import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide RepeatMode;
import 'package:just_audio/just_audio.dart';

import 'player_controller.dart';

const String _kSnapshotKey = 'playback.snapshot.v1';

/// Production [PlayerController] backed by just_audio + audio_service.
///
/// Everything engine-specific lives here. Consumers see only
/// [PlayerController] types.
class JustAudioController extends BaseAudioHandler
    with WidgetsBindingObserver
    implements PlayerController {
  JustAudioController({
    required PlayerPersistence playbackStorage,
    required Future<List<SongRef>> Function(List<String>) songResolver,
    AudioPlayer? player,
    PlaybackStatsSink? onTrackStarted,
  }) : _persistence = playbackStorage,
       _resolveSongs = songResolver,
       _onTrackStarted = onTrackStarted,
       _player = player ?? AudioPlayer() {
    unawaited(_init());
  }

  /// Boots the handler inside audio_service and returns it ready to use.
  static Future<JustAudioController> create({
    required PlayerPersistence persistence,
    required Future<List<SongRef>> Function(List<String>) resolveSongs,
    PlaybackStatsSink? onTrackStarted,
  }) async {
    return AudioService.init(
      builder: () => JustAudioController(
        playbackStorage: persistence,
        songResolver: resolveSongs,
        onTrackStarted: onTrackStarted,
      ),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'voratube.playback',
        androidNotificationChannelName: 'VoraTube playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  }

  final PlayerPersistence _persistence;
  final PlaybackStatsSink? _onTrackStarted;
  final Future<List<SongRef>> Function(List<String>) _resolveSongs;
  final AudioPlayer _player;

  final _snapshotController = StreamController<PlayerSnapshot>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();

  /// Platform channel to the native loudness enhancer. This is what actually
  /// applies gain above 100% — ExoPlayer/just_audio clamp setVolume to 0..1,
  /// so a >1.0 multiplier alone can never raise the output. The enhancer is
  /// attached to just_audio's Android audio session and raises real gain in
  /// millibels up to its native ceiling. Best-effort: failures are swallowed
  /// (audio still plays at normal volume) and non-Android hosts no-op.
  static const MethodChannel _volumeBoosterChannel = MethodChannel(
    'voratube/volume_booster_v1',
  );

  List<SongRef> _queueRefs = const [];
  PlayerSnapshot _last = PlayerSnapshot.initial;
  StreamSubscription<Duration>? _positionSub;
  final List<StreamSubscription<dynamic>> _sessionSubs = [];
  Timer? _persistDebounce;
  bool _restored = false;
  bool _disposed = false;
  bool _suppressStats = true;
  String? _statLastKey;
  String? _statKey;
  int _statAccumMs = 0;
  int _statLastPosMs = -1;
  bool _pausedByInterruption = false;
  bool _ducked = false;
  double _userVolume = 1.0;
  double _boostMultiplier = 1.0;
  double _preampDb = 0.0;
  bool _boostSessionListening = false;
  ReplayGainMode _replayGainMode = ReplayGainMode.off;
  int _playGeneration = 0;

  /// Monotonic revision of the queue contents. Bumped on every
  /// insert/remove/move/replace so the UI can render queue changes even when
  /// every other snapshot field stays equal (a pure reorder changes nothing
  /// but this counter).
  int _queueRevision = 0;

  /// Whether the user wants playback to continue. Set by the play-oriented
  /// controls and cleared by pause/stop; [`_skipBrokenSource`] leans on it so a
  /// failed first-play keeps going into the next queue item instead of pausing.
  bool _wantPlayback = false;

  /// True between the start and end of a [`_skipBrokenSource`] pass, so a
  /// burst of idle events from one failed source does not fire multiple skips.
  bool _skipInFlight = false;

  /// Consecutive engine-driven auto-skips since the last successfully-loaded
  /// source. Bounds runaway skipping on an all-broken queue so the player stops
  /// cleanly rather than spinning.
  int _consecutiveFailures = 0;

  /// True between the start and end of a [playQueue] transition.
  ///
  /// The stop→setAudioSources→play sequence is multi-await, and just_audio
  /// flushes intermediate engine events (idle, cleared index, loading) along
  /// the way. Those transient snapshots would otherwise be broadcast to the UI
  /// as a flash of "no track" (stale or null current) while rapidly switching
  /// songs A→B→C. Gating [emit] here collapses the whole transition into one
  /// coherent snapshot emitted by the winning generation after it finishes.
  bool _queueTransition = false;

  /// Resolves a system-readable content URI for the artwork at [artPath]
  /// by invoking the ingest bridge's [publishSystemArtwork] method.
  /// Returns the [Uri] if successful, otherwise null.
  /// This is best-effort; if it fails the original [file://] URI is kept.
  Future<Uri?> _resolveSystemArtUri(String artPath) async {
    if (artPath.isEmpty) return null;
    // Derive a stable key from the filename stem (e.g. ms_5214426321079491600)
    final name = artPath.split(Platform.pathSeparator).last;
    var stem = name.replaceFirst('.webp', '');
    if (stem.endsWith('_l')) stem = stem.substring(0, stem.length - 2);
    if (stem.endsWith('_s')) stem = stem.substring(0, stem.length - 2);
    final key = stem;
    try {
      final result = await MethodChannel('voratube/ingest_v1')
          .invokeMethod<String>('publishSystemArtwork', {
            'artPath': artPath,
            'key': key,
          });
      if (result == null || result.isEmpty) return null;
      return Uri.tryParse(result);
    } catch (e) {
      return null;
    }
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _sessionSubs.add(
      session.interruptionEventStream.listen(_handleInterruption),
    );
    _sessionSubs.add(
      session.becomingNoisyEventStream.listen((_) => _player.pause()),
    );

    _player.processingStateStream.listen(_handleProcessingState);
    _player.playingStream.listen((_) => _emit());
    _player.loopModeStream.listen((_) => _emit());
    _player.shuffleModeEnabledStream.listen((_) => _emit());
    _player.durationStream.listen((_) => _emit());
    _player.currentIndexStream.listen((_) => _onCurrentIndexChanged());

    _positionSub = _player
        .createPositionStream(
          steps: 120,
          minPeriod: const Duration(milliseconds: 200),
          maxPeriod: const Duration(seconds: 1),
        )
        .listen((position) {
          if (!_positionController.isClosed) {
            _positionController.add(position);
          }
          _trackListenedMs(position);
          _schedulePersist();
        });

    // Persist the exact track + position at the moment the app backgrounds or
    // the engine is torn down, so the latest position isn't lost to the
    // debounce window. Reuses the existing persist path; no architecture change.
    WidgetsBinding.instance.addObserver(this);

    await _restoreIfNeeded();
    _suppressStats = false;
    _emit();
  }

  void _handleInterruption(AudioInterruptionEvent event) {
    if (_disposed) {
      return;
    }
    switch (event.type) {
      case AudioInterruptionType.duck:
        _ducked = event.begin;
        unawaited(_applyVolume());
      case AudioInterruptionType.pause:
      case AudioInterruptionType.unknown:
        if (event.begin) {
          _pausedByInterruption = _player.playing;
          _player.pause();
        } else if (_pausedByInterruption &&
            event.type == AudioInterruptionType.pause) {
          _pausedByInterruption = false;
          _player.play();
        } else {
          _pausedByInterruption = false;
        }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Force a final persist when the app leaves the foreground so a process
    // kill can't drop up to the debounce window of the latest restore point.
    // This reuses the existing persist path (true current index + position);
    // it does not change the queue/session architecture.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_persistNow());
    }
  }

  /// Reacts to source-lifecycle changes.
  ///
  /// A source that fails to prepare lands the engine in `idle` with nothing
  /// loadable: just_audio will not advance on its own, so without this the
  /// player would sit on the broken track forever (stale `current`, duration
  /// 0, media-session state NONE — exactly the AutoBackup defect seen in
  /// Phase 3 device verification). Auto-skip instead. Transient idle events
  /// inside a [playQueue] transition are gated by [_queueTransition] so the
  /// coherent snapshot the winning generation emits is never touched.
  void _handleProcessingState(ProcessingState state) {
    if (_disposed) {
      return;
    }
    if (!_queueTransition &&
        state == ProcessingState.idle &&
        _queueRefs.isNotEmpty) {
      unawaited(_skipBrokenSource());
      return;
    }
    if (state == ProcessingState.ready) {
      _consecutiveFailures = 0;
    }
    _emit();
  }

  /// Moves past a source the engine could not load.
  ///
  /// [playQueue] already collapses its own transition into one snapshot, so
  /// only idle events outside a transition reach here. The skip keeps the
  /// user's play intent: when a tap started playback, hitting a broken track
  /// falls through to the next item and playback continues.
  Future<void> _skipBrokenSource() async {
    if (_disposed || _skipInFlight) {
      return;
    }
    _skipInFlight = true;
    try {
      _consecutiveFailures++;
      final total = _player.sequence.length;
      final wasPlaying = _wantPlayback;
      if (total == 0 || _consecutiveFailures > total) {
        // Nothing to play (single-track stop, or every item failed):
        // release cleanly instead of looping forever.
        _consecutiveFailures = 0;
        _wantPlayback = false;
        try {
          await _player
              .setAudioSources(const [])
              .timeout(const Duration(seconds: 3));
        } catch (_) {
          // Best-effort release; the next playQueue rebuilds from scratch.
        }
        _queueRefs = const [];
        _schedulePersist(immediate: true);
        _emit();
        return;
      }
      if (_player.hasNext) {
        await _player.seekToNext();
        // play() is dispatched: awaiting it here has the same hang hazard as
        // playQueue, and a stalled skip would leave [_skipInFlight] set so no
        // later broken source could ever be skipped again.
        if (wasPlaying) {
          unawaited(_player.play());
        }
        return;
      }
      // The last queue item is unplayable. More than one item: wrap to the top
      // so a repeat-enabled queue self-heals. A single broken track has nowhere
      // to go: stop cleanly.
      if (total > 1) {
        await _player.seek(Duration.zero, index: 0);
        if (wasPlaying) {
          unawaited(_player.play());
        }
      } else {
        _wantPlayback = false;
        try {
          await _player
              .setAudioSources(const [])
              .timeout(const Duration(seconds: 3));
        } catch (_) {
          // Best-effort release; the next playQueue rebuilds from scratch.
        }
        _queueRefs = const [];
        _schedulePersist(immediate: true);
        _emit();
      }
    } finally {
      _skipInFlight = false;
    }
  }

  // -------------------------------------------------------------------------
  // PlayerController
  // -------------------------------------------------------------------------

  @override
  Stream<PlayerSnapshot> get snapshot => _snapshotController.stream;

  @override
  Stream<Duration> get positions => _positionController.stream;

  @override
  PlayerSnapshot get current => _last;

  @override
  Future<void> playQueue(List<SongRef> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) {
      return;
    }
    final gen = ++_playGeneration;
    final safeIndex = startIndex.clamp(0, songs.length - 1);
    _queueTransition = true;
    _wantPlayback = true;
    // Bind the refs before touching the engine so the index reported by any
    // engine event after setAudioSources always resolves against the queue it
    // belongs to, never the previous one.
    _queueRefs = List.unmodifiable(songs);
    _queueRevision++;
    try {
      // The stop is a request, not a gate: just_audio's stop()-then-setAudioSources
      // ordering only matters for the engine's internal sequence swap, which
      // setAudioSources performs anyway. Stopping is dispatched (never awaited)
      // because awaiting a just_audio engine call here can hang the whole
      // transition, stranding the player in [_queueTransition] with emissions
      // suppressed — the same hazard class as the play() hang.
      unawaited(_player.stop());
      await _player.setAudioSources([
        for (final s in songs) _sourceFor(s),
      ], initialIndex: safeIndex);
      if (gen != _playGeneration) {
        return;
      }
      await _syncQueueMetadata();
      // just_audio's [play] future can hang even though the engine starts and
      // runs normally (position stream keeps advancing). Awaiting it would
      // strand the transition in [_queueTransition] and freeze every later
      // [emit]. Dispatch instead; the engine's own event streams drive the
      // snapshots.
      unawaited(_player.play());
      _schedulePersist(immediate: true);
    } finally {
      // Only the winning generation clears the transition flag and emits the
      // final coherent snapshot; a superseded call (gen) leaves the flag set so
      // the newer transition keeps suppressing transient emissions.
      if (gen == _playGeneration) {
        _queueTransition = false;
        _emit();
        // Record the first-play AFTER the transition lifts: called inside the
        // transition it would be gated out, so the first track of a tap-to-play
        // never incremented stats. Skip when the loaded item could not be
        // prepared (engine idle) so broken files are never counted as plays.
        if (_player.processingState != ProcessingState.idle) {
          _maybeRecordStat(_currentRef());
        }
      }
    }
  }

  @override
  Future<void> togglePlay() async {
    if (_player.playing) {
      _wantPlayback = false;
      await _player.pause();
    } else {
      _wantPlayback = true;
      // play() is dispatched, never awaited: its future can hang even though
      // the engine starts (see playQueue). Awaiting here stalled the resume
      // path used by Continue Listening, the MiniPlayer and the full player.
      unawaited(_player.play());
    }
  }

  /// System media-session / notification **Play**.
  ///
  /// audio_service dispatches transport actions from the Android lock screen,
  /// the media notification, Bluetooth and wired-headset buttons through the
  /// [BaseAudioHandler] callbacks. Their default implementations are empty
  /// stubs, so before this override the play button on the lock screen /
  /// notification silently did nothing even though in-app controls worked.
  /// Route it onto the same engine the in-app controls use. Mirror
  /// [togglePlay]'s dispatch-only pattern to dodge the just_audio pick hang.
  @override
  Future<void> play() async {
    _wantPlayback = true;
    unawaited(_player.play());
  }

  /// Lock screen / notification **Next**.
  ///
  /// Routes the system `skipToNext` callback onto the same engine the in-app
  /// next button uses (fixes the empty-stub no-op for media buttons).
  @override
  Future<void> skipToNext() => next();

  /// Lock screen / notification **Previous**.
  ///
  /// Routes the system `skipToPrevious` callback onto the same engine the
  /// in-app previous button uses (fixes the empty-stub no-op for media
  /// buttons).
  @override
  Future<void> skipToPrevious() => previous();

  @override
  Future<void> pause() {
    _wantPlayback = false;
    _flushCurrentHeard();
    return _player.pause();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> seekBy(Duration offset) async {
    await _player.seek(clampSeekBy(_player.position, offset, _player.duration));
  }

  @override
  Future<void> next() => _player.seekToNext();

  @override
  Future<void> previous() => _player.seekToPrevious();

  @override
  Future<void> jumpTo(int index) async {
    final length = _player.sequence.length;
    if (index < 0 || index >= length) {
      return;
    }
    _wantPlayback = true;
    await _player.seek(Duration.zero, index: index);
    unawaited(_player.play());
  }

  @override
  Future<void> enqueue(SongRef song) async {
    await _player.addAudioSource(_sourceFor(song));
    _queueRefs = [..._queueRefs, song];
    await _syncQueueMetadata();
    _broadcastQueueChange();
    _schedulePersist(immediate: true);
  }

  @override
  Future<void> playNext(SongRef song) async {
    final index = _player.sequenceState.currentIndex ?? -1;
    final insertAt = (index + 1).clamp(0, _player.sequence.length);
    await _player.insertAudioSource(insertAt, _sourceFor(song));
    final updated = [..._queueRefs];
    updated.insert(insertAt.clamp(0, updated.length), song);
    _queueRefs = List.unmodifiable(updated);
    await _syncQueueMetadata();
    _broadcastQueueChange();
    _schedulePersist(immediate: true);
  }

  @override
  Future<void> removeAt(int index) async {
    final length = _player.sequence.length;
    if (index < 0 || index >= length) {
      return;
    }
    await _player.removeAudioSourceAt(index);
    _queueRefs = [
      for (var i = 0; i < _queueRefs.length; i++)
        if (i != index) _queueRefs[i],
    ];
    await _syncQueueMetadata();
    _broadcastQueueChange();
    _schedulePersist(immediate: true);
  }

  @override
  Future<void> move(int fromIndex, int toIndex) async {
    final length = _player.sequence.length;
    if (fromIndex < 0 ||
        toIndex < 0 ||
        fromIndex >= length ||
        toIndex >= length) {
      return;
    }
    await _player.moveAudioSource(fromIndex, toIndex);
    final updated = [..._queueRefs];
    final moved = updated.removeAt(fromIndex);
    updated.insert(toIndex, moved);
    _queueRefs = List.unmodifiable(updated);
    _broadcastQueueChange();
    _schedulePersist(immediate: true);
  }

  @override
  Future<void> moveQueueItem(int fromIndex, int toIndex) async {
    await move(fromIndex, toIndex);
  }

  @override
  Future<void> clearQueue() async {
    final currentIndex = _player.sequenceState.currentIndex ?? 0;
    final currentRef = currentIndex < _queueRefs.length
        ? _queueRefs[currentIndex]
        : null;

    if (currentRef != null) {
      await _player.setAudioSources([_sourceFor(currentRef)], initialIndex: 0);
      _queueRefs = List.unmodifiable([currentRef]);
      _broadcastQueueChange();
      _schedulePersist(immediate: true);
    }
  }

  @override
  List<SongRef> get currentQueue => List<SongRef>.of(_queueRefs);

  @override
  Future<void> stop() async {
    _wantPlayback = false;
    _statLastKey = null;
    _queueRefs = const [];
    // Clear the UI state unconditionally, before touching the engine: the
    // sequence must never linger as an orphan AudioTrack playing with no UI.
    _queueRevision++;
    _schedulePersist(immediate: true);
    _emit();
    // Stop first: this reliably releases the audio sink. Clearing the sequence
    // while playback is active is what wedges the platform thread on some
    // devices (ExoPlayer eagerly loads the first item to preload), leaving the
    // old queue decoding in the background with no UI — the observed raster
    // lockup / orphan-track class. Correct order is stop, then empty swap.
    try {
      await _player.stop().timeout(const Duration(seconds: 3));
    } catch (_) {
      // The engine settles on its own; never let a stalled stop block the UI.
    }
    try {
      await _player
          .setAudioSources(const [])
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Best-effort: the queue snapshot is already empty, so the next playQueue
      // rebuilds the engine state from scratch regardless.
    }
  }

  @override
  Future<void> setShuffle(bool enabled) async {
    await _player.setShuffleModeEnabled(enabled);
    _schedulePersist(immediate: true);
  }

  @override
  Future<void> setRepeat(RepeatMode mode) async {
    await _player.setLoopMode(switch (mode) {
      RepeatMode.off => LoopMode.off,
      RepeatMode.all => LoopMode.all,
      RepeatMode.one => LoopMode.one,
    });
    _schedulePersist(immediate: true);
  }

  @override
  ReplayGainMode get replayGainMode => _replayGainMode;

  @override
  Future<void> setReplayGainMode(
    ReplayGainMode mode, {
    double preampDb = 0,
  }) async {
    _replayGainMode = mode;
    _preampDb = preampDb.clamp(-12.0, 12.0);
    unawaited(_applyVolume());
    _schedulePersist(immediate: true);
  }

  @override
  Future<void> setVolume(double volume) async {
    _userVolume = volume.clamp(0.0, 1.0);
    await _applyVolume();
  }

  @override
  Future<void> setVolumeBoost(double multiplier) async {
    _boostMultiplier = multiplier.clamp(1.0, 2.0);
    await _applyVolume();
    // Real gain above 100% cannot go through just_audio/ExoPlayer (volume is
    // clamped to 0..1), so drive it through the native loudness enhancer.
    await _applyBoostGain();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _flushCurrentHeard();
    _persistDebounce?.cancel();
    await _persistNow();
    await _positionSub?.cancel();
    for (final sub in _sessionSubs) {
      await sub.cancel();
    }
    await _snapshotController.close();
    await _positionController.close();
    await _player.dispose();
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  AudioSource _sourceFor(SongRef song) {
    final parsed = Uri.tryParse(song.uri);
    final uri = (parsed != null && parsed.hasScheme)
        ? parsed
        : Uri.file(song.uri);
    return AudioSource.uri(uri, tag: song.identityKey);
  }

  Future<void> _syncQueueMetadata() async {
    final items = [for (final s in _queueRefs) _mediaItemFor(s)];
    queue.add(items);
    await _syncCurrentMediaItem();
  }

  void _onCurrentIndexChanged() {
    _syncCurrentMediaItem();
    _maybeRecordStat(_currentRef());
    // Replay gain is per-track: reapply whenever the track changes.
    unawaited(_applyVolume());
    // Broadcast the new track so the MiniPlayer and full player refresh their
    // metadata. Without this, _syncCurrentMediaItem only updates the media
    // notification; the PlayerSnapshot stream that the UI watches is never
    // updated on an engine-driven track change (next/previous/auto-advance).
    _emit();
  }

  /// Records a play when a *distinct* track starts. Suppressed while the
  /// persisted queue is being restored so launches never inflate counts.
  ///
  /// When switching away from a tracked song, it first credits that song's
  /// measured listening time, then records the fresh start of the new track.
  void _maybeRecordStat(SongRef? ref) {
    if (ref == null || _suppressStats) {
      return;
    }
    if (_queueTransition) {
      return;
    }
    if (_statLastKey == ref.identityKey) {
      return;
    }
    // Credit the song we are leaving with the time the engine actually heard.
    if (_statKey != null && _statAccumMs > 0) {
      _onTrackStarted?.call(_statKey!, _statAccumMs);
    }
    _statLastKey = ref.identityKey;
    _statKey = ref.identityKey;
    _statAccumMs = 0;
    _statLastPosMs = -1;
    _onTrackStarted?.call(ref.identityKey, 0);
  }

  /// Accumulates real listening time for the current tracked song using
  /// position deltas, only while the engine is playing that same song.
  /// Paused/stopped time never accumulates, and backwards seeks never inflate
  /// the count.
  void _trackListenedMs(Duration position) {
    if (!_player.playing || _suppressStats || _statKey == null) {
      _statLastPosMs = -1;
      return;
    }
    final key = _currentRef()?.identityKey;
    if (key == null || key != _statKey) {
      _statLastPosMs = -1;
      return;
    }
    final posMs = position.inMilliseconds;
    if (_statLastPosMs >= 0) {
      final delta = posMs - _statLastPosMs;
      if (delta > 0) {
        _statAccumMs += delta;
      }
    }
    _statLastPosMs = posMs;
  }

  /// Credits and resets the current tracked song's measured listening time.
  /// Called when playback stops or pauses, so no heard time is lost, and
  /// paused/stopped time is never booked.
  void _flushCurrentHeard() {
    if (_statKey != null && _statAccumMs > 0) {
      _onTrackStarted?.call(_statKey!, _statAccumMs);
    }
    _statKey = null;
    _statAccumMs = 0;
    _statLastPosMs = -1;
  }

  /// dB → linear multiplier (0 dB → 1.0).
  double _dbToLinear(double db) => math.pow(10.0, db / 20.0).toDouble();

  /// Recomputes and applies the engine output volume.
  ///
  /// Effective volume = user multiplier × gain multiplier × duck factor. The
  /// gain multiplier is the preamp when ReplayGain is off, or the current
  /// track's stored ReplayGain info (preamp-inclusive, peak-protected) when
  /// on. just_audio/ExoPlayer clamps engine volume to 0..1, so the result is
  /// clamped defensively. The Volume Booster does NOT appear here: gain above
  /// 100% is applied separately by the native loudness enhancer
  /// ([_applyBoostGain]), so the two layers compose additively without ever
  /// being double-counted or fighting over the 0..1 clamp.
  Future<void> _applyVolume() async {
    if (_disposed) {
      return;
    }
    final ref = _currentRef();
    // Preamp scaling applies in every mode (0 dB = no change), so the setting
    // has a real, predictable effect even for libraries with no ReplayGain tags.
    final preampLinear = _dbToLinear(_preampDb);
    final gainMultiplier = switch (_replayGainMode) {
      ReplayGainMode.off => preampLinear,
      ReplayGainMode.track =>
        ref?.replayGain?.trackGainMultiplier(preampDb: _preampDb) ??
            preampLinear,
      ReplayGainMode.album =>
        ref?.replayGain?.albumGainMultiplier(preampDb: _preampDb) ??
            preampLinear,
    };
    final duckFactor = _ducked ? 0.33 : 1.0;
    final effective = (_userVolume * gainMultiplier * duckFactor).clamp(
      0.0,
      1.0,
    );
    try {
      await _player.setVolume(effective);
    } catch (e) {
      debugPrint('VoraTube setVolume failed: $e');
    }
  }

  /// Applies the current Volume Booster as real gain on the native loudness
  /// enhancer attached to just_audio's Android audio session.
  ///
  /// This is the layer that actually raises playback above 100%. It is
  /// best-effort and evergreen: it subscribes once to the audio-session stream
  /// so the enhancer is (re)attached whenever ExoPlayer assigns a session, and
  /// it always mirrors the latest multiplier — so session changes, track
  /// transitions, pause/resume and a live 100→150→200→100 sweep all keep the
  /// gain correct. On non-Android hosts or when the platform channel is
  /// missing, it silently no-ops and playback continues at normal volume.
  Future<void> _applyBoostGain() async {
    if (_disposed || !Platform.isAndroid) {
      return;
    }
    _ensureBoostSessionListener();
    final sessionId = _player.androidAudioSessionId;
    if (sessionId == null) {
      // No session yet (e.g. boosted before anything plays); the listener
      // above will apply the gain as soon as ExoPlayer exposes a session.
      return;
    }
    final millibel = volumeBoostMillibel(_boostMultiplier);
    try {
      await _volumeBoosterChannel.invokeMethod<void>(
        'attach',
        <String, dynamic>{'sessionId': sessionId},
      );
      await _volumeBoosterChannel.invokeMethod<void>(
        'setGain',
        <String, dynamic>{'millibel': millibel},
      );
    } catch (e) {
      debugPrint('VoraTube volume booster failed: $e');
    }
  }

  /// Subscribes (once) to just_audio's audio-session stream so the loudness
  /// enhancer is attached as soon as ExoPlayer publishes a session, and is
  /// re-attached if that session ever changes (e.g. fresh playback start).
  void _ensureBoostSessionListener() {
    if (_boostSessionListening) {
      return;
    }
    _boostSessionListening = true;
    _sessionSubs.add(
      _player.androidAudioSessionIdStream.distinct().listen((_) {
        if (_boostMultiplier > 1.0) {
          unawaited(_applyBoostGain());
        }
      }),
    );
  }

  Future<void> _syncCurrentMediaItem() async {
    final ref = _currentRef();
    // Add provisional media item (with file URI – works in‑process for notification)
    mediaItem.add(ref == null ? null : _mediaItemFor(ref));

    // Attempt to resolve a system-readable artUri for the lock-screen/media-card.
    // This is best-effort; if it succeeds the media item is refreshed with the
    // content-URI so that SystemUI (MediaDataManager) can load the artwork.
    final artPath = ref?.artPath;
    if (artPath != null && artPath.isNotEmpty) {
      try {
        final sysUri = await _resolveSystemArtUri(artPath);
        if (sysUri != null && !_disposed) {
          // Refresh the media item only if the same track is still current
          final r = _currentRef();
          if (r != null && r.artPath == artPath) {
            mediaItem.add(_mediaItemFor(r, artUri: sysUri));
          }
        }
      } catch (e) {
        // ignore; provisional item already added
      }
    }
  }

  SongRef? _currentRef() {
    final index = _player.sequenceState.currentIndex;
    if (index == null || index < 0) {
      return null;
    }
    if (index >= _queueRefs.length) {
      return null;
    }
    return _queueRefs[index];
  }

  MediaItem _mediaItemFor(SongRef song, {Uri? artUri}) {
    return MediaItem(
      id: song.identityKey,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.durationMs > 0
          ? Duration(milliseconds: song.durationMs)
          : null,
      artUri:
          artUri ??
          (song.artPath == null || song.artPath!.isEmpty
              ? null
              : Uri.file(song.artPath!)),
    );
  }

  /// Bumps the queue revision and broadcasts a fresh snapshot so widgets that
  /// render the queue (queue sheet, mini player) reflect insert, remove and
  /// move immediately. A pure reorder keeps every other snapshot field equal,
  /// so without the revision [_emit] would deduplicate it and the dragged item
  /// would appear to snap back.
  void _broadcastQueueChange() {
    _queueRevision++;
    _emit();
  }

  void _emit() {
    if (_disposed || _snapshotController.isClosed) {
      return;
    }
    // Collapse queue-transition engine events into the single snapshot the
    // winning playQueue emits at the end, so a rapid A→B→C switch never
    // broadcasts a stale or "no current track" state in between.
    if (_queueTransition) {
      return;
    }
    final state = _player.processingState;
    // During a preload:false restore the engine is idle while a known queue is
    // loaded — report READY so the UI and media session never claim NONE for a
    // track that exists. Only a genuinely empty engine is truly idle.
    final hasKnownQueue = _player.sequence.isNotEmpty;
    final status = switch (state) {
      ProcessingState.idle when hasKnownQueue => PlayerStatus.ready,
      ProcessingState.idle => PlayerStatus.idle,
      ProcessingState.loading => PlayerStatus.loading,
      ProcessingState.buffering => PlayerStatus.ready,
      ProcessingState.ready => PlayerStatus.ready,
      ProcessingState.completed => PlayerStatus.ready,
    };
    final seq = _player.sequenceState;
    final next = PlayerSnapshot(
      status: status,
      isPlaying: _player.playing,
      repeatMode: switch (_player.loopMode) {
        LoopMode.off => RepeatMode.off,
        LoopMode.all => RepeatMode.all,
        LoopMode.one => RepeatMode.one,
      },
      shuffleEnabled: _player.shuffleModeEnabled,
      queueLength: _player.sequence.length,
      currentIndex: seq.currentIndex ?? -1,
      durationMs: _player.duration?.inMilliseconds ?? 0,
      queueRevision: _queueRevision,
      current: _currentRef(),
    );

    if (_sameSnapshot(_last, next)) {
      return;
    }
    _last = next;
    _snapshotController.add(next);
    _broadcastSystemState();
    if (state == ProcessingState.completed) {
      _schedulePersist(immediate: true);
    } else {
      _schedulePersist();
    }
  }

  bool _sameSnapshot(PlayerSnapshot a, PlayerSnapshot b) =>
      a.status == b.status &&
      a.isPlaying == b.isPlaying &&
      a.repeatMode == b.repeatMode &&
      a.shuffleEnabled == b.shuffleEnabled &&
      a.queueLength == b.queueLength &&
      a.currentIndex == b.currentIndex &&
      a.durationMs == b.durationMs &&
      a.queueRevision == b.queueRevision &&
      identical(a.current, b.current);

  void _broadcastSystemState() {
    final state = _player.processingState;
    // Mirror _emit: a restored-but-unloaded queue is READY, not idle, so the
    // system media session never reports NONE for an existing track.
    final hasKnownQueue = _player.sequence.isNotEmpty;
    final processing = switch (state) {
      ProcessingState.idle when hasKnownQueue => AudioProcessingState.ready,
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          if (_player.hasPrevious) MediaControl.skipToPrevious,
          if (_player.playing) MediaControl.pause else MediaControl.play,
          if (_player.hasNext) MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        processingState: processing,
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _player.sequenceState.currentIndex,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Persistence
  // -------------------------------------------------------------------------

  void _schedulePersist({bool immediate = false}) {
    if (_disposed) {
      return;
    }
    if (immediate) {
      _persistDebounce?.cancel();
      _persistDebounce = null;
      unawaited(_persistNow());
      return;
    }
    // A pending flush is not re-armed by further position ticks: while playing,
    // ticks arrive faster than the 2s debounce, so a cancel+restart scheme
    // would starve _persistNow forever and the saved resume position/index
    // would never advance during playback.
    if (_persistDebounce != null) {
      return;
    }
    _persistDebounce = Timer(const Duration(seconds: 2), () {
      _persistDebounce = null;
      unawaited(_persistNow());
    });
  }

  Future<void> _persistNow() async {
    try {
      if (_queueRefs.isEmpty) {
        return;
      }
      final snapshot = QueueSnapshot(
        identityKeys: [
          for (final r in _queueRefs)
            if (r.identityKey.isNotEmpty) r.identityKey,
        ],
        index: _player.sequenceState.currentIndex ?? 0,
        positionMs: _player.position.inMilliseconds,
        shuffleEnabled: _player.shuffleModeEnabled,
        repeatMode: switch (_player.loopMode) {
          LoopMode.all => RepeatMode.all,
          LoopMode.one => RepeatMode.one,
          LoopMode.off => RepeatMode.off,
        },
      );
      await _persistence.write(_kSnapshotKey, snapshot.toJson());
    } catch (e) {
      debugPrint('VoraTube persist failed: $e');
    }
  }

  Future<void> _restoreIfNeeded() async {
    if (_restored) {
      return;
    }
    _restored = true;
    try {
      final raw = await _persistence.read(_kSnapshotKey);
      if (raw == null || raw.isEmpty) {
        return;
      }
      final saved = QueueSnapshot.fromJson(raw);
      if (saved.isEmpty) {
        return;
      }
      final songs = await _resolveSongs(saved.identityKeys);
      if (songs.isEmpty) {
        return;
      }
      // Preserve saved ordering where possible.
      final byKey = {for (final s in songs) s.identityKey: s};
      final ordered = [
        for (final k in saved.identityKeys)
          if (byKey[k] != null) byKey[k]!,
      ];
      if (ordered.isEmpty) {
        return;
      }
      final index = saved.index.clamp(0, ordered.length - 1);
      _queueRefs = List.unmodifiable(ordered);
      await _player.setAudioSources(
        [for (final s in ordered) _sourceFor(s)],
        preload: false,
        initialIndex: index,
        initialPosition: Duration(milliseconds: saved.positionMs),
      );
      // A preload:false restore leaves the engine idle: no item is loaded, the
      // saved position is never applied, and (because processingState stays
      // idle) the media session broadcasts NONE with position 0 while the
      // restored queue hides a real current track — the "Continue Listening
      // shows NONE" defect. Seek to the saved index to load that item headfully
      // (without starting playback), which applies the saved position and puts
      // the engine in READY/PAUSED so lock-screen/notification controls and the
      // player UI agree with the restored queue.
      await _player.seek(
        Duration(milliseconds: saved.positionMs),
        index: index,
      );
      await _player.setShuffleModeEnabled(saved.shuffleEnabled);
      await setRepeat(saved.repeatMode);
      await _syncQueueMetadata();
      final restoredRef = index < ordered.length ? ordered[index] : null;
      if (restoredRef != null) {
        _statLastKey = restoredRef.identityKey;
      }
      _queueRevision++;
      debugPrint(
        'VoraTube restored queue (${ordered.length} tracks @ '
        '${saved.positionMs}ms)',
      );
    } catch (e) {
      debugPrint('VoraTube restore failed: $e');
    }
  }
}

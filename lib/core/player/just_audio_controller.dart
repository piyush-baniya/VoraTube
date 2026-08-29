import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'player_controller.dart';

const String _kSnapshotKey = 'playback.snapshot.v1';

/// Production [PlayerController] backed by just_audio + audio_service.
///
/// Everything engine-specific lives here. Consumers see only
/// [PlayerController] types.
class JustAudioController extends BaseAudioHandler implements PlayerController {
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
  ReplayGainMode _replayGainMode = ReplayGainMode.off;
  int _playGeneration = 0;

  /// True between the start and end of a [playQueue] transition.
  ///
  /// The stop→setAudioSources→play sequence is multi-await, and just_audio
  /// flushes intermediate engine events (idle, cleared index, loading) along
  /// the way. Those transient snapshots would otherwise be broadcast to the UI
  /// as a flash of "no track" (stale or null current) while rapidly switching
  /// songs A→B→C. Gating [emit] here collapses the whole transition into one
  /// coherent snapshot emitted by the winning generation after it finishes.
  bool _queueTransition = false;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _sessionSubs.add(
      session.interruptionEventStream.listen(_handleInterruption),
    );
    _sessionSubs.add(
      session.becomingNoisyEventStream.listen((_) => _player.pause()),
    );

    _player.processingStateStream.listen((_) => _emit());
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
    // Bind the refs before touching the engine so the index reported by any
    // engine event after setAudioSources always resolves against the queue it
    // belongs to, never the previous one.
    _queueRefs = List.unmodifiable(songs);
    try {
      await _player.stop();
      if (gen != _playGeneration) {
        return;
      }
      await _player.setAudioSources([
        for (final s in songs) _sourceFor(s),
      ], initialIndex: safeIndex);
      if (gen != _playGeneration) {
        return;
      }
      await _syncQueueMetadata();
      if (gen != _playGeneration) {
        return;
      }
      await _player.play();
      _maybeRecordStat(_currentRef());
      _schedulePersist(immediate: true);
    } finally {
      // Only the winning generation clears the transition flag and emits the
      // final coherent snapshot; a superseded call (gen) leaves the flag set so
      // the newer transition keeps suppressing transient emissions.
      if (gen == _playGeneration) {
        _queueTransition = false;
        _emit();
      }
    }
  }

  @override
  Future<void> togglePlay() async =>
      _player.playing ? _player.pause() : _player.play();

  @override
  Future<void> pause() {
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
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  @override
  Future<void> enqueue(SongRef song) async {
    await _player.addAudioSource(_sourceFor(song));
    _queueRefs = [..._queueRefs, song];
    await _syncQueueMetadata();
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
      _schedulePersist(immediate: true);
    }
  }

  @override
  List<SongRef> get currentQueue => List<SongRef>.of(_queueRefs);

  @override
  Future<void> stop() async {
    await _player.setAudioSources(const []);
    _queueRefs = const [];
    _statLastKey = null;
    _schedulePersist(immediate: true);
    _emit();
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
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
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
  /// Effective volume = user multiplier × volume boost × gain multiplier
  /// × duck factor. The gain multiplier is the preamp when ReplayGain is off,
  /// or the current track's stored ReplayGain info (preamp-inclusive,
  /// peak-protected) when on. just_audio/ExoPlayer clamps engine volume to
  /// 0..1, so the result is clamped defensively; the boost lets playback reach
  /// native maximum faster but cannot exceed the engine ceiling, so it is
  /// distortion-safe.
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
    final effective =
        (_userVolume * _boostMultiplier * gainMultiplier * duckFactor).clamp(
          0.0,
          1.0,
        );
    try {
      await _player.setVolume(effective);
    } catch (e) {
      debugPrint('VoraTube setVolume failed: $e');
    }
  }

  Future<void> _syncCurrentMediaItem() async {
    final ref = _currentRef();
    mediaItem.add(ref == null ? null : _mediaItemFor(ref));
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

  MediaItem _mediaItemFor(SongRef song) {
    return MediaItem(
      id: song.identityKey,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.durationMs > 0
          ? Duration(milliseconds: song.durationMs)
          : null,
      artUri: song.artPath == null || song.artPath!.isEmpty
          ? null
          : Uri.file(song.artPath!),
    );
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
    final status = switch (state) {
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
      identical(a.current, b.current);

  void _broadcastSystemState() {
    final state = _player.processingState;
    final processing = switch (state) {
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
      unawaited(_persistNow());
      return;
    }
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(seconds: 2), () {
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
      final index = saved.index.clamp(0, ordered.length - 1);
      _queueRefs = List.unmodifiable(ordered);
      await _player.setAudioSources(
        [for (final s in ordered) _sourceFor(s)],
        preload: false,
        initialIndex: index,
        initialPosition: Duration(milliseconds: saved.positionMs),
      );
      await _player.setShuffleModeEnabled(saved.shuffleEnabled);
      await setRepeat(saved.repeatMode);
      await _syncQueueMetadata();
      final restoredRef = index < ordered.length ? ordered[index] : null;
      if (restoredRef != null) {
        _statLastKey = restoredRef.identityKey;
      }
      debugPrint(
        'VoraTube restored queue (${ordered.length} tracks @ '
        '${saved.positionMs}ms)',
      );
    } catch (e) {
      debugPrint('VoraTube restore failed: $e');
    }
  }
}

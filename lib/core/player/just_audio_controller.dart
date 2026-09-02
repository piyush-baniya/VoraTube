import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide RepeatMode;
import 'package:just_audio/just_audio.dart';

import 'player_controller.dart';
import 'queue_order.dart';

const String _kSnapshotKey = 'playback.snapshot.v1';

/// Decides the millisecond position a restored session should resume from.
///
/// Negative saved positions clamp to 0, and a position at or beyond the
/// track's known [durationMs] (e.g. the persist raced a natural completion,
/// or the file changed length between sessions) restarts the track from 0
/// instead of seeking into an invalid range that would make the restored
/// source complete instantly. An unknown duration (0) keeps the saved value.
int clampResumeMs(int savedPositionMs, int durationMs) {
  if (savedPositionMs < 0) {
    return 0;
  }
  if (durationMs > 0 && savedPositionMs >= durationMs) {
    return 0;
  }
  return savedPositionMs;
}

/// Position-stream resolution used for lyrics highlight, progress bar and the
/// listening-time accumulator. A fixed ~200 ms period keeps the lyrics
/// highlight in step with the actual playback position (a coarse maxPeriod of
/// up to 1 s previously made lines lag by up to a full second). just_audio
/// clamps the effective period to [minPeriod, maxPeriod].
const int positionStreamSteps = 800;
const Duration positionStreamMinPeriod = Duration(milliseconds: 200);
const Duration positionStreamMaxPeriod = Duration(milliseconds: 200);

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
        // Not ongoing so the media notification is user-dismissible: an
        // `ongoing` notification is flagged NO_CLEAR and the user literally
        // cannot swipe it away (it reappears), which the user reported as
        // "can't remove the notification". Background playback still persists
        // regardless, because the service is a foreground service.
        androidNotificationOngoing: false,
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

  /// Authoritative current-first queue: `_queueRefs[0]` is ALWAYS the
  /// currently-playing (or selected) song. The engine loads exactly one source
  /// at a time from this list, so the displayed queue, the Dart state and the
  /// actual playback order are the same single list — there is never a hidden
  /// engine ordering to drift away from. Repeat All/Off and rotation are
  /// implemented here; just_audio is used purely as a one-track engine.
  List<SongRef> _queueRefs = const [];

  /// Authoritative repeat mode. Mirrored to the engine only for the one-track
  /// behaviour (LoopMode.one for Repeat One, else off), but reported to the UI
  /// from here so Repeat All reports `all` even though the engine never loops
  /// natively.
  RepeatMode _repeatMode = RepeatMode.off;

  /// Authoritative shuffle flag. Shuffle reorders [_queueRefs] (current kept at
  /// front); just_audio's own shuffle is never engaged, so only this ordering
  /// matters.
  bool _shuffleEnabled = false;

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

  /// True between the start and end of a queue transition (playQueue, advance,
  /// jump, remove-current, restore).
  ///
  /// The single-source engine's setAudioSource→play sequence is multi-await,
  /// and just_audio flushes intermediate engine events (idle, loading, no
  /// current) along the way. Those transient snapshots would otherwise be
  /// broadcast to the UI as a flash of "no track" or wrong ordering while
  /// switching songs A→B→C. Gating [emit] here collapses the whole transition
  /// into one coherent snapshot emitted by the winning generation after it
  /// finishes.
  bool _queueTransition = false;

  /// True from when a persisted session is restored until the next explicit
  /// [playQueue] starts a brand-new session.
  ///
  /// At cold start the restored engine's single source can transiently land in
  /// `idle` (media URI not yet resolvable, permission check pending, a
  /// momentary platform re-init) before it becomes `ready`. Without this guard
  /// [_skipBrokenSource] would treat that transient idle as a broken file,
  /// drop the current-first song and — if it keeps happening — empty the queue
  /// and persist an empty snapshot, which is exactly the "queue cleared after
  /// restart" symptom this prevents. While a restored session is protected we
  /// never auto-advance or clear; we only idle the engine, keeping the
  /// persisted snapshot intact until the user explicitly acts.
  bool _protectingRestoredSession = false;

  Future<void> _init() async {
    if (Platform.isAndroid) {
      // Remove artwork rows previously copied into MediaStore Downloads by the
      // old publishSystemArtwork flow (they showed up in gallery apps).
      unawaited(
        const MethodChannel('voratube/ingest_v1')
            .invokeMethod<void>('cleanupPublishedArtwork')
            .catchError((_) {}),
      );
    }
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

    // Position stream resolution: ~200 ms fixed cadence (just_audio's native
    // default). The lyrics highlight follows this stream, so a coarse period
    // (previously up to 1 s for songs longer than ~2 min) made the active line
    // lag up to a full second behind the actual playback position. Seeks still
    // emit immediately via playbackEventStream. The stats accumulator is
    // delta-based between successive samples, so a finer cadence does not
    // change recorded listening time.
    _positionSub = _player
        .createPositionStream(
          steps: positionStreamSteps,
          minPeriod: positionStreamMinPeriod,
          maxPeriod: positionStreamMaxPeriod,
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
        } else if (_pausedByInterruption) {
          // Resume on ANY interrupted-while-playing end, not just the `pause`
          // type. Some Android sources report a transient focus interruption as
          // `unknown`, and previously the resume branch was gated on
          // `event.type == pause`, so such an interruption left the player
          // silently paused in the background until the user pressed Play.
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

  @override
  Future<void> onNotificationDeleted() async {
    await super.onNotificationDeleted();
  }

  /// Called by audio_service when the app task is removed from recents.
  ///
  /// The process may be killed immediately after this callback returns, so the
  /// persist **must** complete before we yield control back to the native side.
  /// Unlike [didChangeAppLifecycleState] (which uses [unawaited] because the
  /// framework expects synchronous lifecycle callbacks), here we can safely
  /// await the database write.
  @override
  Future<void> onTaskRemoved() async {
    await _persistNow();
  }

  /// Reacts to source-lifecycle changes.
  ///
  /// The engine always holds exactly one source (the current-first song), so:
  /// - `idle` means the current source could not be loaded → auto-skip to keep
  ///   the play intent alive (a broken file falls through to the next track).
  /// - `completed` means the current song finished naturally → apply the repeat
  ///   policy (Repeat Off removes it, Repeat All moves it to the end, Repeat One
  ///   repeats in place via the engine's loop mode). Transient events inside a
  ///   [playQueue] transition are gated by [_queueTransition] so the coherent
  ///   snapshot the winning generation emits is never touched.
  void _handleProcessingState(ProcessingState state) {
    if (_disposed) {
      return;
    }
    if (_queueTransition) {
      return;
    }
    if (_queueRefs.isEmpty) {
      return;
    }
    if (state == ProcessingState.idle) {
      unawaited(_skipBrokenSource());
      return;
    }
    if (state == ProcessingState.completed) {
      // Repeat One never advances: just_audio's LoopMode.one loops the same
      // source in place, so the current song stays #1 and plays again. Only
      // Repeat Off / All rotate or remove on a natural finish.
      if (_repeatMode != RepeatMode.one) {
        unawaited(_onTrackFinished());
      }
      return;
    }
    if (state == ProcessingState.ready) {
      _consecutiveFailures = 0;
    }
    _emit();
  }

  /// Applies the repeat policy after the current song finished naturally.
  ///
  /// Current-first invariant: [_queueRefs][0] was the finished song.
  /// - Repeat Off: drop it. If that empties the queue, stop cleanly.
  /// - Repeat All: move it to the END so the next song becomes #1 and plays,
  ///   and the finished one plays again only after the whole queue turns over.
  Future<void> _onTrackFinished() async {
    if (_queueRefs.isEmpty || _queueTransition || _disposed) {
      return;
    }
    _queueTransition = true;
    try {
      _queueRefs = List.unmodifiable(
        applyRepeatFinish(_queueRefs, _repeatMode),
      );
      _queueRevision++;
      if (_queueRefs.isEmpty) {
        final gen = ++_playGeneration;
        _wantPlayback = false;
        await _clearEngine();
        if (gen == _playGeneration) {
          _emit();
        }
        return;
      }
      await _loadCurrent();
      // Explicitly re-issue play on a natural completion. Until this point the
      // next source only auto-plays because the engine's `playing` flag stayed
      // true across setAudioSource. In the background that flag can be dropped
      // by the time a track finishes (a transient interruption, a momentary
      // STATE_IDLE while the platform re-arms, ExoPlayer recycling) — in which
      // case the next song loads but never starts, leaving playback silently
      // paused until the user reopens the app and presses Play. Re-issuing
      // play() here (matching _advance/jumpTo/_skipBrokenSource) makes the
      // auto-advance resilient: it is a no-op if already playing.
      if (_wantPlayback && _queueRefs.isNotEmpty) {
        unawaited(_player.play());
      }
    } finally {
      if (!_disposed) {
        _queueTransition = false;
        _emit();
      }
    }
  }

  /// Moves past a source the engine could not load.
  ///
  /// With a single-source engine an unloadable current track lands in `idle`;
  /// treat it like a natural advance but drop the broken song so playback keeps
  /// going. If every item fails, release cleanly instead of spinning forever.
  Future<void> _skipBrokenSource() async {
    if (_disposed || _skipInFlight) {
      return;
    }
    // A freshly-restored session is not "broken" — it just landed in `idle`
    // during cold start (URI not yet resolvable, permission pending). Never
    // auto-advance past or clear it; otherwise a transient idle would wipe the
    // persisted queue the moment the app relaunches. The user must explicitly
    // start playback (or clear) to move on.
    if (_protectingRestoredSession) {
      _wantPlayback = false;
      _emit();
      return;
    }
    _skipInFlight = true;
    try {
      _consecutiveFailures++;
      if (_queueRefs.isEmpty || _consecutiveFailures > _queueRefs.length) {
        // Nothing playable: release cleanly instead of looping forever.
        _consecutiveFailures = 0;
        _wantPlayback = false;
        _queueRefs = const [];
        await _clearEngine();
        _queueRevision++;
        _schedulePersist(immediate: true);
        _emit();
        return;
      }
      // Drop the broken track and advance to the next current-first item.
      _queueRefs = List.unmodifiable(_queueRefs.sublist(1));
      _queueRevision++;
      final wasPlaying = _wantPlayback;
      await _loadCurrent();
      if (wasPlaying && _queueRefs.isNotEmpty) {
        unawaited(_player.play());
      }
    } finally {
      _skipInFlight = false;
    }
  }

  /// Loads the current-first song ([_queueRefs][0]) as the engine's single
  /// source and seeks it ready without necessarily starting playback.
  Future<void> _loadCurrent() async {
    if (_queueRefs.isEmpty) {
      return;
    }
    await _player.setAudioSource(_sourceFor(_queueRefs.first), preload: true);
    await _syncCurrentMediaItem();
  }

  /// Stops the engine and empties its sequence, best-effort.
  Future<void> _clearEngine() async {
    try {
      await _player.stop().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Best-effort; the queue snapshot is authoritative.
    }
    try {
      await _player
          .setAudioSources(const [])
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Best-effort.
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
    // A new explicit session: stop protecting the previously restored one so
    // genuinely broken tracks auto-skip as normal from here on.
    _protectingRestoredSession = false;
    // Rotate so the selected song is at the front (it becomes the current
    // song at #1). If shuffle is on, keep the current first and shuffle the
    // rest — the display, the Dart state and the engine all share this one
    // ordering, so playback always follows the shown queue.
    final ordered = currentFirst(songs, safeIndex) ?? List.of(songs);
    final currentFirstList = List.of(ordered);
    if (_shuffleEnabled && currentFirstList.length > 1) {
      final first = currentFirstList.first;
      final rest = (currentFirstList.sublist(1).toList()..shuffle());
      _queueRefs = List.unmodifiable([first, ...rest]);
    } else {
      _queueRefs = List.unmodifiable(currentFirstList);
    }
    _queueRevision++;
    try {
      // Bind the refs before touching the engine so the index reported by any
      // engine event always resolves against the queue it belongs to.
      await _player.setAudioSource(_sourceFor(_queueRefs.first));
      if (gen != _playGeneration) {
        return;
      }
      await _syncQueueMetadata();
      // just_audio's [play] future can hang even though the engine starts and
      // runs normally (position stream keeps advancing). Awaiting it would
      // strand the transition and freeze every later [emit]. Dispatch instead;
      // the engine's own event streams drive the snapshots.
      unawaited(_player.play());
      _schedulePersist(immediate: true);
    } finally {
      // Only the winning generation clears the transition flag and emits.
      if (gen == _playGeneration) {
        _queueTransition = false;
        _emit();
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
      // The engine must be holding the exact song the UI reports as current.
      // If the engine dropped to `idle` while paused (released source, failed
      // load, platform reclaim) a bare play() would resume whatever stale
      // source the engine last had — a different song than the MiniPlayer
      // shows. Reload the current-first ref so Play always resumes the paused
      // song, then dispatch (never await; see playQueue).
      if (_player.processingState == ProcessingState.idle &&
          _queueRefs.isNotEmpty) {
        await _loadCurrent();
      }
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
    final p = _player.pause();
    // A pause is a deliberate restore point: persist immediately so the saved
    // position matches what the user just heard, instead of waiting for the
    // next debounced tick (which never comes while paused).
    _schedulePersist(immediate: true);
    return p;
  }

  @override
  Future<void> seek(Duration position) {
    final s = _player.seek(position);
    // A seek redefines the meaningful playback position. Schedule (debounced)
    // rather than immediate: rapid scrubbing must not hammer storage, and the
    // pending timer always fires with the final position.
    _schedulePersist();
    return s;
  }

  @override
  Future<void> seekBy(Duration offset) async {
    await _player.seek(clampSeekBy(_player.position, offset, _player.duration));
  }

  @override
  Future<void> next() => _advance(manual: true, backward: false);

  @override
  Future<void> previous() async {
    // If we're more than ~3s into the current song, restart it rather than
    // jumping songs (standard transport behaviour). A single-source engine has
    // no "previous sequence index", so the only way back is to restart the
    // current song or replay from this first-position view.
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    await _advance(manual: true, backward: true);
  }

  /// Moves forward/back one logical track in the current-first queue and plays
  /// the new #1. A manual skip never removes a song (only a natural Repeat-Off
  /// finish removes); the departed song simply wraps to the end so the queue
  /// stays a rotation and current stays at #1.
  Future<void> _advance({required bool manual, required bool backward}) async {
    _wantPlayback = true;
    if (_queueRefs.isEmpty) {
      return;
    }
    if (_queueRefs.length == 1) {
      // Only one song: going "next" restarts it (a single-track Repeat All
      // behaves like a self-loop); there is nothing else to advance to.
      await _player.seek(Duration.zero);
      unawaited(_player.play());
      return;
    }
    _queueTransition = true;
    try {
      // Rotate the current song (index 0) coherently: forward moves it to the
      // end, backward brings the last song to the front. Either way a new song
      // lands at index 0 and becomes current. A manual skip never removes a
      // song (only a natural Repeat-Off finish removes), so the queue stays a
      // rotation and current stays at #1.
      _queueRefs = List.unmodifiable(
        backward ? rotateBackward(_queueRefs) : rotateForward(_queueRefs),
      );
      _queueRevision++;
      _schedulePersist(immediate: true);
      await _loadCurrent();
      unawaited(_player.play());
    } finally {
      _queueTransition = false;
      _emit();
      _maybeRecordStat(_currentRef());
    }
  }

  @override
  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= _queueRefs.length) {
      return;
    }
    _wantPlayback = true;
    if (index == 0) {
      // Already current; just make sure it keeps playing.
      unawaited(_player.play());
      return;
    }
    _queueTransition = true;
    try {
      _queueRefs = List.unmodifiable(currentFirst(_queueRefs, index)!);
      _queueRevision++;
      _schedulePersist(immediate: true);
      await _loadCurrent();
      unawaited(_player.play());
    } finally {
      _queueTransition = false;
      _emit();
      _maybeRecordStat(_currentRef());
    }
  }

  @override
  Future<void> enqueue(SongRef song) async {
    if (_queueRefs.isEmpty) {
      // First song: load it as the current.
      _queueRefs = List.unmodifiable([song]);
      _queueRevision++;
      _wantPlayback = true;
      _queueTransition = true;
      try {
        await _loadCurrent();
        unawaited(_player.play());
      } finally {
        _queueTransition = false;
        _emit();
      }
      await _syncQueueMetadata();
      _broadcastQueueChange();
      _schedulePersist(immediate: true);
      return;
    }
    _queueRefs = List.unmodifiable([..._queueRefs, song]);
    await _syncQueueMetadata();
    _broadcastQueueChange();
    _schedulePersist(immediate: true);
  }

  @override
  Future<void> playNext(SongRef song) async {
    if (_queueRefs.isEmpty) {
      return enqueue(song);
    }
    // Insert immediately after the current-first track (index 0 → insert at 1).
    _queueRefs = List.unmodifiable(insertNext(_queueRefs, song));
    await _syncQueueMetadata();
    _broadcastQueueChange();
    _schedulePersist(immediate: true);
  }

  @override
  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _queueRefs.length) {
      return;
    }
    final removedCurrent = index == 0;
    _queueRefs = List.unmodifiable([
      for (var i = 0; i < _queueRefs.length; i++)
        if (i != index) _queueRefs[i],
    ]);
    _queueRevision++;
    _schedulePersist(immediate: true);
    if (removedCurrent) {
      // The next item becomes current. If the queue emptied, stop.
      if (_queueRefs.isEmpty) {
        _wantPlayback = false;
        _queueTransition = true;
        try {
          await _clearEngine();
        } finally {
          _queueTransition = false;
          _emit();
        }
      } else {
        _queueTransition = true;
        try {
          await _loadCurrent();
          if (_wantPlayback) {
            unawaited(_player.play());
          }
        } finally {
          _queueTransition = false;
          _emit();
        }
      }
    }
    await _syncQueueMetadata();
    _broadcastQueueChange();
  }

  @override
  Future<void> move(int fromIndex, int toIndex) async {
    final length = _queueRefs.length;
    if (fromIndex < 0 ||
        toIndex < 0 ||
        fromIndex >= length ||
        toIndex >= length) {
      return;
    }
    if (fromIndex == toIndex) {
      return;
    }
    final currentKey = _queueRefs.first.identityKey;
    final updated = moveCurrentFirst(_queueRefs, fromIndex, toIndex);
    if (updated == null) {
      return;
    }
    _queueRefs = List.unmodifiable(updated);
    _queueRevision++;
    _schedulePersist(immediate: true);
    _broadcastQueueChange();

    // If a different song became current, load and play it.
    final newCurrent = _queueRefs.first.identityKey;
    if (newCurrent != currentKey) {
      _wantPlayback = true;
      _queueTransition = true;
      try {
        await _loadCurrent();
        unawaited(_player.play());
      } finally {
        _queueTransition = false;
        _emit();
        _maybeRecordStat(_currentRef());
      }
    }
  }

  @override
  Future<void> moveQueueItem(int fromIndex, int toIndex) async {
    await move(fromIndex, toIndex);
  }

  @override
  Future<void> clearQueue() async {
    if (_queueRefs.isEmpty) {
      return;
    }
    // Keep only the current-first song.
    _queueRefs = List.unmodifiable([_queueRefs.first]);
    _queueRevision++;
    await _syncQueueMetadata();
    _broadcastQueueChange();
    _schedulePersist(immediate: true);
  }

  @override
  List<SongRef> get currentQueue => List<SongRef>.of(_queueRefs);

  @override
  Future<void> stop() async {
    // System-initiated teardown (app removed from recents, notification
    // removed): stop the audio engine but DO NOT clear the session. The queue
    // and its persisted snapshot stay intact so reopening the app resumes
    // where the user left off. Only an explicit user action via
    // [clearSession] ends the listening session.
    if (_queueRefs.isEmpty) {
      _wantPlayback = false;
      await _clearEngine();
      _wantPlayback = false;
      await _clearEngine();
      await _teardownSystemState();
      _emit();
      return;
    }
    // Persist the real snapshot so the latest position survives the teardown
    // (recents removal / notification removal may race the process death with
    // onTaskRemoved; this keeps the source of truth current).
    _wantPlayback = false;
    await _persistNow();
    await _clearEngine();
    // Post-stop, report a genuinely idle, not-playing state so the native
    // audio_service layer removes the foreground media notification for good.
    // A preserved queue alone maps to `ready`, which (unlike `idle`) keeps the
    // ongoing media notification posted and makes it reappear after the user
    // swipes it away.
    await _teardownSystemState();
    _emit();
  }

  /// Drives the native side into a stopped, idle state so the foreground media
  /// notification is dismissed permanently, without disturbing the in-memory
  /// queue or its persisted snapshot. Reporting `idle` makes native
  /// audio_service tear the service down (stopForeground REMOVE), which is the
  /// only path that permanently clears the ongoing media notification.
  Future<void> _teardownSystemState() async {
    try {
      playbackState.add(
        playbackState.value.copyWith(
          playing: false,
          processingState: AudioProcessingState.idle,
        ),
      );
      await super.stop();
    } catch (_) {
      // Best-effort; the snapshot is authoritative.
    }
  }

  /// Explicitly ends the listening session (user dismissed the Mini Player):
  /// clears the queue and wipes the persisted snapshot so a restart does not
  /// resurrect a session the user cleared.
  @override
  Future<void> clearSession() async {
    _wantPlayback = false;
    _statLastKey = null;
    _queueRefs = const [];
    // Clear the UI state unconditionally, before touching the engine: the
    // sequence must never linger as an orphan AudioTrack playing with no UI.
    _queueRevision++;
    ++_playGeneration;
    // Explicit stop is a deliberate end of the session: wipe the persisted
    // snapshot so a restart doesn't resurrect a session the user cleared.
    _persistDebounce?.cancel();
    _persistDebounce = null;
    try {
      await _persistence.write(_kSnapshotKey, const QueueSnapshot.empty().toJson());
    } catch (e) {
      debugPrint('VoraTube snapshot clear failed: $e');
    }
    _emit();
    await _clearEngine();
  }

  @override
  Future<void> setShuffle(bool enabled) async {
    _shuffleEnabled = enabled;
    // Never engage just_audio's own shuffle: it would create a second, hidden
    // ordering. Shuffling happens solely on [_queueRefs]; the engine's
    // shuffle flag is left off.
    await _player.setShuffleModeEnabled(false);
    // Re-order the queue: current stays at #1, the rest shuffle. When toggling
    // off, restore a simple current-first order (drop the previous shuffle
    // permutation: current + the rest in their remaining order).
    if (_shuffleEnabled && _queueRefs.length > 1) {
      final first = _queueRefs.first;
      final rest = (_queueRefs.sublist(1).toList()..shuffle());
      _queueRefs = List.unmodifiable([first, ...rest]);
    }
    _queueRevision++;
    _broadcastQueueChange();
    _schedulePersist(immediate: true);
  }

  @override
  Future<void> setRepeat(RepeatMode mode) async {
    _repeatMode = mode;
    // Engine loop only matters for Repeat One (repeat the single loaded source
    // in place). Repeat All is implemented by rotating [_queueRefs] on finish,
    // so the engine is left off.
    await _player.setLoopMode(
      mode == RepeatMode.one ? LoopMode.one : LoopMode.off,
    );
    _schedulePersist(immediate: true);
    _emit();
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
    // Positive Preamp is real gain above the 0..1 volume clamp, so push it
    // through the same native loudness enhancer as the Volume Booster. This
    // makes Preamp changes take effect live mid-playback.
    unawaited(_applyBoostGain());
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

  /// Applies the current Volume Booster + Preamp as real gain on the native
  /// loudness enhancer attached to just_audio's Android audio session.
  ///
  /// This is the layer that actually raises playback above 100%: ExoPlayer
  /// clamps base volume to 0..1, so a positive Preamp (e.g. +6 dB) would
  /// otherwise be swallowed by the clamp and change nothing. Both gain sources
  /// add together in millibels on this one enhancer. It is best-effort and
  /// evergreen: it subscribes once to the audio-session stream so the enhancer
  /// is (re)attached whenever ExoPlayer assigns a session, and it always
  /// mirrors the latest Preamp/Booster — so session changes, track transitions,
  /// pause/resume and a live sweep all keep the gain correct. On non-Android
  /// hosts or when the platform channel is missing, it silently no-ops and
  /// playback continues at normal volume.
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
    final millibel = _enhancerMillibel();
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

  /// Combined real gain (millibels) for the native enhancer: the Volume
  /// Booster's mapping plus the positive Preamp's per-dB boost.
  int _enhancerMillibel() =>
      volumeBoostMillibel(_boostMultiplier) + preampBoostMillibel(_preampDb);

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
        // Re-apply whenever there is any real gain (Booster >100% or a
        // positive Preamp), so a Preamp-only change still gets attached to a
        // freshly assigned session.
        if (_enhancerMillibel() > 0) {
          unawaited(_applyBoostGain());
        }
      }),
    );
  }

  Future<void> _syncCurrentMediaItem() async {
    final ref = _currentRef();
    mediaItem.add(ref == null ? null : _mediaItemFor(ref));
  }

  SongRef? _currentRef() {
    if (_queueRefs.isEmpty) {
      return null;
    }
    return _queueRefs.first;
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
    // A known queue (even while the single source is being prepared) is never
    // reported as idle: only a genuinely empty queue is truly idle.
    final hasKnownQueue = _queueRefs.isNotEmpty;
    final status = switch (state) {
      ProcessingState.idle when hasKnownQueue => PlayerStatus.ready,
      ProcessingState.idle => PlayerStatus.idle,
      ProcessingState.loading => PlayerStatus.loading,
      ProcessingState.buffering => PlayerStatus.ready,
      ProcessingState.ready => PlayerStatus.ready,
      ProcessingState.completed => PlayerStatus.ready,
    };
    final next = PlayerSnapshot(
      status: status,
      isPlaying: _player.playing,
      repeatMode: _repeatMode,
      shuffleEnabled: _shuffleEnabled,
      // Current-first: the playing song is always at index 0.
      queueLength: _queueRefs.length,
      currentIndex: _queueRefs.isEmpty ? -1 : 0,
      // Fall back to the known track metadata while the engine hasn't decoded
      // its own duration yet (fresh load, or a restored idle session), so the
      // progress bar has a denominator before the first engine duration event.
      durationMs:
          _player.duration?.inMilliseconds ?? _currentRef()?.durationMs ?? 0,
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
    // Mirror _emit: a known queue (even while the single source is being
    // prepared) is never reported idle.
    final hasKnownQueue = _queueRefs.isNotEmpty;
    final processing = switch (state) {
      ProcessingState.idle when hasKnownQueue => AudioProcessingState.ready,
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
    // Prev/next on the system transport reflect the current-first queue: a skip
    // is possible whenever there is more than one song (or Repeat All loops).
    final canStep = _queueRefs.length > 1 || _repeatMode == RepeatMode.all;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          if (canStep) MediaControl.skipToPrevious,
          if (_player.playing) MediaControl.pause else MediaControl.play,
          if (canStep) MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        processingState: processing,
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _queueRefs.isEmpty ? -1 : 0,
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
      // Never persist mid-transition: the engine position belongs to whichever
      // source is being swapped, so writing now could clobber a good saved
      // position with a transient 0 (a classic "progress lost on restart"
      // race). The snapshot emitted at the end of the transition re-arms the
      // persist with the coherent state.
      if (_queueTransition) {
        return;
      }
      final snapshot = QueueSnapshot(
        identityKeys: [
          for (final r in _queueRefs)
            if (r.identityKey.isNotEmpty) r.identityKey,
        ],
        index: 0,
        positionMs: _player.position.inMilliseconds,
        shuffleEnabled: _shuffleEnabled,
        repeatMode: _repeatMode,
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
      // Preserve saved ordering where possible, rotating so the saved current
      // index lands at the front (current-first invariant). Newer snapshots
      // persist index 0 already; older ones may point elsewhere.
      final byKey = {for (final s in songs) s.identityKey: s};
      final ordered = [
        for (final k in saved.identityKeys)
          if (byKey[k] != null) byKey[k]!,
      ];
      if (ordered.isEmpty) {
        return;
      }
      final index = saved.index.clamp(0, ordered.length - 1);
      final rotated = [
        for (var i = 0; i < ordered.length; i++)
          ordered[(index + i) % ordered.length],
      ];
      // Clamp an impossible saved position before touching the engine: a
      // position at/after the track's known duration (e.g. the persist raced a
      // natural completion) would make the restored source complete instantly
      // and silently advance to the next track. Restart such a track from 0.
      final resumeMs = clampResumeMs(
        saved.positionMs,
        rotated.first.durationMs,
      );
      // Load the restored track headfully so the engine is genuinely READY at
      // the saved position. The previous `preload: false` + seek approach left
      // the engine idle with the position deferred to a future play(), so the
      // restored progress was never actually applied (and the position stream
      // never reported it) — progress appeared to reset to 0 on every restart.
      _queueRefs = List.unmodifiable(rotated);
      // Protect the restored session from transient cold-start idle failures
      // clearing it. Cleared on the next explicit [playQueue].
      _protectingRestoredSession = true;
      _shuffleEnabled = saved.shuffleEnabled;
      _repeatMode = saved.repeatMode;
      await _player.setAudioSource(
        _sourceFor(_queueRefs.first),
        preload: true,
        initialPosition: Duration(milliseconds: resumeMs),
      );
      // Defensive: make sure the engine agrees with the saved position even if
      // the platform ignored initialPosition.
      if ((_player.position.inMilliseconds - resumeMs).abs() > 1500) {
        await _player.seek(Duration(milliseconds: resumeMs));
      }
      // Engine never uses native shuffle; reflect the restored state only.
      await _player.setShuffleModeEnabled(false);
      await _player.setLoopMode(
        _repeatMode == RepeatMode.one ? LoopMode.one : LoopMode.off,
      );
      await _syncQueueMetadata();
      final restoredRef = _queueRefs.isEmpty ? null : _queueRefs.first;
      if (restoredRef != null) {
        _statLastKey = restoredRef.identityKey;
      }
      _queueRevision++;
      // Seed the position stream with the restored position so progress-
      // rendering widgets (MiniPlayer, full player) show the saved location
      // immediately, without waiting for playback to start: a paused/idle
      // engine does not tick the position stream on its own.
      if (!_positionController.isClosed) {
        _positionController.add(Duration(milliseconds: resumeMs));
      }
      _schedulePersist(immediate: true);
      _emit();
      debugPrint(
        'VoraTube restored queue (${_queueRefs.length} tracks @ '
        '$resumeMs ms)',
      );
    } catch (e) {
      debugPrint('VoraTube restore failed: $e');
    }
  }
}

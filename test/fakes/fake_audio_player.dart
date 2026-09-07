import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// A deterministic [AudioPlayer] double for unit-testing
/// `JustAudioController` on the Dart VM.
///
/// It models a minimalist just_audio engine: state is exposed through plain
/// getters and only changes when the test drives it (or when the controller
/// calls an engine method). Crucially, stream broadcasts are suppressed by
/// default (`emitEvents: false`) so the engine behaves like an Android device
/// whose platform side never re-emits state — which is exactly the scenario
/// that exposed the stale-notification bug. With events suppressed, the ONLY
/// way a state change can reach audio_service is via the controller's explicit
/// emissions, so the tests assert the controller behaves deterministically
/// rather than depending on incidental engine events.
class FakeAudioPlayer extends AudioPlayer {
  FakeAudioPlayer({
    ProcessingState processing = ProcessingState.idle,
    bool playing = false,
    bool emitEvents = false,
  }) : _processing = processing,
       _playing = playing,
       _emitEvents = emitEvents;

  ProcessingState _processing;
  bool _playing;
  final bool _emitEvents;

  final StreamController<ProcessingState> _processingCtrl =
      StreamController<ProcessingState>.broadcast();
  final StreamController<bool> _playingCtrl =
      StreamController<bool>.broadcast();
  final StreamController<LoopMode> _loopCtrl =
      StreamController<LoopMode>.broadcast();
  final StreamController<bool> _shuffleCtrl =
      StreamController<bool>.broadcast();
  final StreamController<Duration?> _durationCtrl =
      StreamController<Duration?>.broadcast();
  final StreamController<int?> _indexCtrl = StreamController<int?>.broadcast();
  final StreamController<Duration> _positionCtrl =
      StreamController<Duration>.broadcast(sync: true);

  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int setAudioSourceCalls = 0;
  int setAudioSourcesCalls = 0;
  List<AudioSource>? lastAudioSources;
  Duration? lastInitialPosition;

  void _emitIfEnabled() {
    if (_emitEvents) {
      _processingCtrl.add(_processing);
      _playingCtrl.add(_playing);
    }
  }

  /// Drives the fake like a real engine loading and starting a source.
  void simulateLoad(ProcessingState next, bool isPlaying) {
    _processing = next;
    _playing = isPlaying;
    _emitIfEnabled();
  }

  @override
  ProcessingState get processingState => _processing;

  @override
  bool get playing => _playing;

  @override
  Duration? get duration => null;

  @override
  Duration get position => Duration.zero;

  @override
  Duration get bufferedPosition => Duration.zero;

  @override
  double get speed => 1.0;

  @override
  int? get androidAudioSessionId => null;

  @override
  Stream<ProcessingState> get processingStateStream => _processingCtrl.stream;

  @override
  Stream<bool> get playingStream => _playingCtrl.stream;

  @override
  Stream<LoopMode> get loopModeStream => _loopCtrl.stream;

  @override
  Stream<bool> get shuffleModeEnabledStream => _shuffleCtrl.stream;

  @override
  Stream<Duration?> get durationStream => _durationCtrl.stream;

  @override
  Stream<int?> get currentIndexStream => _indexCtrl.stream;

  @override
  Stream<Duration> createPositionStream({
    int steps = 800,
    Duration minPeriod = const Duration(milliseconds: 200),
    Duration maxPeriod = const Duration(milliseconds: 200),
  }) => _positionCtrl.stream;

  @override
  Future<Duration?> setAudioSource(
    AudioSource audioSource, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) {
    setAudioSourceCalls++;
    lastAudioSources = [audioSource];
    lastInitialPosition = initialPosition;
    if (_emitEvents) {
      // Instant load: a well-behaved engine lands on `ready` right after the
      // source is set (never lingers in `loading`).
      _processing = ProcessingState.ready;
      _processingCtrl.add(_processing);
    }
    return Future<Duration?>.value(null);
  }

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) {
    setAudioSourcesCalls++;
    lastAudioSources = audioSources;
    lastInitialPosition = initialPosition;
    if (_emitEvents) {
      // Like just_audio: an empty sequence never becomes `ready` — the engine
      // stays in whatever state stop() left it (idle). Only a non-empty set
      // loads into `ready`.
      if (audioSources.isNotEmpty) {
        _processing = ProcessingState.ready;
      }
      _processingCtrl.add(_processing);
    }
    return Future<Duration?>.value(null);
  }

  @override
  Future<void> play() async {
    playCalls++;
    _playing = true;
    if (_emitEvents) {
      _playingCtrl.add(true);
    }
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _playing = false;
    if (_emitEvents) {
      _playingCtrl.add(false);
    }
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _processing = ProcessingState.idle;
    _playing = false;
    _emitIfEnabled();
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (_emitEvents) {
      _positionCtrl.add(position ?? Duration.zero);
    }
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setLoopMode(LoopMode mode) async {}

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {}

  @override
  Future<void> dispose() async {
    await _processingCtrl.close();
    await _playingCtrl.close();
    await _loopCtrl.close();
    await _shuffleCtrl.close();
    await _durationCtrl.close();
    await _indexCtrl.close();
    await _positionCtrl.close();
  }
}

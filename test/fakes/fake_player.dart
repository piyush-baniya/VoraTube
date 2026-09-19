import 'dart:async';

import 'package:vora_tube/core/audio/audio_effects.dart';
import 'package:vora_tube/core/audio/parametric_eq.dart';
import 'package:vora_tube/core/player/player_controller.dart';

/// Deterministic no-op player for widget tests. Never touches platform
/// channels.
class FakePlayerController implements PlayerController {
  FakePlayerController({PlayerSnapshot? initial, List<SongRef>? queue})
    : current = initial ?? PlayerSnapshot.initial,
      _queue = queue ?? const [],
      _snapshotController = StreamController<PlayerSnapshot>.broadcast();

  @override
  PlayerSnapshot current;

  final List<SongRef> _queue;
  final StreamController<PlayerSnapshot> _snapshotController;

  /// Pushes a new snapshot to listeners and updates [current].
  void pushSnapshot(PlayerSnapshot snapshot) {
    current = snapshot;
    _snapshotController.add(snapshot);
  }

  @override
  List<SongRef> get currentQueue => List<SongRef>.of(_queue);

  @override
  Stream<PlayerSnapshot> get snapshot => _snapshotController.stream;

  @override
  Stream<Duration> get positions => Stream.value(Duration.zero);

  @override
  Future<void> playQueue(List<SongRef> songs, {int startIndex = 0}) async {}

  @override
  Future<void> togglePlay() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> clearSession() async {
    current = PlayerSnapshot.initial;
    if (!_snapshotController.isClosed) {
      _snapshotController.add(current);
    }
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> seekBy(Duration offset) async {}

  @override
  Future<void> next() async {}

  @override
  Future<void> previous() async {}

  @override
  Future<void> jumpTo(int index) async {}

  @override
  Future<void> enqueue(SongRef song) async {}

  @override
  Future<void> playNext(SongRef song) async {}

  @override
  Future<void> removeAt(int index) async {}

  /// Records what the delete flow asked to prune, and drops matching entries
  /// from the fake queue so tests can assert the queue was actually cleaned.
  final Set<String> removedIdentityKeys = <String>{};

  @override
  Future<void> removeByIdentityKeys(Set<String> identityKeys) async {
    removedIdentityKeys.addAll(identityKeys);
    _queue.removeWhere((r) => identityKeys.contains(r.identityKey));
  }

  @override
  Future<void> move(int fromIndex, int toIndex) async {}

  @override
  Future<void> moveQueueItem(int fromIndex, int toIndex) async {}

  @override
  Future<void> clearQueue() async {}

  @override
  Future<void> setShuffle(bool enabled) async {}

  @override
  Future<void> setRepeat(RepeatMode mode) async {}

  @override
  ReplayGainMode get replayGainMode => ReplayGainMode.off;

  @override
  Future<void> setReplayGainMode(
    ReplayGainMode mode, {
    double preampDb = 0,
  }) async {}

  @override
  Future<void> setVolume(double volume) async {}

  // --- Advanced audio settings (recorded for assertion, never touch the UI) ---

  double? lastPlaybackSpeed;
  bool? eqEnabled;
  EqPreset? eqPreset;
  List<double>? eqCustomLevels;
  bool? parametricEqEnabled;
  List<ParametricEqBand>? parametricEqBands;
  PlaybackTransitionMode? transitionMode;
  int? crossfadeSeconds;
  double? audioBalance;

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    lastPlaybackSpeed = speed;
  }

  @override
  Future<void> setEqualizer({
    required bool enabled,
    required EqPreset preset,
    required List<double> customLevels,
  }) async {
    eqEnabled = enabled;
    eqPreset = preset;
    eqCustomLevels = List<double>.of(customLevels);
  }

  @override
  Future<void> setParametricEq({
    required bool enabled,
    required List<ParametricEqBand> bands,
  }) async {
    parametricEqEnabled = enabled;
    parametricEqBands = List<ParametricEqBand>.of(bands);
  }

  @override
  Future<void> setTransitionMode(
    PlaybackTransitionMode mode, {
    int crossfadeSeconds = kDefaultCrossfadeSeconds,
  }) async {
    transitionMode = mode;
    this.crossfadeSeconds = crossfadeSeconds;
  }

  @override
  Future<void> setAudioBalance(double balance) async {
    audioBalance = balance;
  }

  @override
  Future<void> dispose() async {
    await _snapshotController.close();
  }
}

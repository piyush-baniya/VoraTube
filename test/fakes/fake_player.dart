import 'dart:async';

import 'package:vora_tube/core/player/player_controller.dart';

/// Deterministic no-op player for widget tests. Never touches platform
/// channels.
class FakePlayerController implements PlayerController {
  FakePlayerController({PlayerSnapshot? initial, List<SongRef>? queue})
    : current = initial ?? PlayerSnapshot.initial,
      _queue = queue ?? const [];

  @override
  PlayerSnapshot current;

  final List<SongRef> _queue;

  @override
  List<SongRef> get currentQueue => List<SongRef>.of(_queue);

  @override
  Stream<PlayerSnapshot> get snapshot => Stream.value(current);

  @override
  Stream<Duration> get positions => Stream.value(Duration.zero);

  @override
  Future<void> playQueue(List<SongRef> songs, {int startIndex = 0}) async {}

  @override
  Future<void> togglePlay() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {
    current = PlayerSnapshot.initial;
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
  @override
  Future<void> setReplayGainMode(
    ReplayGainMode mode, {
    double preampDb = 0,
  }) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setVolumeBoost(double multiplier) async {}

  @override
  Future<void> dispose() async {}
}

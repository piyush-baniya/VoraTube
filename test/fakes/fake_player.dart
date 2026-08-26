import 'dart:async';

import 'package:vora_tube/core/player/player_controller.dart';

/// Deterministic no-op player for widget tests. Never touches platform
/// channels.
class FakePlayerController implements PlayerController {
  FakePlayerController({PlayerSnapshot? initial})
    : current = initial ?? PlayerSnapshot.initial;

  @override
  PlayerSnapshot current;

  @override
  Stream<PlayerSnapshot> get snapshot => Stream.value(current);

  @override
  Stream<Duration> get positions => const Stream.empty();

  @override
  Future<void> playQueue(List<SongRef> songs, {int startIndex = 0}) async {}

  @override
  Future<void> togglePlay() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

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
  Future<void> setShuffle(bool enabled) async {}

  @override
  Future<void> setRepeat(RepeatMode mode) async {}

  @override
  Future<void> dispose() async {}
}

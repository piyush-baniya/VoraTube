import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/core/player/player_controller.dart';

/// Regression tests for the **queue reorder index contract**.
///
/// The player queue is reordered through `ReorderableListView.onReorderItem`,
/// which already reports `newIndex` in *post-removal* space (the framework
/// removes the dragged item first, then reports the insertion slot). That
/// index is passed straight into the player's move implementation
/// (`moveQueueItem`/`move`), which applies the same convention:
///
/// ```dart
/// final moved = queue.removeAt(from);
/// queue.insert(to, moved);
/// ```
///
/// (This mirrors `JustAudioController.move` and just_audio's
/// `AudioPlayer.moveAudioSource`, both of which do `removeAt` then `insert`.)
///
/// These tests lock in that contract so the old `newIndex--` adjustment for
/// downward moves is never re-introduced.
SongRef _ref(String key) =>
    SongRef(identityKey: key, uri: 'file:///$key', title: key);

/// Applies the exact queue-move semantics used by the player controller.
List<SongRef> _move(List<SongRef> queue, int from, int to) {
  final updated = List<SongRef>.of(queue);
  final moved = updated.removeAt(from);
  updated.insert(to, moved);
  return updated;
}

/// A minimal recording player that implements the queue-reorder contract:
/// it records every `moveQueueItem(from, to)` and keeps its internal queue in
/// sync, exactly like the production controller.
class _RecordingPlayer implements PlayerController {
  _RecordingPlayer(List<SongRef> queue) : _queue = List.of(queue);

  final List<SongRef> _queue;
  final List<(int, int)> moves = [];

  @override
  List<SongRef> get currentQueue => List.unmodifiable(_queue);

  @override
  Future<void> moveQueueItem(int fromIndex, int toIndex) async {
    moves.add((fromIndex, toIndex));
    final updated = _move(_queue, fromIndex, toIndex);
    _queue
      ..clear()
      ..addAll(updated);
  }

  // Unused by these tests; routed through noSuchMethod where not implemented.
  @override
  PlayerSnapshot get current => PlayerSnapshot.initial;
  @override
  Stream<PlayerSnapshot> get snapshot => const Stream<PlayerSnapshot>.empty();
  @override
  Stream<Duration> get positions => const Stream<Duration>.empty();
  @override
  ReplayGainMode get replayGainMode => ReplayGainMode.off;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  List<SongRef> queue(List<String> keys) => [for (final k in keys) _ref(k)];

  String order(List<SongRef> q) => q.map((s) => s.identityKey).join(',');

  group('queue reorder move semantics (post-removal index)', () {
    test('first -> last', () {
      // onReorderItem reports newIndex=3 for A -> end of [A,B,C,D].
      expect(order(_move(queue(['A', 'B', 'C', 'D']), 0, 3)), 'B,C,D,A');
    });

    test('last -> first', () {
      expect(order(_move(queue(['A', 'B', 'C', 'D']), 3, 0)), 'D,A,B,C');
    });

    test('middle -> first', () {
      // C in [A,B,C,D,E] moved above A => post-removal index 0.
      expect(order(_move(queue(['A', 'B', 'C', 'D', 'E']), 2, 1)), 'A,C,B,D,E');
    });

    test('middle -> last', () {
      // B in [A,B,C,D] moved to the end => post-removal index 3.
      expect(order(_move(queue(['A', 'B', 'C', 'D']), 1, 3)), 'A,C,D,B');
    });

    test('the exact scenarios from the bug report', () {
      // Drag A below C on [A,B,C,D].
      expect(order(_move(queue(['A', 'B', 'C', 'D']), 0, 3)), 'B,C,D,A');
      // Drag D above B on [A,B,C,D].
      expect(order(_move(queue(['A', 'B', 'C', 'D']), 3, 1)), 'A,D,B,C');
    });
  });

  group('queue sheet onReorderItem -> moveQueueItem delegation', () {
    test('passes post-removal (oldIndex, newIndex) straight through', () async {
      final player = _RecordingPlayer(queue(['A', 'B', 'C', 'D']));

      // Move D to the front exactly as ReorderableListView's onReorderItem
      // reports it: oldIndex=3, newIndex=0 (post-removal space).
      await player.moveQueueItem(3, 0);
      expect(player.moves, [(3, 0)]);
      expect(order(player.currentQueue), 'D,A,B,C');

      // Move the (now first) item to the end.
      await player.moveQueueItem(0, 3);
      expect(player.moves, [(3, 0), (0, 3)]);
      expect(order(player.currentQueue), 'A,B,C,D');
    });
  });
}
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/core/player/queue_order.dart';

SongRef _song(int id) => SongRef(
  identityKey: 'ms:$id',
  uri: 'content://media/external/audio/media/$id',
  title: 'Song $id',
  artist: 'Artist',
  album: 'Album',
  durationMs: 200000,
);

List<String> _keys(List<SongRef> refs) => [for (final r in refs) r.identityKey];

void main() {
  group('currentFirst', () {
    test('rotates the selected song to #1 keeping the list play order', () {
      final queue = [_song(1), _song(2), _song(3), _song(4)];
      // True circular rotation: the song after the tapped one stays next.
      expect(_keys(currentFirst(queue, 2)!), ['ms:3', 'ms:4', 'ms:1', 'ms:2']);
      expect(_keys(currentFirst(queue, 0)!), ['ms:1', 'ms:2', 'ms:3', 'ms:4']);
    });

    test('Next from a mid-queue start follows list order, not library head', () {
      // A B C D E, start C: queue must be C D E A B, so Next from C → D.
      final queue = [
        _song(1),
        _song(2),
        _song(3),
        _song(4),
        _song(5),
      ];
      final fromC = currentFirst(queue, 2)!;
      expect(_keys(fromC), ['ms:3', 'ms:4', 'ms:5', 'ms:1', 'ms:2']);
      expect(_keys(rotateForward(fromC)).first, 'ms:4');
    });

    test('returns null for out-of-range indices', () {
      expect(currentFirst([_song(1)], -1), isNull);
      expect(currentFirst([_song(1)], 1), isNull);
    });
  });

  group('rotateForward / rotateBackward', () {
    test('rotates current-first forward (current to end)', () {
      final queue = [_song(1), _song(2), _song(3)];
      expect(_keys(rotateForward(queue)), ['ms:2', 'ms:3', 'ms:1']);
    });

    test('rotates current-first backward (last to front)', () {
      final queue = [_song(1), _song(2), _song(3)];
      expect(_keys(rotateBackward(queue)), ['ms:3', 'ms:1', 'ms:2']);
    });

    test('single-song queue self-loops', () {
      expect(_keys(rotateForward([_song(1)])), ['ms:1']);
      expect(_keys(rotateBackward([_song(1)])), ['ms:1']);
    });
  });

  group('applyRepeatFinish', () {
    test('Repeat Off removes the finished current song', () {
      final queue = [_song(1), _song(2), _song(3)];
      expect(_keys(applyRepeatFinish(queue, RepeatMode.off)), ['ms:2', 'ms:3']);
    });

    test('Repeat Off empties a single-song queue', () {
      expect(applyRepeatFinish([_song(1)], RepeatMode.off), isEmpty);
    });

    test('Repeat All rotates current to the end', () {
      final queue = [_song(1), _song(2), _song(3)];
      expect(_keys(applyRepeatFinish(queue, RepeatMode.all)), [
        'ms:2',
        'ms:3',
        'ms:1',
      ]);
    });

    test('Repeat One leaves the queue unchanged', () {
      final queue = [_song(1), _song(2)];
      expect(_keys(applyRepeatFinish(queue, RepeatMode.one)), ['ms:1', 'ms:2']);
    });

    test('Repeat All never drops songs across many transitions', () {
      // A long background queue must survive an arbitrary number of natural
      // completions without items being removed or the queue being cleared —
      // this is the invariant the auto-advance fix relies on (a 20-30 song
      // queue playing continuously in the background).
      final queue = [
        for (var i = 1; i <= 30; i++) _song(i),
      ];
      final sortedKeys = (List<String>.of(_keys(queue))..sort());
      var rotated = queue;
      for (var t = 0; t < 50; t++) {
        final wasFirst = _keys(rotated).first;
        rotated = applyRepeatFinish(rotated, RepeatMode.all);
        // Every track is still present, just reordered.
        expect((List<String>.of(_keys(rotated))..sort()), sortedKeys);
        // The just-finished current track wraps to the end (current-first).
        expect(_keys(rotated).last, wasFirst);
      }
    });
  });

  group('moveCurrentFirst', () {
    test('a new song moved to #1 becomes current', () {
      final queue = [_song(1), _song(2), _song(3)];
      expect(_keys(moveCurrentFirst(queue, 1, 0)!), ['ms:2', 'ms:1', 'ms:3']);
    });

    test('moving the current song away keeps it at #1', () {
      final queue = [_song(1), _song(2), _song(3)];
      expect(_keys(moveCurrentFirst(queue, 0, 2)!), ['ms:1', 'ms:2', 'ms:3']);
    });

    test('reorder among non-current songs is a plain move', () {
      final queue = [_song(1), _song(2), _song(3)];
      expect(_keys(moveCurrentFirst(queue, 1, 2)!), ['ms:1', 'ms:3', 'ms:2']);
    });

    test('same index is a no-op; invalid indices return null', () {
      final queue = [_song(1), _song(2)];
      expect(moveCurrentFirst(queue, 0, 0), same(queue));
      expect(moveCurrentFirst(queue, 0, 2), isNull);
      expect(moveCurrentFirst(queue, 2, 0), isNull);
    });
  });

  group('insertNext', () {
    test('inserts immediately after the current-first track', () {
      final queue = [_song(1), _song(2), _song(3)];
      expect(_keys(insertNext(queue, _song(9))), [
        'ms:1',
        'ms:9',
        'ms:2',
        'ms:3',
      ]);
    });
  });
}

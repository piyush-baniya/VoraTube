import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/core/player/queue_order.dart';

/// Regression tests for the shuffle-off behaviour.
///
/// BUG: turning shuffle OFF only flipped a boolean and left the internally
/// shuffled queue active, so Next/Previous kept following the shuffled
/// permutation instead of the deterministic ORIGINAL queue order.
///
/// FIX: the controller keeps a canonical unshuffled order ([[_baseQueue]] in
/// `just_audio_controller.dart`) that shuffle-off restores around the current
/// song, located by identity key. The ordering machinery lives as pure
/// functions in `queue_order.dart`; the tests below exercise those production
/// functions directly plus a thin mirror of the controller's glue so the full
/// user scenario (play C → shuffle ON → advance → shuffle OFF → Next= D,
/// Previous= B) is covered without an audio platform.

SongRef _song(String key, {String? title}) => SongRef(
  identityKey: key,
  uri: 'file:///$key',
  title: title ?? key,
);

List<String> _keys(List<SongRef> refs) => [for (final r in refs) r.identityKey];

/// Mirrors `JustAudioController`'s shuffle bookkeeping so the end-to-end flow
/// can be regression-tested against the same production helpers the controller
/// calls ([shuffledTail], [restoreOriginalOrder], [reconcileBaseOrder],
/// [rotateForward]/[rotateBackward], [applyRepeatFinish]). Keep in step when
/// the controller changes.
class _ShuffleSession {
  _ShuffleSession._(this.base, this.live);

  /// Mirrors `JustAudioController.playQueue`: the selected song rotates to #1
  /// and becomes the canonical base; when shuffle is already on the tail is
  /// shuffled on top of it.
  factory _ShuffleSession.playQueue(
    List<String> keys, {
    int startIndex = 0,
    bool shuffleEnabled = false,
  }) {
    final songs = [for (final k in keys) _song(k)];
    final ordered = currentFirst(songs, startIndex) ?? List.of(songs);
    final base = List.of(ordered);
    final live = shuffleEnabled
        ? List.of(shuffledTail(ordered))
        : List.of(ordered);
    return _ShuffleSession._(base, live)..shuffleEnabled = shuffleEnabled;
  }

  List<SongRef> base;
  List<SongRef> live;
  bool shuffleEnabled = false;

  List<String> get liveKeys => _keys(live);

  List<String> get baseKeys => _keys(base);

  /// Mirrors `JustAudioController.setShuffle`.
  void setShuffle(bool enabled) {
    shuffleEnabled = enabled;
    if (enabled) {
      live = List.of(shuffledTail(live));
    } else {
      live = List.of(restoreOriginalOrder(base: base, live: live));
    }
  }

  /// Mirrors `JustAudioController.next` / `previous` (_advance).
  void next() {
    live = List.of(rotateForward(live));
    _reconcile();
  }

  void previous() {
    live = List.of(rotateBackward(live));
    _reconcile();
  }

  /// Mirrors `JustAudioController._onTrackFinished` with Repeat Off: the
  /// finished current song leaves the queue.
  void finishRepeatOff() {
    live = List.of(applyRepeatFinish(live, RepeatMode.off));
    _reconcile();
  }

  /// Mirrors `JustAudioController.removeAt` (+ `_reconcileBase`).
  void removeAt(int index) {
    live = List.of([...live]..removeAt(index));
    _reconcile();
  }

  /// Mirrors `JustAudioController._reconcileBase`.
  void _reconcile() {
    base = List.of(
      reconcileBaseOrder(
        base: base,
        live: live,
        shuffleEnabled: shuffleEnabled,
      ),
    );
  }
}

void main() {
  group('shuffledTail (shuffle ON edge cases)', () {
    test('keeps the current-first song at #1 and preserves membership', () {
      final refs = [
        _song('A'),
        _song('B'),
        _song('C'),
        _song('D'),
        _song('E'),
      ];
      final tail = shuffledTail(refs);
      expect(tail.length, 5);
      expect(tail.first.identityKey, 'A');
      expect(tail.map((r) => r.identityKey).toSet(),
          {'A', 'B', 'C', 'D', 'E'});
    });

    test('single-song and empty queues are returned unchanged', () {
      expect(_keys(shuffledTail([_song('A')])), ['A']);
      expect(shuffledTail(const []), isEmpty);
    });
  });

  group('rotateToCurrent', () {
    test('rotates the canonical order so the requested song becomes #1', () {
      final canonical = [
        _song('C'),
        _song('D'),
        _song('E'),
        _song('A'),
        _song('B'),
      ];
      expect(_keys(rotateToCurrent(canonical, 'A')!),
          ['A', 'B', 'C', 'D', 'E']);
    });

    test('returns null for an absent key', () {
      expect(rotateToCurrent([_song('A')], 'Z'), isNull);
    });
  });

  group('restoreOriginalOrder (shuffle OFF)', () {
    test('restores the original order around the current song, not the '
        'shuffled index', () {
      // Canonical natural order A B C D E with C current; shuffled live queue
      // C E A D B. Restoring must return C D E A B — never keep C E A D B.
      final base = [
        _song('C'),
        _song('D'),
        _song('E'),
        _song('A'),
        _song('B'),
      ];
      final live = [
        _song('C'),
        _song('E'),
        _song('A'),
        _song('D'),
        _song('B'),
      ];
      expect(_keys(restoreOriginalOrder(base: base, live: live)),
          ['C', 'D', 'E', 'A', 'B']);
    });

    test('leaves an empty live queue untouched', () {
      expect(
        restoreOriginalOrder(base: [_song('A')], live: const []),
        isEmpty,
      );
    });

    test('keeps the live queue when the current song is absent from the base '
        '(defensive)', () {
      final live = [_song('Z'), _song('A')];
      expect(
        _keys(restoreOriginalOrder(base: [_song('B')], live: live)),
        ['Z', 'A'],
      );
    });
  });

  group('reconcileBaseOrder (canonical base maintenance)', () {
    test('mirrors the live queue exactly when shuffle is off', () {
      final base = [_song('C'), _song('D'), _song('E'), _song('A')];
      final live = [_song('D'), _song('E'), _song('A'), _song('C')];
      expect(
        _keys(reconcileBaseOrder(
          base: base,
          live: live,
          shuffleEnabled: false,
        )),
        _keys(live),
      );
    });

    test('keeps the natural ordering while adopting removals when shuffle is on',
        () {
      final base = [
        _song('C'),
        _song('D'),
        _song('E'),
        _song('A'),
        _song('B'),
      ];
      // C finished (Repeat Off): it leaves the live queue.
      final live = [_song('E'), _song('A'), _song('D'), _song('B')];
      expect(
        _keys(reconcileBaseOrder(
          base: base,
          live: live,
          shuffleEnabled: true,
        )),
        ['D', 'E', 'A', 'B'],
      );
    });

    test('adopts newly added songs when shuffle is on', () {
      final base = [
        _song('C'),
        _song('D'),
        _song('E'),
        _song('A'),
        _song('B'),
      ];
      final live = [...base, _song('F')];
      expect(
        _keys(reconcileBaseOrder(
          base: base,
          live: live,
          shuffleEnabled: true,
        )),
        ['C', 'D', 'E', 'A', 'B', 'F'],
      );
    });
  });

  group('shuffle OFF restores the ORIGINAL queue order (regression)', () {
    test('play C from A..E → shuffle ON → OFF → current C, next D, prev B', () {
      final s = _ShuffleSession.playQueue(['A', 'B', 'C', 'D', 'E'], startIndex: 2);
      expect(s.liveKeys, ['C', 'D', 'E', 'A', 'B']);

      s.setShuffle(true);
      // Shuffle preserves the current song and every queue member.
      expect(s.live.first.identityKey, 'C');
      expect(
        s.liveKeys.toSet(),
        s.baseKeys.toSet(),
      );

      // THE FIX: toggling off must restore the deterministic original order.
      s.setShuffle(false);
      expect(s.liveKeys, ['C', 'D', 'E', 'A', 'B']);

      // Next follows ORIGINAL order: C → D (the bug left C → E).
      s.next();
      expect(s.live.first.identityKey, 'D');

      // Step back to C, then Previous follows ORIGINAL order: C → B.
      s.previous();
      s.previous();
      expect(s.live.first.identityKey, 'B');
    });

    test('shuffle ON → several Next → OFF → Next follows ORIGINAL order from '
        'the current song', () {
      const original = ['A', 'B', 'C', 'D', 'E'];
      final s = _ShuffleSession.playQueue(original, startIndex: 2);
      s.setShuffle(true);
      s.next();
      s.next();
      final currentKey = s.live.first.identityKey;

      s.setShuffle(false);
      // Current song is preserved by IDENTITY (never a raw index).
      expect(s.live.first.identityKey, currentKey);
      // The queue is the canonical cycle rotated around the current song, so
      // position 1 is the ORIGINAL next song — definitively not the shuffled
      // successor.
      final idx = original.indexOf(currentKey);
      expect(s.liveKeys, [
        currentKey,
        original[(idx + 1) % original.length],
        original[(idx + 2) % original.length],
        original[(idx + 3) % original.length],
        original[(idx + 4) % original.length],
      ]);

      s.next();
      expect(s.live.first.identityKey, original[(idx + 1) % original.length]);
    });

    test('shuffle OFF → ON → OFF stays deterministic', () {
      final s = _ShuffleSession.playQueue(['A', 'B', 'C', 'D', 'E'], startIndex: 2);
      s.setShuffle(true);
      s.setShuffle(false);
      expect(s.liveKeys, ['C', 'D', 'E', 'A', 'B']);

      s.setShuffle(true);
      s.setShuffle(false);
      expect(s.liveKeys, ['C', 'D', 'E', 'A', 'B']);

      // ON, advance once, OFF: restored order rotates around the new current.
      s.setShuffle(true);
      s.next();
      final currentKey = s.live.first.identityKey;
      s.setShuffle(false);
      expect(s.live.first.identityKey, currentKey);
      expect(s.live.length, 5);
      expect(s.baseKeys, contains(currentKey));
    });

    test('a song finished while shuffled never returns on shuffle OFF '
        '(Repeat Off)', () {
      final s = _ShuffleSession.playQueue(['A', 'B', 'C', 'D', 'E'], startIndex: 2);
      s.setShuffle(true);
      s.finishRepeatOff(); // C leaves the queue.
      expect(s.liveKeys, isNot(contains('C')));
      final currentKey = s.live.first.identityKey;

      s.setShuffle(false);
      expect(s.live.first.identityKey, currentKey);
      // Restored = original order minus the finished song, rotated around the
      // current song.
      expect(s.liveKeys.toSet(), {'A', 'B', 'D', 'E'});
      final remaining = ['D', 'E', 'A', 'B'];
      final idx = remaining.indexOf(currentKey);
      expect(s.liveKeys[1], remaining[(idx + 1) % remaining.length]);
    });

    test('shuffle enabled BEFORE playQueue restores the queue that was active '
        'at session start', () {
      final s = _ShuffleSession.playQueue(
        ['A', 'B', 'C', 'D', 'E'],
        startIndex: 2,
        shuffleEnabled: true,
      );
      expect(s.live.first.identityKey, 'C');
      s.setShuffle(false);
      expect(s.liveKeys, ['C', 'D', 'E', 'A', 'B']);
    });

    test('single-song queue survives shuffle on/off and next/previous', () {
      final s = _ShuffleSession.playQueue(['A']);
      s.setShuffle(true);
      s.setShuffle(false);
      expect(s.liveKeys, ['A']);
      s.next();
      s.previous();
      expect(s.liveKeys, ['A']);
    });

    test('two-song queue behaves deterministically', () {
      final s = _ShuffleSession.playQueue(['A', 'B']);
      s.setShuffle(true);
      s.setShuffle(false);
      expect(s.liveKeys, ['A', 'B']);
      s.setShuffle(true);
      s.next();
      expect(s.live.first.identityKey, 'B');
      s.setShuffle(false);
      expect(s.live.first.identityKey, 'B');
      expect(s.liveKeys, ['B', 'A']); // restored original order around B
      s.next();
      expect(s.live.first.identityKey, 'A');
    });

    test('current at FIRST position — previous keeps the existing '
        'beginning-of-queue (wrap) behaviour', () {
      final s = _ShuffleSession.playQueue(['A', 'B', 'C', 'D']);
      s.setShuffle(true);
      s.setShuffle(false);
      expect(s.liveKeys, ['A', 'B', 'C', 'D']);
      s.previous();
      expect(s.live.first.identityKey, 'D');
    });

    test('current at LAST position — next keeps the natural wrap', () {
      final s = _ShuffleSession.playQueue(['A', 'B', 'C', 'D'], startIndex: 3);
      expect(s.liveKeys, ['D', 'A', 'B', 'C']);
      s.setShuffle(true);
      s.setShuffle(false);
      expect(s.liveKeys, ['D', 'A', 'B', 'C']);
      s.next();
      expect(s.live.first.identityKey, 'A');
    });

    test('duplicate-looking metadata — restore locates the current song by '
        'identity key, not title', () {
      final songs = [
        _song('ms:1', title: 'Same Title'),
        _song('ms:2', title: 'Same Title'),
        _song('ms:3', title: 'Only One'),
      ];
      final ordered = currentFirst(songs, 1)!; // current = ms:2
      final base = List.of(ordered);
      final live = List.of(shuffledTail(ordered));
      final restored = restoreOriginalOrder(base: base, live: live);
      expect(restored.first.identityKey, 'ms:2');
      expect(_keys(restored), ['ms:2', 'ms:3', 'ms:1']);
    });

    test('manual removal while shuffle is off is respected by a later '
        'shuffle on/off', () {
      final s = _ShuffleSession.playQueue(['A', 'B', 'C', 'D', 'E'], startIndex: 2);
      s.removeAt(1); // removes D from current-first view
      expect(s.liveKeys, ['C', 'E', 'A', 'B']);
      expect(s.baseKeys, ['C', 'E', 'A', 'B']);
      s.setShuffle(true);
      s.setShuffle(false);
      expect(s.liveKeys, ['C', 'E', 'A', 'B']);
    });
  });
}
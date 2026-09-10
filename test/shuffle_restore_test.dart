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
/// Previous= C restarting C) is covered without an audio platform.
///
/// NOTE ON PREVIOUS: since the playback-history fix the controller's Previous
/// never wraps the queue rotation — it re-walks the songs actually Played this
/// session and, at the very start of that history, simply restarts the current
/// song from 0. The mirror below models that behaviour, so shuffle-order
/// expectations focus on Next and queue restoration (which Previous no longer
/// drives).

SongRef _song(String key, {String? title}) =>
    SongRef(identityKey: key, uri: 'file:///$key', title: title ?? key);

List<String> _keys(List<SongRef> refs) => [for (final r in refs) r.identityKey];

/// Mirrors `JustAudioController`'s shuffle + playback-history bookkeeping so
/// the end-to-end flow can be regression-tested against the same production
/// helpers the controller calls ([shuffledTail], [restoreOriginalOrder],
/// [reconcileBaseOrder], [rotateForward]/[rotateBackward],
/// [applyRepeatFinish], [rotateToCurrent]). Keep in step when the controller
/// changes.
class _ShuffleSession {
  _ShuffleSession._(this.base, this.live) {
    notePlayed(live.first.identityKey);
  }

  /// Mirrors `JustAudioController.playQueue`: the selected song rotates to #1
  /// and becomes the canonical base; when shuffle is already on the tail is
  /// shuffled on top of it. The first song starts a new listening session,
  /// so it also seeds the playback history.
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

  /// Mirrors `JustAudioController`'s live history of songs actually started.
  List<String> history = const [];
  int historyCursor = -1;
  String? lastPlayed;

  List<String> get liveKeys => _keys(live);

  List<String> get baseKeys => _keys(base);

  /// Mirrors `JustAudioController._noteNewTrackPlayed` + `_trackHistory`.
  void notePlayed(String key) {
    if (lastPlayed == key) return;
    lastPlayed = key;
    if (history.isEmpty) {
      history = [key];
      historyCursor = 0;
      return;
    }
    final currentIdx = history.indexOf(live.first.identityKey);
    if (currentIdx >= 0) historyCursor = currentIdx;
    var cursor = historyCursor;
    if (cursor < 0 || cursor >= history.length) {
      cursor = history.length - 1;
    }
    if (history[cursor] == key) return;
    if (cursor < history.length - 1) {
      history = history.sublist(0, cursor + 1);
    }
    history = [...history, key];
    historyCursor = history.length - 1;
  }

  String? historyBackKey() {
    if (history.isEmpty) return null;
    final idx = history.indexOf(live.first.identityKey);
    if (idx < 0) return null;
    for (var i = idx - 1; i >= 0; i--) {
      if (live.any((r) => r.identityKey == history[i])) {
        historyCursor = i;
        return history[i];
      }
    }
    return null;
  }

  String? historyForwardKey() {
    if (history.isEmpty) return null;
    final idx = history.indexOf(live.first.identityKey);
    if (idx < 0) return null;
    for (var i = idx + 1; i < history.length; i++) {
      if (live.any((r) => r.identityKey == history[i])) {
        historyCursor = i;
        return history[i];
      }
    }
    return null;
  }

  /// Mirrors `JustAudioController._playHistoryKey` (history walk target).
  void playFrom(String key) {
    live = List.of(rotateToCurrent(live, key)!);
    _reconcile();
    notePlayed(key);
  }

  /// Mirrors `JustAudioController.setShuffle`.
  void setShuffle(bool enabled) {
    shuffleEnabled = enabled;
    if (enabled) {
      live = List.of(shuffledTail(live));
    } else {
      live = List.of(restoreOriginalOrder(base: base, live: live));
    }
  }

  /// Mirrors `JustAudioController.next`: re-walks the recorded forward history
  /// first, then falls through to the queue rotation.
  void next() {
    final forwardKey = historyForwardKey();
    if (forwardKey != null) {
      playFrom(forwardKey);
      return;
    }
    if (live.length == 1) {
      return; // single song: restart in place (no rotation)
    }
    live = List.of(rotateForward(live));
    _reconcile();
    notePlayed(live.first.identityKey);
  }

  /// Mirrors `JustAudioController.previous`: walks the recorded back history
  /// first, otherwise RESTARTS the current song (never rotates the queue).
  void previous() {
    final backKey = historyBackKey();
    if (backKey != null) {
      playFrom(backKey);
      return;
    }
    // History start: restart the current song from 0 — the live queue keeps
    // its exact order and nothing else starts.
  }

  /// Mirrors `JustAudioController._onTrackFinished` with Repeat Off: the
  /// finished current song leaves the queue and the next song becomes current.
  void finishRepeatOff() {
    live = List.of(applyRepeatFinish(live, RepeatMode.off));
    _reconcile();
    if (live.isNotEmpty) {
      notePlayed(live.first.identityKey);
    }
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
      final refs = [_song('A'), _song('B'), _song('C'), _song('D'), _song('E')];
      final tail = shuffledTail(refs);
      expect(tail.length, 5);
      expect(tail.first.identityKey, 'A');
      expect(tail.map((r) => r.identityKey).toSet(), {'A', 'B', 'C', 'D', 'E'});
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
      expect(_keys(rotateToCurrent(canonical, 'A')!), [
        'A',
        'B',
        'C',
        'D',
        'E',
      ]);
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
      final base = [_song('C'), _song('D'), _song('E'), _song('A'), _song('B')];
      final live = [_song('C'), _song('E'), _song('A'), _song('D'), _song('B')];
      expect(_keys(restoreOriginalOrder(base: base, live: live)), [
        'C',
        'D',
        'E',
        'A',
        'B',
      ]);
    });

    test('leaves an empty live queue untouched', () {
      expect(restoreOriginalOrder(base: [_song('A')], live: const []), isEmpty);
    });

    test('keeps the live queue when the current song is absent from the base '
        '(defensive)', () {
      final live = [_song('Z'), _song('A')];
      expect(_keys(restoreOriginalOrder(base: [_song('B')], live: live)), [
        'Z',
        'A',
      ]);
    });
  });

  group('reconcileBaseOrder (canonical base maintenance)', () {
    test('mirrors the live queue exactly when shuffle is off', () {
      final base = [_song('C'), _song('D'), _song('E'), _song('A')];
      final live = [_song('D'), _song('E'), _song('A'), _song('C')];
      expect(
        _keys(
          reconcileBaseOrder(base: base, live: live, shuffleEnabled: false),
        ),
        _keys(live),
      );
    });

    test(
      'keeps the natural ordering while adopting removals when shuffle is on',
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
          _keys(
            reconcileBaseOrder(base: base, live: live, shuffleEnabled: true),
          ),
          ['D', 'E', 'A', 'B'],
        );
      },
    );

    test('adopts newly added songs when shuffle is on', () {
      final base = [_song('C'), _song('D'), _song('E'), _song('A'), _song('B')];
      final live = [...base, _song('F')];
      expect(
        _keys(reconcileBaseOrder(base: base, live: live, shuffleEnabled: true)),
        ['C', 'D', 'E', 'A', 'B', 'F'],
      );
    });
  });

  group('shuffle OFF restores the ORIGINAL queue order (regression)', () {
    test('play C from A..E → shuffle ON → OFF → current C, next D, prev B', () {
      final s = _ShuffleSession.playQueue([
        'A',
        'B',
        'C',
        'D',
        'E',
      ], startIndex: 2);
      expect(s.liveKeys, ['C', 'D', 'E', 'A', 'B']);

      s.setShuffle(true);
      // Shuffle preserves the current song and every queue member.
      expect(s.live.first.identityKey, 'C');
      expect(s.liveKeys.toSet(), s.baseKeys.toSet());

      // THE FIX: toggling off must restore the deterministic original order.
      s.setShuffle(false);
      expect(s.liveKeys, ['C', 'D', 'E', 'A', 'B']);

      // Next follows ORIGINAL order: C → D (the bug left C → E).
      s.next();
      expect(s.live.first.identityKey, 'D');

      // Previous now walks actual PLAYBACK history: D → C (re-starts C), then
      // C is at the start of the history so Previous restarts it in place.
      // It no longer wraps the queue rotation to B.
      s.previous();
      expect(s.live.first.identityKey, 'C');
      s.previous();
      expect(s.live.first.identityKey, 'C');
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
      final s = _ShuffleSession.playQueue([
        'A',
        'B',
        'C',
        'D',
        'E',
      ], startIndex: 2);
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
      final s = _ShuffleSession.playQueue([
        'A',
        'B',
        'C',
        'D',
        'E',
      ], startIndex: 2);
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

    test('current at FIRST position — previous restarts the first song in '
        'place (no history, no queue wrap)', () {
      final s = _ShuffleSession.playQueue(['A', 'B', 'C', 'D']);
      s.setShuffle(true);
      s.setShuffle(false);
      expect(s.liveKeys, ['A', 'B', 'C', 'D']);
      s.previous();
      // Not the old begin-of-queue wrap to D: with no playback history behind
      // A, Previous restarts A and the queue order is untouched.
      expect(s.liveKeys, ['A', 'B', 'C', 'D']);
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
      final s = _ShuffleSession.playQueue([
        'A',
        'B',
        'C',
        'D',
        'E',
      ], startIndex: 2);
      s.removeAt(1); // removes D from current-first view
      expect(s.liveKeys, ['C', 'E', 'A', 'B']);
      expect(s.baseKeys, ['C', 'E', 'A', 'B']);
      s.setShuffle(true);
      s.setShuffle(false);
      expect(s.liveKeys, ['C', 'E', 'A', 'B']);
    });
  });
}

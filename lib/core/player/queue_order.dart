import 'player_controller.dart';

/// Pure current-first queue ordering helpers.
///
/// VoraTube models its queue as *current-first*: index 0 is ALWAYS the current
/// song, and the engine plays a single track at a time straight from this list.
/// These pure functions encode the rotation/repeat rules so they can be unit
/// tested in isolation, independently of the just_audio engine.

/// Rotates [items] so the song at [index] becomes the CURRENT song, keeping
/// the queue's natural play order intact: the songs that follow [index] wrap
/// around to the front of the remainder.
///
/// For `A B C D E` with index 2 this yields `C D E A B` — the song after C
/// stays D, so Next from C plays D. (A naive "move C to front, keep the rest
/// in original order" would produce `C A B D E`, making Next from C jump to
/// A.) Returns null when [index] is out of range.
List<SongRef>? currentFirst(List<SongRef> items, int index) {
  if (index < 0 || index >= items.length) {
    return null;
  }
  final length = items.length;
  return [
    for (var i = 0; i < length; i++) items[(index + i) % length],
  ];
}

/// Steps the current-first queue one song FORWARD: the current song (index 0)
/// moves to the END and everything else shifts up, so the next song becomes the
/// new current. A single-song queue is returned unchanged (a self-loop).
List<SongRef> rotateForward(List<SongRef> refs) {
  if (refs.length <= 1) {
    return refs;
  }
  return [...refs.sublist(1), refs.first];
}

/// Steps the current-first queue one song BACKWARD: the LAST song moves to the
/// FRONT and becomes current. A single-song queue is returned unchanged.
List<SongRef> rotateBackward(List<SongRef> refs) {
  if (refs.length <= 1) {
    return refs;
  }
  return [refs.last, ...refs.sublist(0, refs.length - 1)];
}

/// Applies the repeat policy after the current song finishes naturally.
///
/// - [RepeatMode.off]: drop the finished current song (index 0).
/// - [RepeatMode.all]: move the finished song to the END (next becomes current).
/// - [RepeatMode.one]: unchanged (the engine loops the single source in place).
List<SongRef> applyRepeatFinish(List<SongRef> refs, RepeatMode mode) {
  return switch (mode) {
    RepeatMode.off => refs.length <= 1 ? const [] : refs.sublist(1),
    RepeatMode.all => rotateForward(refs),
    RepeatMode.one => refs,
  };
}

/// Moves the item at [from] to [to] while preserving the current-first
/// invariant (index 0 is always current). Returns null on invalid indices.
///
/// If a DIFFERENT song is moved to index 0 it becomes the new current; if the
/// current song is moved away from index 0 it is rotated back to the front.
List<SongRef>? moveCurrentFirst(List<SongRef> refs, int from, int to) {
  final length = refs.length;
  if (length == 0 || from < 0 || from >= length || to < 0 || to >= length) {
    return null;
  }
  if (from == to) {
    return refs;
  }
  final updated = [...refs];
  final moved = updated.removeAt(from);
  updated.insert(to, moved);

  final currentKey = refs.first.identityKey;
  if (moved.identityKey != currentKey && to == 0) {
    // A new song was brought to the front → it becomes current.
    return [
      moved,
      for (final s in updated)
        if (s.identityKey != moved.identityKey) s,
    ];
  }
  if (moved.identityKey == currentKey && to != 0) {
    // Current left #1 → rotate it back to the front.
    return [
      for (final s in updated)
        if (s.identityKey == currentKey) s,
      for (final s in updated)
        if (s.identityKey != currentKey) s,
    ];
  }
  return updated;
}

/// Inserts [song] immediately after the current-first track (index 0).
List<SongRef> insertNext(List<SongRef> refs, SongRef song) {
  return [refs.first, song, ...refs.sublist(1)];
}

/// Returns [refs] with the songs AFTER the current-first track (index 0)
/// randomly permuted. The current song stays #1, so enabling shuffle never
/// restarts or jumps away from what is playing. A single-song (or empty) queue
/// is returned unchanged.
List<SongRef> shuffledTail(List<SongRef> refs) {
  if (refs.length <= 1) {
    return refs;
  }
  final rest = refs.sublist(1).toList()..shuffle();
  return [refs.first, ...rest];
}

/// Rotates the canonical (unshuffled) current-first ordering [items] so the
/// song identified by [identityKey] becomes the CURRENT song (#1), preserving
/// the natural play order — the song that originally followed it stays next.
/// Returns null when the key is absent from [items].
List<SongRef>? rotateToCurrent(List<SongRef> items, String identityKey) {
  final index = items.indexWhere((s) => s.identityKey == identityKey);
  if (index < 0) {
    return null;
  }
  return currentFirst(items, index);
}

/// Restores the deterministic ORIGINAL ordering around the currently playing
/// song: the canonical unshuffled [base] is rotated so the song that is
/// current in [live] (located by identity key, never a raw index) becomes #1,
/// with the natural order afterwards. Returns [live] untouched when it is
/// empty or its current song is absent from [base].
List<SongRef> restoreOriginalOrder({
  required List<SongRef> base,
  required List<SongRef> live,
}) {
  if (live.isEmpty) {
    return live;
  }
  final restored = rotateToCurrent(base, live.first.identityKey);
  return restored ?? live;
}

/// Reconciles the canonical unshuffled [base] with the live queue [live] after
/// a queue mutation:
///
/// - Shuffle OFF: the base mirrors the live queue exactly (same membership AND
///   order).
/// - Shuffle ON: the base keeps its natural ordering but adopts membership
///   changes — songs removed from the live queue (natural finish, broken-skip,
///   user removal) leave the base, and songs added (enqueue, play-next) join
///   it — so turning shuffle off always restores the original order of exactly
///   the songs still queued, never a resurrected played song.
List<SongRef> reconcileBaseOrder({
  required List<SongRef> base,
  required List<SongRef> live,
  required bool shuffleEnabled,
}) {
  if (!shuffleEnabled) {
    return List.of(live);
  }
  if (live.isEmpty) {
    return const [];
  }
  final liveKeys = live.map((r) => r.identityKey).toSet();
  final pruned = [
    for (final r in base)
      if (liveKeys.contains(r.identityKey)) r,
  ];
  final baseKeys = pruned.map((r) => r.identityKey).toSet();
  return [
    for (final r in pruned) r,
    for (final r in live)
      if (!baseKeys.contains(r.identityKey)) r,
  ];
}

import 'player_controller.dart';

/// Pure current-first queue ordering helpers.
///
/// VoraTube models its queue as *current-first*: index 0 is ALWAYS the current
/// song, and the engine plays a single track at a time straight from this list.
/// These pure functions encode the rotation/repeat rules so they can be unit
/// tested in isolation, independently of the just_audio engine.

/// Rotates [items] so the song at [index] moves to the FRONT, preserving the
/// relative order of every other song. Returns null when [index] is out of
/// range.
List<SongRef>? currentFirst(List<SongRef> items, int index) {
  if (index < 0 || index >= items.length) {
    return null;
  }
  return [
    items[index],
    for (var i = 0; i < items.length; i++)
      if (i != index) items[i],
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

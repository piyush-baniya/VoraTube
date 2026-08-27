import 'dart:io';

import 'package:flutter/foundation.dart';

/// Memoized existence checks for artwork files on disk.
///
/// Artwork is stored as files written by the ingest pipeline, so the render path
/// has to know whether a path is backed by real bytes before handing it to
/// `Image.file` — otherwise every art-less row costs a failed decode and a
/// console exception.
///
/// The obvious way to answer that, `File(path).existsSync()` inside `build`, is
/// a synchronous `stat(2)` on the UI thread *per widget, per frame*. A list with
/// 15 visible tiles rebuilding at 60fps is ~900 syscalls a second, and the
/// player rebuilds its artwork on every position tick on top of that. This
/// cache reduces it to one `stat` per distinct path.
///
/// Staleness is handled in both directions, because both directions happen:
///
///  * **missing then present** — a scan resolved artwork while a screen was
///    already built. Handled by [invalidate], called whenever the pipeline may
///    have written new files.
///  * **present then missing** — the file was deleted, or the volume holding it
///    was unmounted. Handled by the widgets' `errorBuilder`, which calls
///    [forget] so the next lookup re-checks instead of trusting a stale hit.
abstract final class ArtworkFileCache {
  /// Cap on remembered paths.
  ///
  /// Each entry references a path string the database already holds, so the
  /// marginal cost is a map slot rather than a copy of the path. Overflow clears
  /// wholesale instead of evicting an LRU: the following frames then pay one
  /// `stat` per newly seen path, which is merely the cost of having no cache,
  /// and the policy stays simple enough to be obviously correct.
  static const int _maxEntries = 8192;

  /// Floor on decode width, so a tiny indicator still decodes something legible.
  static const int _minDecodeWidth = 32;

  /// Ceiling on decode width. Full-screen player artwork on a 3x tablet would
  /// otherwise ask for a several-thousand-pixel bitmap.
  static const int _maxDecodeWidth = 1080;

  /// Path to resolved file. A key present with a null value means "checked, and
  /// it is not there" — which is exactly the case worth remembering, since it is
  /// the one that would otherwise be re-checked forever.
  static final Map<String, File?> _resolved = <String, File?>{};

  /// Resolves [path] to a [File] known to exist, or null when there is nothing
  /// to render.
  ///
  /// Safe to call from `build`: on a cache hit it performs no I/O and allocates
  /// nothing.
  static File? resolve(String? path) {
    if (path == null || path.isEmpty) {
      return null;
    }
    final hit = _resolved[path];
    if (hit != null) {
      return hit;
    }
    if (_resolved.containsKey(path)) {
      return null;
    }
    if (_resolved.length >= _maxEntries) {
      _resolved.clear();
    }
    final file = File(path);
    final resolved = _existsSafely(file) ? file : null;
    _resolved[path] = resolved;
    return resolved;
  }

  static bool _existsSafely(File file) {
    try {
      return file.existsSync();
    } on FileSystemException {
      // An unreadable parent directory or a revoked storage grant is not a
      // programming error, it just means there is no artwork to show here.
      return false;
    }
  }

  /// Drops a remembered answer for [path] so the next [resolve] re-checks.
  ///
  /// Called from image error builders. Mutating this map during `build` is safe:
  /// it touches no widget, schedules no frame, and marks no element dirty, so
  /// the fallback simply renders this frame and the file is re-examined the next
  /// time something asks for it.
  static void forget(String? path) {
    if (path == null || path.isEmpty) {
      return;
    }
    _resolved.remove(path);
  }

  /// Forgets every remembered answer.
  ///
  /// Call this after any operation that can create artwork files — a library
  /// scan, an import, a user-chosen cover. Without it, a path that was checked
  /// before the file existed stays remembered as missing until the app restarts,
  /// which is precisely the "I rescanned and artwork still will not show up"
  /// symptom.
  static void invalidate() => _resolved.clear();

  /// Decode width, in device pixels, for artwork rendered at [logicalSize].
  ///
  /// `Image.file` decodes at the file's intrinsic size unless told otherwise, so
  /// a 1024px cover shown in a 48px tile would hold ~4MB in the image cache
  /// rather than ~9KB. Scaling by the device pixel ratio keeps it crisp on 3x
  /// screens without over-decoding on 1x ones; the ceiling stops a large hero
  /// artwork from undoing the point.
  ///
  /// The result must be stable across rebuilds — it forms part of the image
  /// cache key, so a value that drifted frame to frame would re-decode
  /// continuously.
  static int decodeWidth(double logicalSize, double devicePixelRatio) {
    final ratio = devicePixelRatio > 0 ? devicePixelRatio : 1.0;
    final scaled = logicalSize * ratio;
    if (!scaled.isFinite) {
      return _minDecodeWidth;
    }
    // Bounded with explicit comparisons rather than `clamp`, whose static
    // return type on int receivers relies on an analyzer special case.
    final rounded = scaled.round();
    if (rounded < _minDecodeWidth) {
      return _minDecodeWidth;
    }
    if (rounded > _maxDecodeWidth) {
      return _maxDecodeWidth;
    }
    return rounded;
  }

  @visibleForTesting
  static int get trackedPathCount => _resolved.length;
}

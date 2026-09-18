import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'artwork_palette.dart';

/// Deterministic cache identity for one artwork file.
///
/// Keyed on the artwork file's real on-disk identity — path, size and last
/// modification time — rather than song/album metadata, so two tracks sharing
/// one artwork reuse one palette while a changed cover automatically gets a
/// fresh key. Song titles/artist/album names are deliberately never part of
/// the key: they can collide and are not what the artwork *is*.
abstract final class ArtworkCacheKey {
  static const int hashLength = 24;

  /// 24-hex-char key derived from a file's identity.
  static Future<String> forFile(File file) async {
    final size = await _sizeOf(file);
    final modified = await _modifiedOf(file);
    return fromParts(file.path, size, modified);
  }

  /// Sync variant built from values already known to exist.
  static String fromParts(String path, int size, int modifiedMillis) {
    final payload = '$path\n$size\n$modifiedMillis';
    return sha256
        .convert(utf8.encode(payload))
        .toString()
        .substring(0, hashLength);
  }

  static Future<int> _sizeOf(File file) async {
    try {
      return await file.length();
    } on FileSystemException {
      return -1;
    }
  }

  static Future<int> _modifiedOf(File file) async {
    try {
      return (await file.stat()).modified.millisecondsSinceEpoch;
    } on FileSystemException {
      return -1;
    }
  }
}

/// Bounded in-memory + versioned disk cache of extracted [ArtworkPalette]s.
///
/// * In-memory LRU gives effectively immediate repeated lookups.
/// * Disk backing (one small JSON file per artwork key) survives app restarts
///   so a song that played last week does not re-extract today.
/// * Both layers carry the current [paletteAlgorithmVersion]; a bumped version
///   makes every stale mirror a miss and [pruneStaleVersions] sweeps the old
///   files.
///
/// Instances created without a directory operate memory-only (used by tests
/// and as a safe fallback when the storage directory cannot be resolved).
class ArtworkPaletteCache {
  ArtworkPaletteCache({Future<Directory> Function()? directory}) {
    _dirFuture = _resolveDirectory(directory);
  }

  late final Future<Directory?> _dirFuture;

  /// Memory LRU capacity.
  static const int memoryCap = 96;

  final Map<String, ArtworkPalette> _memory = {};
  final LinkedHashSet<String> _memoryKeys = LinkedHashSet();

  Future<Directory?> _resolveDirectory(
    Future<Directory> Function()? directory,
  ) async {
    if (directory == null) return null;
    try {
      return await directory();
    } catch (_) {
      return null;
    }
  }

  /// Synchronous in-memory peek. Never touches the disk, so it is safe on the
  /// first frame of a track change.
  ArtworkPalette? getSync(String key) {
    if (_memory.containsKey(key)) {
      _memoryKeys.remove(key);
      _memoryKeys.add(key);
      return _memory[key];
    }
    return null;
  }

  /// Full lookup: memory first, then the versioned disk file. Returns null on
  /// miss, or when the stored payload was produced by another algorithm
  /// version (the stale file is deleted so it cannot shadow a future fix).
  Future<ArtworkPalette?> get(String key) async {
    final mem = getSync(key);
    if (mem != null) return mem;
    final dir = await _dirFuture;
    if (dir == null) return null;
    final file = File(
      '${dir.path}${Platform.pathSeparator}$_filePrefix$key.json',
    );
    var candidate = null as ArtworkPalette?;
    try {
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      candidate = ArtworkPalette.decodeCachePayload(
        decoded is Map<String, Object?> ? decoded : null,
        expectedVersion: paletteAlgorithmVersion,
      );
    } catch (_) {
      candidate = null;
    }
    if (candidate != null) {
      _remember(key, candidate);
      return candidate;
    }
    // Corrupt payload or produced by another algorithm version: remove so it
    // cannot block a future rewrite of this key.
    try {
      await file.delete();
    } on FileSystemException {
      // best effort
    }
    return null;
  }

  /// Stores [palette] under [key], memory (bounded) and disk (best effort).
  Future<void> put(String key, ArtworkPalette palette) async {
    _remember(key, palette);
    final dir = await _dirFuture;
    if (dir == null) return;
    try {
      await dir.create(recursive: true);
      final file = File(
        '${dir.path}${Platform.pathSeparator}$_filePrefix$key.json',
      );
      await file.writeAsString(jsonEncode(palette.encodeCachePayload()));
    } catch (_) {
      // A failed disk write must never fail extraction.
    }
  }

  /// Drops a single key from memory only (disk entry kept).
  void forgetMemory(String key) {
    _memory.remove(key);
    _memoryKeys.remove(key);
  }

  /// Clears memory and deletes every palette file (older versions included).
  Future<void> clear() async {
    _memory.clear();
    _memoryKeys.clear();
    final dir = await _dirFuture;
    if (dir == null || !await dir.exists()) return;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File && entity.path.contains(_basePrefix)) {
          await entity.delete();
        }
      }
    } catch (_) {
      // best effort
    }
  }

  /// Deletes cached files whose algorithm version is no longer current.
  /// Current-version entries already self-invalidate via payload version
  /// checks; this just reclaims the space old files would otherwise occupy.
  Future<void> pruneStaleVersions() async {
    final dir = await _dirFuture;
    if (dir == null || !await dir.exists()) return;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File &&
            entity.path.contains(_basePrefix) &&
            !entity.path.contains(_filePrefix)) {
          await entity.delete();
        }
      }
    } catch (_) {
      // best effort
    }
  }

  @visibleForTesting
  int get memoryCount => _memory.length;

  String get _basePrefix => 'palette_';

  String get _filePrefix => 'palette_${paletteAlgorithmVersion}_';

  void _remember(String key, ArtworkPalette palette) {
    if (_memory.containsKey(key)) {
      _memory[key] = palette;
      return;
    }
    if (_memory.length >= memoryCap) {
      final oldest = _memoryKeys.first;
      _memory.remove(oldest);
      _memoryKeys.remove(oldest);
    }
    _memory[key] = palette;
    _memoryKeys.add(key);
  }
}

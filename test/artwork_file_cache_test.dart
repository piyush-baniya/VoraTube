import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/ingest/artwork/artwork_file_cache.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    // Global static state, so every test starts from a known-empty cache.
    ArtworkFileCache.invalidate();
    tempDir = Directory.systemTemp.createTempSync('vt_art_cache_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  File writeArt(String name) {
    final file = File('${tempDir.path}/$name');
    file.writeAsBytesSync(const [0x52, 0x49, 0x46, 0x46]);
    return file;
  }

  group('resolve', () {
    test('treats a null or empty path as no artwork', () {
      expect(ArtworkFileCache.resolve(null), isNull);
      expect(ArtworkFileCache.resolve(''), isNull);
      // Neither should occupy a cache slot.
      expect(ArtworkFileCache.trackedPathCount, 0);
    });

    test('resolves a file that exists', () {
      final art = writeArt('cover.webp');

      final resolved = ArtworkFileCache.resolve(art.path);

      expect(resolved, isNotNull);
      expect(resolved!.path, art.path);
    });

    test('returns null for a path with no file behind it', () {
      expect(ArtworkFileCache.resolve('${tempDir.path}/absent.webp'), isNull);
    });

    test('remembers a miss so it is not re-checked', () {
      final path = '${tempDir.path}/absent.webp';

      expect(ArtworkFileCache.resolve(path), isNull);
      expect(ArtworkFileCache.trackedPathCount, 1);

      // Creating the file now must NOT be picked up: the whole point of the
      // cache is that it stops asking the filesystem. Invalidation is what
      // makes newly written artwork visible, and the scan controller is
      // responsible for calling it.
      writeArt('absent.webp');
      expect(ArtworkFileCache.resolve(path), isNull);

      ArtworkFileCache.invalidate();
      expect(ArtworkFileCache.resolve(path), isNotNull);
    });

    test('remembers a hit so it is not re-checked', () {
      final art = writeArt('cover.webp');
      expect(ArtworkFileCache.resolve(art.path), isNotNull);

      art.deleteSync();
      // Still a hit: the cache is deliberately stale here, and the widgets'
      // errorBuilder is what notices and calls forget().
      expect(ArtworkFileCache.resolve(art.path), isNotNull);

      ArtworkFileCache.forget(art.path);
      expect(ArtworkFileCache.resolve(art.path), isNull);
    });

    test('forget on an untracked or empty path is harmless', () {
      ArtworkFileCache.forget(null);
      ArtworkFileCache.forget('');
      ArtworkFileCache.forget('${tempDir.path}/never_seen.webp');
      expect(ArtworkFileCache.trackedPathCount, 0);
    });

    test('invalidate clears every remembered answer', () {
      final a = writeArt('a.webp');
      final b = writeArt('b.webp');
      ArtworkFileCache.resolve(a.path);
      ArtworkFileCache.resolve(b.path);
      ArtworkFileCache.resolve('${tempDir.path}/c.webp');
      expect(ArtworkFileCache.trackedPathCount, 3);

      ArtworkFileCache.invalidate();

      expect(ArtworkFileCache.trackedPathCount, 0);
    });
  });

  group('decodeWidth', () {
    test('scales by device pixel ratio', () {
      expect(ArtworkFileCache.decodeWidth(48, 3), 144);
      expect(ArtworkFileCache.decodeWidth(48, 1), 48);
    });

    test('clamps to a sane range', () {
      // A full-screen hero on a 3x tablet must not ask for a 3,000px bitmap.
      expect(ArtworkFileCache.decodeWidth(1200, 3), 1080);
      // A tiny indicator still decodes something legible.
      expect(ArtworkFileCache.decodeWidth(4, 1), 32);
    });

    test('survives a nonsensical pixel ratio', () {
      // Some embedders report 0 before the first frame.
      expect(ArtworkFileCache.decodeWidth(64, 0), 64);
      expect(ArtworkFileCache.decodeWidth(64, -2), 64);
      expect(ArtworkFileCache.decodeWidth(double.infinity, 2), 32);
      expect(ArtworkFileCache.decodeWidth(double.nan, 2), 32);
    });
  });
}

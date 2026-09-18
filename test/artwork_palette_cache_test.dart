import 'dart:io';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/core/artwork_palette/artwork_palette.dart';
import 'package:vora_tube/core/artwork_palette/artwork_palette_cache.dart';

import 'fakes/tiny_png.dart';

ArtworkPalette sample() {
  return const ArtworkPalette(
    dominant: Color(0xFF101010),
    vibrant: Color(0xFF202020),
    muted: Color(0xFF303030),
    dark: Color(0xFF404040),
    darkMuted: Color(0xFF505050),
    light: Color(0xFF606060),
    lightVibrant: Color(0xFF707070),
    surface: Color(0xFF808080),
    surfaceVariant: Color(0xFF909090),
    accent: Color(0xFFA0A0A0),
    secondaryAccent: Color(0xFFB0B0B0),
    onSurface: Color(0xFFC0C0C0),
    onAccent: Color(0xFFD0D0D0),
    backgroundStart: Color(0xFFE0E0E0),
    backgroundEnd: Color(0xFFF0F0F0),
    sourceArtworkKey: 'abc',
    extractionVersion: paletteAlgorithmVersion,
    wasFallback: false,
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('palette_cache_test');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // best effort cleanup on Windows
    }
  });

  group('ArtworkCacheKey', () {
    test('identical identity yields identical key from parts', () {
      expect(
        ArtworkCacheKey.fromParts('a.png', 1234, 1000),
        ArtworkCacheKey.fromParts('a.png', 1234, 1000),
      );
    });

    test('anything differing yields a different key', () {
      final base = ArtworkCacheKey.fromParts('a.png', 1234, 1000);
      expect(base, isNot(ArtworkCacheKey.fromParts('b.png', 1234, 1000)));
      expect(base, isNot(ArtworkCacheKey.fromParts('a.png', 1235, 1000)));
      expect(base, isNot(ArtworkCacheKey.fromParts('a.png', 1234, 1001)));
    });

    test('key reflects real file changes', () async {
      final file = await writeTempFile(tempDir, 'cover.png', [1, 2, 3]);
      final before = await ArtworkCacheKey.forFile(file);
      await file.writeAsBytes([9, 8, 7]); // same size, same path
      expect(await ArtworkCacheKey.forFile(file), isNot(before));
      await file.writeAsBytes([9, 8, 7, 6]); // size change
      expect(await ArtworkCacheKey.forFile(file), isNot(before));
    });

    test('key length is 24 hex chars', () async {
      final file = await writeTempFile(tempDir, 'a.png', [9, 9]);
      final key = await ArtworkCacheKey.forFile(file);
      expect(key, matches(RegExp(r'^[0-9a-f]{24}$')));
    });
  });

  group('ArtworkPaletteCache', () {
    ArtworkPaletteCache memoryOnly() => ArtworkPaletteCache();

    ArtworkPaletteCache diskBacked() =>
        ArtworkPaletteCache(directory: () async => tempDir);

    test('memory-only put/get works without a directory', () async {
      final cache = memoryOnly();
      await cache.put('key', sample());
      expect(cache.getSync('key'), sample());
    });

    test('disk round-trip survives a fresh cache instance', () async {
      final write = diskBacked();
      await write.put('p-key', sample());
      final read = diskBacked();
      final loaded = await read.get('p-key');
      expect(loaded, sample());
      expect(loaded!.sourceArtworkKey, 'abc');
    });

    test('memory hit is synchronous and returns the stored instance', () async {
      final cache = diskBacked();
      final palette = sample();
      await cache.put('x', palette);
      expect(identical(cache.getSync('x'), palette), isTrue);
    });

    test('disk get after memory eviction still finds the palette', () async {
      final cache = diskBacked();
      await cache.put('x', sample());
      cache.forgetMemory('x');
      expect(cache.getSync('x'), isNull);
      // A full get re-loads from disk.
      final reloaded = await cache.get('x');
      expect(reloaded, sample());
    });

    test('memory LRU evicts beyond capacity', () async {
      final cache = diskBacked();
      for (var i = 0; i < ArtworkPaletteCache.memoryCap + 10; i++) {
        await cache.put('k$i', sample());
      }
      expect(
        cache.memoryCount,
        lessThanOrEqualTo(ArtworkPaletteCache.memoryCap),
      );
      expect(cache.getSync('k0'), isNull, reason: 'oldest evicted');
    });

    test(
      'corrupt or stale-version disk files are rejected and swept',
      () async {
        final cache = diskBacked();
        await cache.put('good', sample());
        // Seed a stale-version file next to it.
        final stale = File(
          '${tempDir.path}${Platform.pathSeparator}'
          'palette_999_stale.json',
        );
        await stale.writeAsString('{"v":999}');
        // Current-version file with broken content.
        final broken = File(
          '${tempDir.path}${Platform.pathSeparator}'
          'palette_${paletteAlgorithmVersion}_broken.json',
        );
        await broken.writeAsString('not json');

        expect(await cache.get('good'), isNotNull);
        expect(await diskBacked().get('stale'), isNull);
        expect(await diskBacked().get('broken'), isNull);
        // Rejected payloads are deleted so they cannot shadow a fix later.
        expect(await broken.exists(), isFalse);
        expect(
          await stale.exists(),
          isTrue,
          reason: 'stale files persist until pruned',
        );

        await diskBacked().pruneStaleVersions();
        expect(await stale.exists(), isFalse);
        expect(
          await File(
            '${tempDir.path}${Platform.pathSeparator}'
            'palette_${paletteAlgorithmVersion}_good.json',
          ).exists(),
          isTrue,
        );
      },
    );

    test('clear removes memory and every palette file', () async {
      final cache = diskBacked();
      await cache.put('a', sample());
      await cache.put('b', sample());
      expect(await cache.get('a'), isNotNull);
      await cache.clear();
      expect(cache.memoryCount, 0);
      expect(await diskBacked().get('a'), isNull);
    });

    test('directory resolution failures degrade to memory-only', () async {
      final cache = ArtworkPaletteCache(
        directory: () async => throw StateError('denied'),
      );
      await cache.put('k', sample());
      expect(cache.getSync('k'), sample());
    });

    test('put is best-effort: a write failure never throws', () async {
      final cache = ArtworkPaletteCache(
        directory: () async {
          final dir = Directory(
            '${tempDir.path}${Platform.pathSeparator}sub${Platform.pathSeparator}nested',
          );
          // Make the parent a file so create(recursive:true) fails.
          await File('${tempDir.path}${Platform.pathSeparator}sub')
              .writeAsString('x');
          return dir;
        },
      );
      await cache.put('k', sample());
      expect(cache.getSync('k'), sample());
    });
  });
}

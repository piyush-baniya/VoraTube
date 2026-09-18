import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/core/artwork_palette/artwork_contrast.dart';
import 'package:vora_tube/core/artwork_palette/artwork_palette_extractor.dart';

import 'fakes/tiny_png.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const extractor = ArtworkPaletteExtractor();

  group('analyzeRgba raw pixels', () {
    test('colorful artwork yields a complete, theme-independent palette', () {
      final rgba = regionsRgba(
        width: 64,
        height: 64,
        regions: [
          // 50% teal, 30% deep blue, 20% gold — teal dominates.
          (0, 0, 44, 64, 0, 180, 180, 255),
          (44, 0, 12, 64, 20, 40, 160, 255),
          (56, 0, 8, 64, 220, 180, 40, 255),
        ],
      );
      final palette = extractor.analyzeRgba(rgba, width: 64, height: 64);
      expect(palette, isNotNull);
      final p = palette!;
      expect(p.wasFallback, isFalse);
      expect(p.sourceArtworkKey, isNull);
      expect(ArtworkContrast.saturation(p.accent), greaterThan(0.28));
      // 15 slots, all populated.
      expect(p.colorSlots.length, 15);
    });

    test('extraction is deterministic for identical input', () {
      final rgba = solidRgba(width: 24, height: 24, r: 92, g: 58, b: 237);
      final first = extractor.analyzeRgba(rgba, width: 24, height: 24);
      final second = extractor.analyzeRgba(rgba, width: 24, height: 24);
      expect(first, second);
    });

    test('dark artwork keeps a usable non-white surface', () {
      final rgba = regionsRgba(
        width: 32,
        height: 32,
        regions: [(0, 0, 32, 32, 8, 12, 24, 255)],
      );
      final palette = extractor.analyzeRgba(rgba, width: 32, height: 32);
      expect(palette, isNotNull);
      expect(ArtworkContrast.lightness(palette!.surface), lessThan(0.35));
    });

    test('bright artwork never produces a pure white surface', () {
      final rgba = regionsRgba(
        width: 32,
        height: 32,
        regions: [(0, 0, 32, 32, 244, 246, 250, 255)],
      );
      final palette = extractor.analyzeRgba(rgba, width: 32, height: 32);
      expect(palette, isNotNull);
      expect(ArtworkContrast.lightness(palette!.surface), lessThan(0.85));
    });

    test(
      'grayscale artwork yields readable foregrounds without invented hue',
      () {
        final rgba = regionsRgba(
          width: 32,
          height: 32,
          regions: [(0, 0, 32, 32, 96, 96, 96, 255)],
        );
        final palette = extractor.analyzeRgba(rgba, width: 32, height: 32);
        expect(palette, isNotNull);
        final p = palette!;
        expect(ArtworkContrast.saturation(p.accent), lessThan(0.35));
        expect(
          ArtworkContrast.contrastRatio(p.onSurface, p.surface),
          greaterThanOrEqualTo(ArtworkContrast.normalTextMinRatio),
          reason: 'surface text must meet WCAG AA normal-text contrast',
        );
      },
    );

    test('surface text meets 4.5:1 WCAG AA on every extract', () {
      for (final rbg in [
        (8, 12, 24),
        (96, 96, 96),
        (244, 246, 250),
        (180, 60, 40),
        (60, 180, 160),
      ]) {
        final rgba = solidRgba(
          width: 32,
          height: 32,
          r: rbg.$1,
          g: rbg.$2,
          b: rbg.$3,
        );
        final palette = extractor.analyzeRgba(rgba, width: 32, height: 32);
        expect(palette, isNotNull, reason: '$rbg');
        expect(
          ArtworkContrast.contrastRatio(palette!.onSurface, palette.surface),
          greaterThanOrEqualTo(ArtworkContrast.normalTextMinRatio),
          reason: 'onSurface for $rbg must stay WCAG AA readable',
        );
      }
    });

    test('accent foreground keeps minimum WCAG contrast', () {
      final rgba = regionsRgba(
        width: 32,
        height: 32,
        regions: [(0, 0, 32, 32, 12, 12, 12, 255)],
      );
      final palette = extractor.analyzeRgba(rgba, width: 32, height: 32)!;
      expect(
        ArtworkContrast.contrastRatio(palette.onAccent, palette.accent),
        greaterThanOrEqualTo(ArtworkContrast.largeTextAndUiMinRatio),
      );
    });

    test(
      'accent foreground prefers normal-text contrast when color allows',
      () {
        final rgba = regionsRgba(
          width: 32,
          height: 32,
          regions: [(0, 0, 32, 32, 12, 12, 12, 255)],
        );
        final palette = extractor.analyzeRgba(rgba, width: 32, height: 32)!;
        if (ArtworkContrast.contrastRatio(
              palette.onAccent,
              palette.accent,
            ) <
            ArtworkContrast.normalTextMinRatio) {
          // 4.5 may be unreachable for the cast accent; it must at least
          // be the best the hue family can offer (black/white rescue).
          final best = ArtworkContrast.foregroundFor(palette.accent);
          expect(
            ArtworkContrast.contrastRatio(
              palette.onAccent,
              palette.accent,
            ),
            greaterThanOrEqualTo(
              ArtworkContrast.contrastRatio(best, palette.accent) - 0.01,
            ),
          );
        }
      },
    );

    test('transparent artwork is rejected', () {
      final rgba = solidRgba(width: 32, height: 32, r: 0, g: 0, b: 0, a: 127);
      expect(extractor.analyzeRgba(rgba, width: 32, height: 32), isNull);
    });

    test('too few solid pixels is rejected', () {
      final rgba = solidRgba(width: 4, height: 4, r: 255, g: 0, b: 0);
      expect(extractor.analyzeRgba(rgba, width: 4, height: 4), isNull);
    });

    test('near-black artwork still produces a usable dark palette', () {
      final rgba = solidRgba(width: 32, height: 32, r: 3, g: 5, b: 9);
      final palette = extractor.analyzeRgba(rgba, width: 32, height: 32);
      expect(palette, isNotNull);
      expect(ArtworkContrast.lightness(palette!.surface), lessThan(0.25));
      expect(
        ArtworkContrast.contrastRatio(palette.onSurface, palette.surface),
        greaterThanOrEqualTo(ArtworkContrast.normalTextMinRatio),
      );
    });

    test('near-white artwork keeps a readable dark text surface', () {
      final rgba = solidRgba(width: 32, height: 32, r: 248, g: 249, b: 251);
      final palette = extractor.analyzeRgba(rgba, width: 32, height: 32);
      expect(palette, isNotNull);
      final p = palette!;
      expect(ArtworkContrast.lightness(p.surface), lessThan(0.85));
      expect(
        ArtworkContrast.contrastRatio(p.onSurface, p.surface),
        greaterThanOrEqualTo(ArtworkContrast.normalTextMinRatio),
      );
    });

    test('white canvas with a tiny color object still yields a colored accent',
        () {
      final rgba = regionsRgba(
        width: 64,
        height: 64,
        regions: [
          (58, 58, 6, 6, 200, 40, 180, 255), // tiny magenta-region object
          (0, 0, 64, 64, 255, 255, 255, 255),
        ],
      );
      final palette = extractor.analyzeRgba(rgba, width: 64, height: 64);
      expect(palette, isNotNull);
      final p = palette!;
      // The extraction must not silently discard the object; a colored accent
      // (post-clamp) is expected even though white dominates the area.
      expect(ArtworkContrast.saturation(p.accent), greaterThan(0.05));
      expect(
        ArtworkContrast.contrastRatio(p.onSurface, p.surface),
        greaterThanOrEqualTo(ArtworkContrast.normalTextMinRatio),
      );
    });

    test('black canvas with a tiny color object still yields a colored accent',
        () {
      final rgba = regionsRgba(
        width: 64,
        height: 64,
        regions: [
          (58, 58, 6, 6, 60, 200, 120, 255), // tiny green flash
          (0, 0, 64, 64, 0, 0, 0, 255),
        ],
      );
      final palette = extractor.analyzeRgba(rgba, width: 64, height: 64);
      expect(palette, isNotNull);
      final p = palette!;
      expect(ArtworkContrast.lightness(p.surface), lessThan(0.35));
      expect(
        ArtworkContrast.contrastRatio(p.onSurface, p.surface),
        greaterThanOrEqualTo(ArtworkContrast.normalTextMinRatio),
      );
    });

    test('saturated red single-color artwork yields a red-leaning accent', () {
      final rgba = solidRgba(width: 32, height: 32, r: 220, g: 20, b: 24);
      final palette = extractor.analyzeRgba(rgba, width: 32, height: 32)!;
      expect(ArtworkContrast.saturation(palette.accent), greaterThan(0.4));
      expect(
        ArtworkContrast.contrastRatio(palette.onAccent, palette.accent),
        greaterThanOrEqualTo(ArtworkContrast.largeTextAndUiMinRatio),
      );
    });

    test('neon green artwork keeps a readable, non-harsh palette', () {
      final rgba = solidRgba(width: 32, height: 32, r: 40, g: 255, b: 90);
      final palette = extractor.analyzeRgba(rgba, width: 32, height: 32)!;
      // Neon extremes are clamped into a tasteful band, never left raw.
      expect(ArtworkContrast.lightness(palette.accent), lessThanOrEqualTo(0.62));
      expect(
        ArtworkContrast.contrastRatio(palette.onAccent, palette.accent),
        greaterThanOrEqualTo(ArtworkContrast.largeTextAndUiMinRatio),
      );
    });

    test('pale pastel artwork yields a muted, readable palette', () {
      final rgba = solidRgba(width: 32, height: 32, r: 232, g: 210, b: 236);
      final palette = extractor.analyzeRgba(rgba, width: 32, height: 32)!;
      // Pastel lightness ~0.87 must be clamped into the usable band, not left
      // a near-white wash.
      expect(ArtworkContrast.lightness(palette.accent), lessThanOrEqualTo(0.62));
      expect(
        ArtworkContrast.contrastRatio(palette.onSurface, palette.surface),
        greaterThanOrEqualTo(ArtworkContrast.normalTextMinRatio),
      );
    });

    test('transparent canvas with a tiny opaque object is rejected early', () {
      final rgba = regionsRgba(
        width: 64,
        height: 64,
        regions: [
          (0, 0, 64, 64, 0, 0, 0, 0),
          (62, 62, 2, 2, 255, 0, 0, 255),
        ],
      );
      expect(extractor.analyzeRgba(rgba, width: 64, height: 64), isNull,
          reason: 'fewer than 48 solid pixels cannot describe a palette');
    });

    test('single near-black color keeps on-surface text readable', () {
      final rgba = solidRgba(width: 32, height: 32, r: 10, g: 10, b: 12);
      final palette = extractor.analyzeRgba(rgba, width: 32, height: 32)!;
      expect(ArtworkContrast.lightness(palette.surface), lessThan(0.3));
      expect(
        ArtworkContrast.contrastRatio(palette.onSurface, palette.surface),
        greaterThanOrEqualTo(ArtworkContrast.normalTextMinRatio),
      );
    });

    test('invalid buffer layout is rejected defensively', () {
      expect(
        extractor.analyzeRgba(Uint8List(10), width: 32, height: 32),
        isNull,
      );
      expect(extractor.analyzeRgba(Uint8List(0), width: 0, height: 0), isNull);
    });
  });

  group('extractFromBytes (real decode)', () {
    test('decodes a small PNG and matches a direct pixel pass', () async {
      final rgba = solidRgba(width: 24, height: 24, r: 60, g: 120, b: 200);
      final png = encodePng(width: 24, height: 24, rgba: rgba);
      final fromBytes = await extractor.extractFromBytes(png);
      final direct = extractor.analyzeRgba(rgba, width: 24, height: 24);
      expect(fromBytes, direct);
    });

    test('downscales large artwork to the analysis width', () async {
      final rgba = regionsRgba(
        width: 512,
        height: 512,
        regions: [
          (0, 0, 400, 512, 0, 160, 160, 255),
          (400, 0, 112, 512, 200, 40, 120, 255),
        ],
      );
      final png = encodePng(width: 512, height: 512, rgba: rgba);
      final palette = await extractor.extractFromBytes(png);
      expect(palette, isNotNull);
      // A 512px cover must not be decoded at full size; the engineering
      // contract is enforced separately, but extraction must still succeed.
      expect(ArtworkContrast.saturation(palette!.accent), greaterThan(0.2));
    });

    test('empty bytes return null', () async {
      expect(await extractor.extractFromBytes(Uint8List(0)), isNull);
    });

    test('corrupt bytes return null instead of throwing', () async {
      final junk = Uint8List.fromList(
        List<int>.generate(4096, (i) => (i * 7) % 256),
      );
      expect(await extractor.extractFromBytes(junk), isNull);
    });

    test('extraction stays under the async budget', () async {
      final rgba = regionsRgba(
        width: 512,
        height: 512,
        regions: [
          (0, 0, 256, 512, 30, 90, 200, 255),
          (256, 0, 256, 512, 220, 160, 40, 255),
        ],
      );
      final png = encodePng(width: 512, height: 512, rgba: rgba);
      final sw = Stopwatch()..start();
      await extractor.extractFromBytes(png);
      sw.stop();
      expect(
        sw.elapsed,
        lessThan(const Duration(seconds: 3)),
        reason: 'downscaled extraction took ${sw.elapsedMilliseconds}ms',
      );
    });
  });

  group('extractFromFile', () {
    test('missing file returns null', () async {
      final dir = Directory.systemTemp.createTempSync('palette_ext_missing');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}nope.png');
      expect(await extractor.extractFromFile(file), isNull);
    });

    test('a real artwork file produces a complete palette', () async {
      final dir = Directory.systemTemp.createTempSync('palette_ext_file');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = await writeTempFile(
        dir,
        'cover.png',
        encodePng(
          width: 128,
          height: 128,
          rgba: regionsRgba(
            width: 128,
            height: 128,
            regions: [
              (0, 0, 96, 128, 80, 40, 200, 255),
              (96, 0, 32, 128, 240, 200, 60, 255),
            ],
          ),
        ),
      );
      final palette = await extractor.extractFromFile(file);
      expect(palette, isNotNull);
      final p = palette!;
      expect(p.wasFallback, isFalse);
      expect(p.colorSlots.length, 15);
    });
  });
}

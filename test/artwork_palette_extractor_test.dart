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
          greaterThanOrEqualTo(3.0),
        );
      },
    );

    test('accent foreground keeps minimum WCAG contrast', () {
      final rgba = regionsRgba(
        width: 32,
        height: 32,
        regions: [(0, 0, 32, 32, 12, 12, 12, 255)],
      );
      final palette = extractor.analyzeRgba(rgba, width: 32, height: 32)!;
      expect(
        ArtworkContrast.contrastRatio(palette.onAccent, palette.accent),
        greaterThanOrEqualTo(3.0),
      );
    });

    test('transparent artwork is rejected', () {
      final rgba = solidRgba(width: 32, height: 32, r: 0, g: 0, b: 0, a: 127);
      expect(extractor.analyzeRgba(rgba, width: 32, height: 32), isNull);
    });

    test('too few solid pixels is rejected', () {
      final rgba = solidRgba(width: 4, height: 4, r: 255, g: 0, b: 0);
      expect(extractor.analyzeRgba(rgba, width: 4, height: 4), isNull);
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

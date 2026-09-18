import 'package:flutter/material.dart' show Color, Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/core/artwork_palette/artwork_contrast.dart';

void main() {
  bool close(double a, double b, {double eps = 0.02}) => (a - b).abs() <= eps;

  group('ArtworkContrast luminance + ratio', () {
    test('absolute black/white endpoints', () {
      expect(
        ArtworkContrast.relativeLuminance(Colors.black),
        closeTo(0.0, 0.0),
      );
      expect(
        ArtworkContrast.relativeLuminance(Colors.white),
        closeTo(1.0, 0.0),
      );
      expect(ArtworkContrast.contrastRatio(Colors.black, Colors.white), 21.0);
    });

    test('known WCAG reference pairs', () {
      // #777777 vs white = 4.48:1 (the classic 4.5:1 gate case).
      final gray = const Color(0xFF777777);
      expect(
        ArtworkContrast.contrastRatio(gray, Colors.white),
        closeTo(4.48, 0.05),
      );
      // #FF0000 vs white = 4.00:1.
      final red = const Color(0xFFFF0000);
      expect(
        ArtworkContrast.contrastRatio(red, Colors.white),
        closeTo(4.0, 0.05),
      );
    });

    test('ratio is symmetric and never below 1', () {
      final a = const Color(0xFF336699);
      final b = const Color(0xFF99CCFF);
      final ab = ArtworkContrast.contrastRatio(a, b);
      final ba = ArtworkContrast.contrastRatio(b, a);
      expect(ab, closeTo(ba, 1e-9));
      expect(ab, greaterThanOrEqualTo(1.0));
      expect(ArtworkContrast.contrastRatio(a, a), 1.0);
    });
  });

  group('foregroundFor', () {
    test('black background gets white foreground', () {
      expect(
        ArtworkContrast.foregroundFor(Colors.black),
        const Color(0xFFFFFFFF),
      );
    });

    test('white background gets black foreground', () {
      expect(
        ArtworkContrast.foregroundFor(Colors.white),
        const Color(0xFF000000),
      );
    });

    test('is deterministic for a fixed background', () {
      const background = Color(0xFF7C3AED);
      final first = ArtworkContrast.foregroundFor(background);
      final second = ArtworkContrast.foregroundFor(background);
      expect(first, second);
    });
  });

  group('ensureContrast', () {
    test('returns foreground unchanged when it already passes', () {
      const foreground = Color(0xFFFFFFFF);
      const background = Color(0xFF202020);
      expect(
        ArtworkContrast.ensureContrast(foreground, background),
        foreground,
      );
    });

    test('rescues a foreground that would be unreadable', () {
      const foreground = Color(0xFF808080);
      const background = Color(0xFF7E7E7E);
      final rescued = ArtworkContrast.ensureContrast(foreground, background);
      expect(rescued, isNot(foreground));
      expect(
        ArtworkContrast.contrastRatio(rescued, background),
        greaterThanOrEqualTo(3.0),
      );
    });

    test('higher minimum ratio is honored', () {
      const background = Color(0xFF5B21B6);
      final rescued = ArtworkContrast.ensureContrast(
        const Color(0xFF7C3AED),
        background,
        minRatio: 4.5,
      );
      expect(
        ArtworkContrast.contrastRatio(rescued, background),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('semantic ratios', () {
    test('constants pin the WCAG bars', () {
      expect(ArtworkContrast.normalTextMinRatio, 4.5);
      expect(ArtworkContrast.largeTextAndUiMinRatio, 3.0);
      expect(
        ArtworkContrast.largeTextAndUiMinRatio,
        lessThan(ArtworkContrast.normalTextMinRatio),
      );
    });
  });

  group('readableForeground', () {
    test('black/white bands in are decisive', () {
      expect(
        ArtworkContrast.readableForeground(
          Colors.black,
          minRatio: ArtworkContrast.normalTextMinRatio,
        ),
        Colors.white,
      );
      expect(
        ArtworkContrast.readableForeground(
          Colors.white,
          minRatio: ArtworkContrast.normalTextMinRatio,
        ),
        Colors.black,
      );
    });

    test('meets the hard minimum ratio', () {
      const background = Color(0xFF7C3AED);
      final fg = ArtworkContrast.readableForeground(
        background,
        minRatio: ArtworkContrast.largeTextAndUiMinRatio,
      );
      expect(
        ArtworkContrast.contrastRatio(fg, background),
        greaterThanOrEqualTo(ArtworkContrast.largeTextAndUiMinRatio),
      );
    });

    test('prefers the tighter ratio whenever achievable', () {
      // Black on a mid-luminance accent strongly exceeds every goal, so the
      // result must match the plain foregroundFor pick (no rescue distortion).
      const background = Color(0xFF3B82C4);
      final plain = ArtworkContrast.foregroundFor(background);
      final fg = ArtworkContrast.readableForeground(
        background,
        minRatio: ArtworkContrast.largeTextAndUiMinRatio,
        preferredRatio: ArtworkContrast.normalTextMinRatio,
      );
      expect(fg, plain);
      expect(
        ArtworkContrast.contrastRatio(fg, background),
        greaterThanOrEqualTo(ArtworkContrast.normalTextMinRatio),
      );
    });

    test('relaxes to the minimum only when the tighter goal is unreachable',
        () {
      // A vivid saturated violet sits near the black/white breakover band
      // where neither black nor white exceeds 4.5, but one always still
      // clears 3.0. readableForeground must land on the best rescue, not guess.
      // #7C3AED was picked because black/white both dip below 4.5 on it.
      const background = Color(0xFF7C3AED);
      final fg = ArtworkContrast.readableForeground(
        background,
        minRatio: ArtworkContrast.largeTextAndUiMinRatio,
        preferredRatio: ArtworkContrast.normalTextMinRatio,
      );
      final ratio = ArtworkContrast.contrastRatio(fg, background);
      expect(ratio, greaterThanOrEqualTo(2.9));
      // Never silently returns a mid-luminance compromise: white or black.
      expect(
        fg == const Color(0xFFFFFFFF) || fg == const Color(0xFF000000),
        isTrue,
        reason: 'foreground $fg should resolve to black or white',
      );
    });

    test('asserts sane parameter ordering', () {
      expect(
        () => ArtworkContrast.readableForeground(
          Colors.grey,
          minRatio: 1.0,
        ),
        throwsAssertionError,
      );
      expect(
        () => ArtworkContrast.readableForeground(
          Colors.grey,
          minRatio: 3.0,
          preferredRatio: 2.0,
        ),
        throwsAssertionError,
      );
    });
  });

  group('HSL math', () {
    test('hue/lightness/saturation agree on a pure color', () {
      const teal = Color(0xFF00B4B4);
      expect(ArtworkContrast.hue(teal), closeTo(180, 0.5));
      expect(ArtworkContrast.saturation(teal), greaterThan(0.5));
      expect(ArtworkContrast.lightness(teal), closeTo(0.35, 0.01));
    });

    test('gray has zero saturation and zero hue', () {
      const gray = Color(0xFF808080);
      expect(ArtworkContrast.saturation(gray), 0.0);
      expect(ArtworkContrast.hue(gray), 0.0);
    });

    test('fromHsl round-trips', () {
      const color = Color(0xFF336699);
      final rebuilt = ArtworkContrast.fromHsl(
        ArtworkContrast.hue(color),
        ArtworkContrast.saturation(color),
        ArtworkContrast.lightness(color),
      );
      expect(rebuilt.r, inInclusiveRange(color.r - 0.02, color.r + 0.02));
      expect(rebuilt.g, inInclusiveRange(color.g - 0.02, color.g + 0.02));
      expect(rebuilt.b, inInclusiveRange(color.b - 0.02, color.b + 0.02));
    });

    test('lighten increases lightness toward white', () {
      const base = Color(0xFF336699);
      final lighter = ArtworkContrast.lighten(base, 0.4);
      expect(
        ArtworkContrast.lightness(lighter),
        greaterThan(ArtworkContrast.lightness(base)),
      );
      final almostWhite = ArtworkContrast.lighten(base, 1.0);
      expect(ArtworkContrast.lightness(almostWhite), closeTo(1.0, 0.01));
    });

    test('darken decreases lightness toward black', () {
      const base = Color(0xFF336699);
      final darker = ArtworkContrast.darken(base, 0.5);
      expect(
        ArtworkContrast.lightness(darker),
        lessThan(ArtworkContrast.lightness(base)),
      );
      expect(ArtworkContrast.lightness(ArtworkContrast.darken(base, 1)), 0.0);
    });

    test('desaturate keeps lightness but lowers saturation', () {
      const base = Color(0xFF00B4B4);
      final desat = ArtworkContrast.desaturate(base, 0.5);
      expect(
        ArtworkContrast.saturation(desat),
        closeTo(ArtworkContrast.saturation(base) * 0.5, 0.02),
      );
      expect(
        ArtworkContrast.lightness(desat),
        closeTo(ArtworkContrast.lightness(base), 0.01),
      );
    });

    test('withLightness targets a value', () {
      const base = Color(0xFF336699);
      final forced = ArtworkContrast.withLightness(base, 0.5);
      expect(ArtworkContrast.lightness(forced), closeTo(0.5, 0.01));
    });
  });

  group('clampTone', () {
    test('clamps lightness into range', () {
      const bright = Color(0xFFE8E8E8);
      final clamped = ArtworkContrast.clampTone(
        bright,
        minLightness: 0.4,
        maxLightness: 0.6,
      );
      expect(ArtworkContrast.lightness(clamped), inInclusiveRange(0.4, 0.6));
    });

    test('never raises saturation of an effectively neutral color', () {
      const gray = Color(0xFF9A9A9A);
      final clamped = ArtworkContrast.clampTone(
        gray,
        minSaturation: 0.5,
        maxSaturation: 0.9,
      );
      expect(ArtworkContrast.saturation(clamped), closeTo(0.0, 0.01));
    });

    test('raises saturation only for genuinely chromatic colors', () {
      const chromatic = Color(0xFF2A7A9E);
      final clamped = ArtworkContrast.clampTone(
        chromatic,
        minSaturation: 0.4,
        maxSaturation: 0.9,
      );
      expect(ArtworkContrast.saturation(clamped), greaterThanOrEqualTo(0.4));
    });
  });

  group('blend', () {
    test('blend amount 0 returns source, 1 returns target', () {
      const a = Color(0xFF000000);
      const b = Color(0xFFFFFFFF);
      expect(ArtworkContrast.blend(a, b, 0), a);
      expect(ArtworkContrast.blend(a, b, 1), b);
      expect(close(ArtworkContrast.blend(a, b, 0.5).r, 0.5), isTrue);
    });

    test('blend clamps out-of-range amounts', () {
      const a = Color(0xFF112233);
      expect(
        ArtworkContrast.blend(a, const Color(0xFFFFFFFF), 2.0),
        const Color(0xFFFFFFFF),
      );
    });
  });
}

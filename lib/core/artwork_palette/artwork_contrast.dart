import 'dart:math' as math;

import 'package:flutter/material.dart' show Color;

/// Dart-side color math used by the artwork palette engine.
///
/// Everything here is pure and side-effect free so extraction, fallback
/// derivation and tests share one implementation. The metrics follow the WCAG
/// 2.x relative-luminance model, which is the de-facto readable-contrast
/// standard and is what the accessibility requirements in this feature are
/// pinned to.
///
/// Colors are treated as opaque (RGB). Alpha is intentionally ignored by the
/// arithmetic functions: surfaces the app will paint on must be opaque by the
/// time a contrast decision is made, and pretending otherwise produces
/// contrast numbers that do not exist on a real screen.
abstract final class ArtworkContrast {
  /// WCAG AA minimum contrast ratio for normal-size text.
  ///
  /// The palette engine guarantees surface text against extracted surfaces,
  /// production themes, OLED surfaces and light-mode fallbacks all sit above
  /// this. Pinned to the WCAG 2.x AA normal-text bar (4.5:1).
  static const double normalTextMinRatio = 4.5;

  /// WCAG AA minimum contrast ratio for large text (>=24px/>=18.66px bold)
  /// and graphical objects (controls, icons, progress fill).
  ///
  /// Used for accent-bound foregrounds where pure-black/white is still a
  /// deliberate design choice; 3:1 is the AA graphical-object bar.
  static const double largeTextAndUiMinRatio = 3.0;

  /// WCAG relative luminance of an opaque color, `0.0` (black) to `1.0` (white).
  static double relativeLuminance(Color color) {
    double channel(double v) {
      return v <= 0.03928
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  /// WCAG contrast ratio between two opaque colors, `1.0` .. `21.0`.
  ///
  /// `ratio(a, b) == ratio(b, a)`.
  static double contrastRatio(Color a, Color b) {
    final la = relativeLuminance(a);
    final lb = relativeLuminance(b);
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Picks black or white as the foreground that gives [background] the best
  /// WCAG contrast. Always deterministic; never guesses.
  static Color foregroundFor(Color background, {bool preferWhite = false}) {
    final onWhite = contrastRatio(background, const Color(0xFFFFFFFF));
    final onBlack = contrastRatio(background, const Color(0xFF000000));
    if (preferWhite) {
      return onWhite >= onBlack
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF000000);
    }
    return onBlack > onWhite
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);
  }

  /// Resolves a readable foreground for [background] with two, increasingly
  /// relaxed WCAG goals:
  ///
  /// 1. Black/white candidate that already beats [preferredRatio] (e.g.
  ///    [normalTextMinRatio]); when present the caller benefits without any
  ///    rescue.
  /// 2. Otherwise a rescue that still guarantees at least [minRatio] (e.g.
  ///    [largeTextAndUiMinRatio]) toward black/white — the most contrast
  ///    available from a single hue family.
  ///
  /// The two-tier design lets callers ask for normal-text contrast "where
  /// practical" and only relax to the graphical-object bar when the color cast
  /// physically cannot reach the tighter target, instead of silently picking a
  /// mid-luminance compromise that fails both goals.
  static Color readableForeground(
    Color background, {
    required double minRatio,
    double? preferredRatio,
  }) {
    assert(minRatio > 1.0);
    assert(preferredRatio == null || preferredRatio >= minRatio);
    final best = foregroundFor(background);
    final target = preferredRatio ?? minRatio;
    if (contrastRatio(best, background) >= target) {
      return best;
    }
    final rescued = ensureContrast(best, background, minRatio: target);
    if (contrastRatio(rescued, background) >= minRatio) {
      return rescued;
    }
    return ensureContrast(best, background, minRatio: minRatio);
  }

  /// Returns [foreground] when it already meets [minRatio] against
  /// [background]; otherwise shifts [foreground] toward black or white
  /// (whichever increases contrast) until the ratio holds.
  ///
  /// Used to rescue a dynamically derived color that would otherwise render
  /// unreadable text, icons or progress controls.
  static Color ensureContrast(
    Color foreground,
    Color background, {
    double minRatio = 3.0,
  }) {
    if (contrastRatio(foreground, background) >= minRatio) {
      return foreground;
    }
    final lighten =
        relativeLuminance(foreground) > relativeLuminance(background);
    var candidate = foreground;
    for (var i = 0; i < 64; i++) {
      candidate = lighten
          ? _towardWhite(candidate, 0.06)
          : Color.lerp(candidate, const Color(0xFF000000), 0.06)!;
      if (contrastRatio(candidate, background) >= minRatio) {
        return candidate;
      }
    }
    return lighten ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
  }

  /// Hue in degrees `0..360`; `0` for the neutral colors that have no hue.
  static double hue(Color color) {
    final r = color.r;
    final g = color.g;
    final b = color.b;
    final maxC = math.max(r, math.max(g, b));
    final minC = math.min(r, math.min(g, b));
    final delta = maxC - minC;
    if (delta == 0) return 0;
    double h;
    if (maxC == r) {
      h = 60 * (((g - b) / delta) % 6);
    } else if (maxC == g) {
      h = 60 * ((b - r) / delta + 2);
    } else {
      h = 60 * ((r - g) / delta + 4);
    }
    return h < 0 ? h + 360 : h;
  }

  /// Saturation in `0..1` using the HSL model.
  static double saturation(Color color) {
    final r = color.r;
    final g = color.g;
    final b = color.b;
    final maxC = math.max(r, math.max(g, b));
    final minC = math.min(r, math.min(g, b));
    final delta = maxC - minC;
    final sum = maxC + minC;
    if (delta == 0) return 0;
    final l = sum / 2;
    return l <= 0.5 ? delta / sum : delta / (2 - sum);
  }

  /// Lightness in `0..1` using the HSL model.
  static double lightness(Color color) {
    final maxC = math.max(color.r, math.max(color.g, color.b));
    final minC = math.min(color.r, math.min(color.g, color.b));
    return (maxC + minC) / 2;
  }

  /// Builds a color from HSL components.
  static Color fromHsl(double h, double s, double l) {
    final c = (1 - (2 * l - 1).abs()) * s;
    final x = c * (1 - ((h / 60) % 2 - 1).abs());
    final m = l - c / 2;
    double r = 0;
    double g = 0;
    double b = 0;
    if (h < 60) {
      r = c;
      g = x;
    } else if (h < 120) {
      r = x;
      g = c;
    } else if (h < 180) {
      g = c;
      b = x;
    } else if (h < 240) {
      g = x;
      b = c;
    } else if (h < 300) {
      r = x;
      b = c;
    } else {
      r = c;
      b = x;
    }
    return Color.fromARGB(
      255,
      _f((r + m) * 255),
      _f((g + m) * 255),
      _f((b + m) * 255),
    );
  }

  /// Lightens [color] by [amount] in HSL lightness space (`0..1`).
  static Color lighten(Color color, double amount) {
    final clamped = amount.clamp(0.0, 1.0);
    final l = lightness(color);
    return fromHsl(hue(color), saturation(color), l + (1 - l) * clamped);
  }

  /// Darkens [color] by [amount] in HSL lightness space (`0..1`).
  static Color darken(Color color, double amount) {
    final clamped = amount.clamp(0.0, 1.0);
    return fromHsl(
      hue(color),
      saturation(color),
      lightness(color) * (1 - clamped),
    );
  }

  /// Reduces saturation by [factor] (0 = fully gray, 1 = unchanged).
  static Color desaturate(Color color, double factor) {
    final clamped = factor.clamp(0.0, 1.0);
    return fromHsl(hue(color), saturation(color) * clamped, lightness(color));
  }

  /// Forces a color's lightness to [target] (`0..1`), preserving hue and
  /// saturation.
  static Color withLightness(Color color, double target) {
    return fromHsl(hue(color), saturation(color), target.clamp(0.0, 1.0));
  }

  /// Forces a color's lightness into `[min, max]` and its saturation into
  /// `[minSat, maxSat]`. Saturation is only ever raised when the color already
  /// carries real chroma ([minSat] is ignored when the color is effectively
  /// neutral), so a gray artwork can never be given an arbitrary neon hue.
  static Color clampTone(
    Color color, {
    double minLightness = 0.0,
    double maxLightness = 1.0,
    double minSaturation = 0.0,
    double maxSaturation = 1.0,
  }) {
    final l = lightness(color).clamp(minLightness, maxLightness);
    var s = saturation(color).clamp(0.0, maxSaturation);
    if (s < minSaturation && s > 0.06) {
      s = minSaturation;
    }
    return fromHsl(hue(color), s, l);
  }

  /// Moves [color] toward [target] in [steps] steps along sRGB (like
  /// `Color.lerp`). Useful for deterministic surface/variant relationships.
  static Color blend(Color color, Color target, double amount) {
    return Color.lerp(color, target, amount.clamp(0.0, 1.0))!;
  }

  static Color _towardWhite(Color color, double amount) {
    return Color.lerp(color, const Color(0xFFFFFFFF), amount.clamp(0.0, 1.0))!;
  }
}

int _f(double v) => v.round().clamp(0, 255);

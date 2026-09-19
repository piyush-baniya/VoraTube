import 'package:flutter/material.dart';

import '../../core/artwork_palette/artwork_contrast.dart';
import '../../core/artwork_palette/artwork_palette.dart';
import 'app_colors.dart';
import 'app_theme.dart';

/// Artwork-driven "Chameleon" theme resolution.
///
/// Reuses the existing artwork palette engine (an extracted [ArtworkPalette]
/// from the currently playing song) to derive a full, contrast-safe
/// [ThemeData] for the whole app:
///
/// * brightness is chosen from the artwork's surface luminance (never the
///   system theme),
/// * surfaces, elevation steps, outlines, accents and every foreground are
///   re-derived from the artwork with WCAG guarantees (>= 4.5:1 normal text,
///   >= 3:1 large text / UI graphics),
/// * edge-cases are normalized (near-black/white, grayscale, low/extreme
///   saturation, neon, pastel, one dominant color), and
/// * the result is memoized per palette so one artwork identity produces one
///   ThemeData and nothing re-extracts inside `build()`.
///
/// No artwork, missing/corrupt artwork, or a transient extraction produces a
/// deterministic neutral VoraTube fallback (the default Purple identity)
/// regardless of the manually selected preset.
abstract final class ChameleonTheme {
  ChameleonTheme._();

  /// Smooth whole-app color crossfade for Chameleon transitions (600–900 ms
  /// band; 700 ms sits comfortably inside it).
  static const Duration transitionDuration = Duration(milliseconds: 700);

  /// Memoized resolved themes, keyed by the source palette (value equality).
  /// Bounded so long sessions with many distinct artworks stay tiny.
  static final Map<ArtworkPalette, ThemeData> _cache = {};

  /// Resolves (and memoizes) the full Chameleon [ThemeData] for an extracted
  /// artwork palette.
  static ThemeData build(ArtworkPalette palette) {
    if (_cache.length > 64) {
      _cache.clear();
    }
    return _cache.putIfAbsent(palette, () {
      final resolved = _resolve(palette);
      return AppTheme.buildThemeData(
        resolved.scheme,
        resolved.ramp,
        isDark: resolved.isDark,
        palette: resolved.identity,
      );
    });
  }

  /// Deterministic neutral VoraTube fallback for Chameleon when there is no
  /// playable artwork right now. Independent of the manual color preset.
  static ThemeData neutralFallback({required bool isDark}) => isDark
      ? AppTheme.dark(AppThemePreset.purple)
      : AppTheme.light(AppThemePreset.purple);

  static _Resolution _resolve(ArtworkPalette p) {
    final isDark = ArtworkContrast.relativeLuminance(p.surface) < 0.5;

    final surface = _normalizeSurface(p.surface, isDark);
    final ramp = _buildRamp(p, surface, isDark);
    final accent = isDark
        ? _accentForDark(p.accent)
        : _accentForLight(p.accent);
    final secondary = isDark
        ? _accentForDark(p.secondaryAccent)
        : _accentForLight(p.secondaryAccent);
    final scheme = _buildScheme(p, surface, ramp, accent, secondary, isDark);
    final identity = AppPalette(
      // Tag only: nothing reads the extension palette's preset enum. The
      // color fields carry the artwork identity used by `context.palette` and
      // gradient consumers.
      preset: AppThemePreset.purple,
      primary: accent,
      highlight: secondary,
      lightDeep: accent,
      accentGradient: [p.vibrant, p.secondaryAccent],
      glowColor: accent,
      glassTint: accent,
    );
    return _Resolution(
      isDark: isDark,
      scheme: scheme,
      ramp: ramp,
      identity: identity,
    );
  }

  static ColorScheme _buildScheme(
    ArtworkPalette p,
    Color surface,
    AppSurfaceRamp r,
    Color accent,
    Color secondary,
    bool isDark,
  ) {
    final onSurface = r.textPrimary;
    final onPrimary = ArtworkContrast.readableForeground(
      accent,
      minRatio: ArtworkContrast.normalTextMinRatio,
      preferredRatio: ArtworkContrast.normalTextMinRatio,
    );
    final onSecondary = ArtworkContrast.readableForeground(
      secondary,
      minRatio: ArtworkContrast.normalTextMinRatio,
      preferredRatio: ArtworkContrast.normalTextMinRatio,
    );
    final primaryContainer = ArtworkContrast.blend(accent, surface, 0.82);
    final secondaryContainer = ArtworkContrast.blend(secondary, surface, 0.85);
    final onPrimaryContainer = ArtworkContrast.readableForeground(
      primaryContainer,
      minRatio: ArtworkContrast.normalTextMinRatio,
    );
    final onSecondaryContainer = ArtworkContrast.readableForeground(
      secondaryContainer,
      minRatio: ArtworkContrast.normalTextMinRatio,
    );
    // Semantic status colors are deliberately not recolored from the artwork.
    final onError = ArtworkContrast.foregroundFor(AppColors.error);
    final onTertiary = ArtworkContrast.foregroundFor(AppColors.success);

    return (isDark ? ColorScheme.dark : ColorScheme.light)(
      primary: accent,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: onSecondaryContainer,
      tertiary: AppColors.success,
      onTertiary: onTertiary,
      tertiaryContainer: r.cardElevated,
      onTertiaryContainer: onSurface,
      error: AppColors.error,
      onError: onError,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerLowest: isDark ? surface : r.surfaceLow,
      surfaceContainerLow: isDark ? r.surfaceLow : surface,
      surfaceContainer: r.surfaceContainer,
      surfaceContainerHigh: r.surfaceContainerHigh,
      surfaceContainerHighest: r.surfaceContainerHighest,
      onSurfaceVariant: r.textSecondary,
      outline: r.outline,
      outlineVariant: r.outlineVariant,
      scrim: r.overlay,
      shadow: Colors.black,
      inverseSurface: r.inverseSurface,
      onInverseSurface: r.inverseOnSurface,
      inversePrimary: isDark ? secondary : accent,
    );
  }

  // ── Surfaces ─────────────────────────────────────────────────────────

  /// Normalizes the artwork surface so extreme artwork (near-black, near-white,
  /// pastel, neon) still yields a believable app canvas instead of a blank or
  /// unreadable background. Direction depends on the theme brightness so the
  /// canvas always stays compatible with its own foreground.
  static Color _normalizeSurface(Color c, bool isDark) {
    return ArtworkContrast.clampTone(
      c,
      minLightness: isDark ? 0.10 : 0.52,
      maxLightness: isDark ? 0.44 : 0.86,
      maxSaturation: 0.5,
    );
  }

  static Color _tone(Color c, double dl, double satMul) {
    return ArtworkContrast.fromHsl(
      ArtworkContrast.hue(c),
      (ArtworkContrast.saturation(c) * satMul).clamp(0.0, 1.0),
      (ArtworkContrast.lightness(c) + dl).clamp(0.0, 1.0),
    );
  }

  static AppSurfaceRamp _buildRamp(
    ArtworkPalette p,
    Color surface,
    bool isDark,
  ) {
    final low = _tone(surface, isDark ? 0.03 : 0.28, 0.9);
    final container = _tone(surface, isDark ? 0.07 : 0.03, 0.85);
    final high = _tone(surface, isDark ? 0.13 : -0.07, 0.8);
    final highest = _tone(surface, isDark ? 0.20 : -0.14, 0.75);

    // The on-surface text is resolved for 4.5:1 regardless of the direction
    // guessed above; ramps for luminous artwork (e.g. amber covers) still get a
    // readable foreground instead of an unreadable white-on-light canvas.
    final onSurface = ArtworkContrast.readableForeground(
      surface,
      minRatio: ArtworkContrast.normalTextMinRatio,
      preferredRatio: ArtworkContrast.normalTextMinRatio,
    );
    final textSecondary = _contrastForeground(onSurface, surface, 0.62, 4.5);
    final textTertiary = _contrastForeground(onSurface, surface, 0.42, 4.5);
    final outline = _contrastForeground(onSurface, surface, 0.55, 3.0);
    final outlineVariant = _contrastForeground(onSurface, surface, 0.35, 3.0);

    final inverseSurface = isDark
        ? _tone(surface, 0.62, 0.35)
        : _tone(surface, -0.62, 0.35);
    final inverseOnSurface = ArtworkContrast.readableForeground(
      inverseSurface,
      minRatio: ArtworkContrast.normalTextMinRatio,
    );

    return AppSurfaceRamp(
      surface: surface,
      surfaceLow: low,
      surfaceContainer: container,
      surfaceContainerHigh: high,
      surfaceContainerHighest: highest,
      outline: outline,
      outlineVariant: outlineVariant,
      divider: ArtworkContrast.blend(onSurface, surface, 0.16),
      textPrimary: onSurface,
      textSecondary: textSecondary,
      textTertiary: textTertiary,
      inverseSurface: inverseSurface,
      inverseOnSurface: inverseOnSurface,
      card: _tone(surface, isDark ? 0.02 : -0.01, 0.9),
      cardElevated: _tone(surface, isDark ? 0.07 : -0.04, 0.85),
      cardPress: _tone(surface, isDark ? 0.12 : -0.07, 0.85),
      overlay: isDark
          ? Color.alphaBlend(const Color(0xCC000000), surface)
          : Color.alphaBlend(const Color(0xCCFFFFFF), surface),
    );
  }

  /// Blends a muted foreground toward the surface and rescues it back above
  /// [ratio] against the surface, so secondary/tertiary text tiers always stay
  /// readable.
  static Color _contrastForeground(
    Color fg,
    Color surface,
    double t,
    double ratio,
  ) {
    return ArtworkContrast.ensureContrast(
      ArtworkContrast.blend(fg, surface, t),
      surface,
      minRatio: ratio,
    );
  }

  // ── Accents ──────────────────────────────────────────────────────────

  /// Dark canvases can carry vivid, mid-light accents.
  static Color _accentForDark(Color c) {
    final s = ArtworkContrast.saturation(c);
    return ArtworkContrast.clampTone(
      c,
      minLightness: 0.35,
      maxLightness: 0.75,
      minSaturation: s > 0.06 ? 0.3 : 0.0,
      maxSaturation: 0.95,
    );
  }

  /// Light canvases need a deep accent so foreground text stays 4.5:1 on it.
  static Color _accentForLight(Color c) {
    final s = ArtworkContrast.saturation(c);
    return ArtworkContrast.clampTone(
      c,
      minLightness: 0.20,
      maxLightness: 0.45,
      minSaturation: s > 0.06 ? 0.3 : 0.0,
      maxSaturation: 0.9,
    );
  }
}

class _Resolution {
  const _Resolution({
    required this.isDark,
    required this.scheme,
    required this.ramp,
    required this.identity,
  });

  final bool isDark;
  final ColorScheme scheme;
  final AppSurfaceRamp ramp;
  final AppPalette identity;
}

import 'package:flutter/material.dart' show Color;

import '../../app/theme/app_theme.dart';
import 'artwork_contrast.dart';
import 'artwork_palette.dart';

/// Bridges the artwork palette engine to the 9 VoraTube themes.
///
/// Concept:
///
///     Base Theme + Optional Dynamic Artwork Palette = Effective player styling
///
/// The selected VoraTube theme stays the base/fallback. It derives a complete
/// [ArtworkPalette] whenever no usable artwork palette exists, and OLED gets
/// its own rules so dynamic colors never trample its true-black canvas.
abstract final class ArtworkPaletteTheme {
  /// Resolves the effective palette for the active theme.
  ///
  /// * No extracted palette → theme-derived fallback.
  /// * OLED + extracted palette → artwork accents over true-black surfaces.
  /// * Otherwise the extracted palette is used as-is (theme-independent).
  static ArtworkPalette resolveForTheme(
    ArtworkPalette? extracted, {
    required AppPalette palette,
    required bool isDark,
    required bool oled,
  }) {
    if (extracted == null) {
      return buildThemeFallback(palette, isDark: isDark);
    }
    if (oled) {
      return extracted.withTrueBlackSurfaces();
    }
    return extracted;
  }

  /// Builds a complete, deterministic [ArtworkPalette] straight from a theme,
  /// so a fallback never leaves the UI in a loading or invalid state.
  static ArtworkPalette buildThemeFallback(
    AppPalette palette, {
    required bool isDark,
  }) {
    final ramp = isDark ? palette.darkRamp : palette.lightRamp;
    final oled = palette.preset == AppThemePreset.oled;
    final accent = isDark ? palette.primary : palette.lightDeep;
    final highlight = palette.highlight;

    final surface = ramp.surface;
    final surfaceVariant = oled ? ramp.surfaceLow : ramp.surfaceContainer;

    const white = Color(0xFFFFFFFF);
    final onAccent =
        ArtworkContrast.contrastRatio(white, accent) >=
                ArtworkContrast.normalTextMinRatio
            ? white
            : ArtworkContrast.readableForeground(
                accent,
                minRatio: ArtworkContrast.largeTextAndUiMinRatio,
                preferredRatio: ArtworkContrast.normalTextMinRatio,
              );
    final onSurface = ramp.textPrimary;

    return ArtworkPalette(
      dominant: accent,
      vibrant: highlight,
      muted: isDark
          ? ArtworkContrast.desaturate(palette.primary, 0.55)
          : ArtworkContrast.desaturate(palette.lightDeep, 0.45),
      dark: ArtworkContrast.darken(accent, 0.55),
      darkMuted: ArtworkContrast.desaturate(
        ArtworkContrast.darken(accent, 0.60),
        0.4,
      ),
      light: ArtworkContrast.lighten(highlight, 0.35),
      lightVibrant: highlight,
      surface: surface,
      surfaceVariant: surfaceVariant,
      accent: accent,
      secondaryAccent: highlight,
      onSurface: onSurface,
      onAccent: onAccent,
      backgroundStart: surface,
      backgroundEnd: ArtworkContrast.blend(
        surface,
        accent,
        isDark ? 0.16 : 0.10,
      ),
      sourceArtworkKey: null,
      extractionVersion: paletteAlgorithmVersion,
      wasFallback: true,
    );
  }
}

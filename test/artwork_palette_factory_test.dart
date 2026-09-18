import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/app/theme/app_theme.dart';
import 'package:vora_tube/core/artwork_palette/artwork_contrast.dart';
import 'package:vora_tube/core/artwork_palette/artwork_palette.dart';
import 'package:vora_tube/core/artwork_palette/artwork_palette_factory.dart';

ArtworkPalette extractedSample() {
  return const ArtworkPalette(
    dominant: Color(0xFF336699),
    vibrant: Color(0xFF00B4B4),
    muted: Color(0xFF778899),
    dark: Color(0xFF111A2B),
    darkMuted: Color(0xFF151D2E),
    light: Color(0xFFDDEEFF),
    lightVibrant: Color(0xFF88DDDD),
    surface: Color(0xFF5A6B7A),
    surfaceVariant: Color(0xFF6B7C8B),
    accent: Color(0xFF00A0B0),
    secondaryAccent: Color(0xFF40DDD0),
    onSurface: Color(0xFFFFFFFF),
    onAccent: Color(0xFF000000),
    backgroundStart: Color(0xFF5A6B7A),
    backgroundEnd: Color(0xFF6B7C8B),
    sourceArtworkKey: 'art-1',
    extractionVersion: paletteAlgorithmVersion,
    wasFallback: false,
  );
}

void main() {
  group('theme fallbacks', () {
    for (final preset in AppThemePreset.values) {
      for (final isDark in [true, false]) {
        final label = '${preset.name} ${isDark ? 'dark' : 'light'}';
        test('$label produces a complete, deterministic fallback', () {
          final palette = AppPalette.of(preset);
          final fb1 = ArtworkPaletteTheme.buildThemeFallback(
            palette,
            isDark: isDark,
          );
          final fb2 = ArtworkPaletteTheme.buildThemeFallback(
            palette,
            isDark: isDark,
          );
          expect(fb1, fb2);
          expect(fb1.wasFallback, isTrue);
          expect(fb1.colorSlots.length, 15);
          expect(fb1.sourceArtworkKey, isNull);
          // Accent foreground holds at least 3:1, by construction.
          expect(
            ArtworkContrast.contrastRatio(fb1.onAccent, fb1.accent),
            greaterThanOrEqualTo(3.0),
          );
        });
      }
    }

    test('fallback accent follows the theme identity', () {
      final darkPurple = ArtworkPaletteTheme.buildThemeFallback(
        AppPalette.of(AppThemePreset.purple),
        isDark: true,
      );
      expect(darkPurple.accent, AppPalette.purple.primary);
      final lightPurple = ArtworkPaletteTheme.buildThemeFallback(
        AppPalette.of(AppThemePreset.purple),
        isDark: false,
      );
      expect(lightPurple.accent, AppPalette.purple.lightDeep);
    });

    test('OLED fallback surfaces are true black', () {
      final fb = ArtworkPaletteTheme.buildThemeFallback(
        AppPalette.of(AppThemePreset.oled),
        isDark: true,
      );
      expect(fb.surface, const Color(0xFF000000));
      expect(fb.backgroundStart, const Color(0xFF000000));
    });
  });

  group('resolveForTheme', () {
    test('extracted palettes pass through unchanged for normal themes', () {
      final extracted = extractedSample();
      final effective = ArtworkPaletteTheme.resolveForTheme(
        extracted,
        palette: AppPalette.of(AppThemePreset.purple),
        isDark: true,
        oled: false,
      );
      expect(effective, extracted);
    });

    test('OLED overrides surfaces but keeps artwork accents', () {
      final extracted = extractedSample();
      final effective = ArtworkPaletteTheme.resolveForTheme(
        extracted,
        palette: AppPalette.of(AppThemePreset.oled),
        isDark: true,
        oled: true,
      );
      expect(effective.surface, const Color(0xFF000000));
      expect(effective.accent, extracted.accent);
      expect(effective.secondaryAccent, extracted.secondaryAccent);
    });

    test('no extraction yields a theme fallback', () {
      final effective = ArtworkPaletteTheme.resolveForTheme(
        null,
        palette: AppPalette.of(AppThemePreset.rose),
        isDark: false,
        oled: false,
      );
      expect(effective.wasFallback, isTrue);
      expect(effective.surface, AppPalette.rose.lightRamp.surface);
    });
  });
}

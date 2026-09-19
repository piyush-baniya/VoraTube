import 'package:flutter/material.dart' show Color, Brightness, ThemeData;
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/app/theme/app_theme.dart';
import 'package:vora_tube/app/theme/chameleon_theme.dart';
import 'package:vora_tube/core/artwork_palette/artwork_contrast.dart';
import 'package:vora_tube/core/artwork_palette/artwork_palette.dart';

/// Builds a complete [ArtworkPalette] around the two slots the Chameleon
/// resolver actually reads (surface + accent family).
ArtworkPalette _ap(
  Color surface,
  Color accent, {
  Color secondaryAccent = const Color(0xFF6B7280),
}) {
  return ArtworkPalette(
    dominant: surface,
    vibrant: accent,
    muted: surface,
    dark: surface,
    darkMuted: surface,
    light: surface,
    lightVibrant: surface,
    surface: surface,
    surfaceVariant: surface,
    accent: accent,
    secondaryAccent: secondaryAccent,
    onSurface: const Color(0xFF000000),
    onAccent: const Color(0xFFFFFFFF),
    backgroundStart: surface,
    backgroundEnd: surface,
    sourceArtworkKey: 'unit-test-art',
  );
}

/// Asserts the full contrast contract for one artwork-resolved theme.
void _expectContrast(ThemeData theme) {
  final s = theme.colorScheme;
  double ratio(Color a, Color b) => ArtworkContrast.contrastRatio(a, b);
  expect(
    ratio(s.onSurface, s.surface),
    greaterThanOrEqualTo(4.5),
    reason: 'body text must clear WCAG AA on the artwork surface',
  );
  expect(
    ratio(s.onSurfaceVariant, s.surface),
    greaterThanOrEqualTo(4.5),
    reason: 'secondary text must clear WCAG AA',
  );
  expect(
    ratio(s.onPrimary, s.primary),
    greaterThanOrEqualTo(4.5),
    reason: 'on-primary must clear WCAG AA',
  );
  expect(
    ratio(s.onSecondary, s.secondary),
    greaterThanOrEqualTo(4.5),
    reason: 'on-secondary must clear WCAG AA',
  );
  expect(
    ratio(s.onPrimaryContainer, s.primaryContainer),
    greaterThanOrEqualTo(4.5),
    reason: 'on-primary-container must clear WCAG AA',
  );
  expect(
    ratio(s.outline, s.surface),
    greaterThanOrEqualTo(3.0),
    reason: 'outlines/UI graphics must clear the WCAG 3:1 graphical bar',
  );
  expect(ratio(s.outlineVariant, s.surface), greaterThanOrEqualTo(3.0));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChameleonTheme transition config', () {
    test('transitionDuration sits inside the 600–900 ms band', () {
      final ms = ChameleonTheme.transitionDuration.inMilliseconds;
      expect(ms, greaterThanOrEqualTo(600));
      expect(ms, lessThanOrEqualTo(900));
    });
  });

  group('ChameleonTheme brightness + surfaces', () {
    test(
      'brightness is derived from the artwork surface, never the system',
      () {
        // near-black artwork → dark theme.
        expect(
          ChameleonTheme.build(
            _ap(const Color(0xFF050508), const Color(0xFF3B82F6)),
          ).brightness,
          Brightness.dark,
        );
        // near-white artwork → light theme.
        expect(
          ChameleonTheme.build(
            _ap(const Color(0xFFF7F4EF), const Color(0xFF5B21B6)),
          ).brightness,
          Brightness.light,
        );
      },
    );

    test(
      'near-black surfaces are clamped to a believable canvas (0.10..0.44)',
      () {
        final theme = ChameleonTheme.build(
          _ap(const Color(0xFF050508), const Color(0xFF7C3AED)),
        );
        expect(theme.brightness, Brightness.dark);
        final l = ArtworkContrast.lightness(theme.colorScheme.surface);
        expect(l, inInclusiveRange(0.10, 0.44));
        expect(theme.colorScheme.surface, isNot(const Color(0xFF000000)));
      },
    );

    test(
      'near-white surfaces are clamped to a believable canvas (0.52..0.86)',
      () {
        final theme = ChameleonTheme.build(
          _ap(const Color(0xFFFDFDFB), const Color(0xFFBE185D)),
        );
        expect(theme.brightness, Brightness.light);
        final l = ArtworkContrast.lightness(theme.colorScheme.surface);
        expect(l, inInclusiveRange(0.52, 0.86));
        expect(theme.colorScheme.surface, isNot(const Color(0xFFFFFFFF)));
      },
    );

    test('grayscale artwork never gains a neon accent hue', () {
      final theme = ChameleonTheme.build(
        _ap(
          const Color(0xFF2A2A2A),
          const Color(0xFF9A9A9A),
          secondaryAccent: const Color(0xFF808080),
        ),
      );
      expect(theme.brightness, Brightness.dark);
      expect(
        ArtworkContrast.saturation(theme.colorScheme.primary),
        0,
        reason: 'a neutral extraction must stay neutral',
      );
      expect(ArtworkContrast.saturation(theme.colorScheme.secondary), 0);
    });
  });

  group('ChameleonTheme contrast table', () {
    // surface, accent, secondaryAccent, label
    const cases = <(Color, Color, Color, String)>[
      (Color(0xFF16213E), Color(0xFF3B82F6), Color(0xFF93C5FD), 'dark navy'),
      (Color(0xFF1F2937), Color(0xFFF59E0B), Color(0xFFFCD34D), 'dark warm'),
      (
        Color(0xFF7F1D1D),
        Color(0xFFDC2626),
        Color(0xFFFCA5A5),
        'saturated red',
      ),
      (Color(0xFF042F12), Color(0xFF00FF41), Color(0xFF4ADE80), 'neon green'),
      (
        Color(0xFFF5EFE6),
        Color(0xFF8B5CF6),
        Color(0xFFC4B5FD),
        'light parchment',
      ),
      (Color(0xFFE8F1FB), Color(0xFF1D4ED8), Color(0xFF93C5FD), 'light sky'),
      (Color(0xFFEAD6C0), Color(0xFFE0B89A), Color(0xFFF0CFB3), 'pastel'),
    ];

    for (final (surface, accent, secondary, label) in cases) {
      test('$label artwork resolves to a contrast-safe theme', () {
        final theme = ChameleonTheme.build(
          _ap(surface, accent, secondaryAccent: secondary),
        );
        _expectContrast(theme);
      });
    }

    test('dark artwork gets a dark theme, light artwork a light theme', () {
      expect(
        ChameleonTheme.build(
          _ap(const Color(0xFF16213E), const Color(0xFF3B82F6)),
        ).brightness,
        Brightness.dark,
      );
      expect(
        ChameleonTheme.build(
          _ap(const Color(0xFFF5EFE6), const Color(0xFF8B5CF6)),
        ).brightness,
        Brightness.light,
      );
    });
  });

  group('ChameleonTheme neutral fallback', () {
    test('is the deterministic purple identity, independent of any preset', () {
      final light = ChameleonTheme.neutralFallback(isDark: false);
      final dark = ChameleonTheme.neutralFallback(isDark: true);

      expect(light.colorScheme.surface, AppPalette.purple.lightRamp.surface);
      expect(light.colorScheme.primary, AppPalette.purple.lightDeep);
      expect(dark.colorScheme.surface, AppPalette.purple.darkRamp.surface);
      expect(dark.colorScheme.primary, AppPalette.purple.primary);

      // Not derived from another preset's identity.
      expect(dark.colorScheme.surface, isNot(AppPalette.oled.darkRamp.surface));
      expect(
        dark.colorScheme.surface,
        isNot(AppPalette.sepia.darkRamp.surface),
      );

      // Deterministic across calls.
      expect(ChameleonTheme.neutralFallback(isDark: true), same(dark));
      expect(ChameleonTheme.neutralFallback(isDark: false), same(light));
    });
  });

  group('ChameleonTheme memoization', () {
    test('reuses one ThemeData per palette identity', () {
      final p = _ap(const Color(0xFF16213E), const Color(0xFF3B82F6));
      expect(ChameleonTheme.build(p), same(ChameleonTheme.build(p)));
    });

    test('different palettes resolve to different themes', () {
      final a = _ap(const Color(0xFF16213E), const Color(0xFF3B82F6));
      final b = _ap(const Color(0xFF16213E), const Color(0xFF10B981));
      expect(ChameleonTheme.build(a), isNot(same(ChameleonTheme.build(b))));
    });

    test('cache stays bounded: evicted identities rebuild', () {
      final first = _ap(const Color(0xFF101010), const Color(0xFF111111));
      final originalFirst = ChameleonTheme.build(first);
      // 70 distinct palettes push the 64-entry cache over its limit.
      for (var i = 0; i < 70; i++) {
        ChameleonTheme.build(
          _ap(
            const Color.fromARGB(255, 0x10, 0x20, 0x30),
            Color.fromARGB(255, i.clamp(0, 255), 0x40, 0x50),
          ),
        );
      }
      expect(
        ChameleonTheme.build(first),
        isNot(same(originalFirst)),
        reason: 'the oldest entry was evicted and must be rebuilt fresh',
      );
    });

    test('cached artwork switching cost stays O(1) for a replay', () {
      final a = _ap(const Color(0xFF16213E), const Color(0xFF3B82F6));
      final b = _ap(const Color(0xFFF5EFE6), const Color(0xFF8B5CF6));
      final firstA = ChameleonTheme.build(a);
      ChameleonTheme.build(b);
      expect(ChameleonTheme.build(a), same(firstA));
    });
  });

  group('ChameleonTheme extension identity', () {
    test('VoraTheme carries the artwork accent, not the purple preset', () {
      final p = _ap(const Color(0xFF16213E), const Color(0xFF3B82F6));
      final theme = ChameleonTheme.build(p);
      final identity = theme.extension<VoraTheme>()!.palette;

      expect(
        identity.preset,
        AppThemePreset.purple,
        reason: 'the tag is only bookkeeping; colors carry the identity',
      );
      expect(identity.primary, theme.colorScheme.primary);
      expect(
        identity.highlight,
        theme.colorScheme.secondary,
        reason: 'MiniPlayer reads context.palette.highlight',
      );
      expect(identity.primary, isNot(AppPalette.purple.primary));
      expect(identity.accentGradient, [p.vibrant, p.secondaryAccent]);
    });

    test('the app chrome is wired through the shared builder', () {
      final theme = ChameleonTheme.build(
        _ap(const Color(0xFF16213E), const Color(0xFF3B82F6)),
      );
      expect(theme.useMaterial3, isTrue);
      expect(theme.scaffoldBackgroundColor, theme.colorScheme.surface);
      expect(theme.extension<VoraTheme>(), isNotNull);
    });
  });

  group('theme lerp math', () {
    test('AppPalette.lerp crossfades colors and snaps the preset tag', () {
      final a = AppPalette.purple;
      final b = AppPalette.oled;
      final mid = a.lerp(b, 0.5);
      expect(mid.preset, AppThemePreset.oled);
      expect(mid.primary, Color.lerp(a.primary, b.primary, 0.5));
      expect(a.lerp(b, 0).primary, a.primary);
      expect(a.lerp(b, 1).primary, b.primary);
    });

    test('AppSurfaceRamp.lerp crossfades every ramp color', () {
      final dark = AppPalette.purple.darkRamp;
      final light = AppPalette.purple.lightRamp;
      final mid = dark.lerp(light, 0.5);
      expect(mid.surface, Color.lerp(dark.surface, light.surface, 0.5));
      expect(
        mid.textSecondary,
        Color.lerp(dark.textSecondary, light.textSecondary, 0.5),
      );
      expect(
        dark.lerp(light, 0.4).surface,
        Color.lerp(dark.surface, light.surface, 0.4),
      );
    });

    test('VoraTheme.lerp drives smooth Chameleon crossfades', () {
      final vt1 = VoraTheme(
        palette: AppPalette.purple,
        surfaces: AppPalette.purple.darkRamp,
        isDark: true,
      );
      final vt2 = VoraTheme(
        palette: AppPalette.sepia,
        surfaces: AppPalette.sepia.lightRamp,
        isDark: false,
      );
      final mid = vt1.lerp(vt2, 0.5);
      expect(mid.isDark, isFalse, reason: 'brightness snaps past the midpoint');
      expect(mid.palette.preset, AppThemePreset.sepia);
      expect(
        mid.palette.primary,
        Color.lerp(AppPalette.purple.primary, AppPalette.sepia.primary, 0.5),
      );
      expect(
        mid.surfaces.surface,
        Color.lerp(
          AppPalette.purple.darkRamp.surface,
          AppPalette.sepia.lightRamp.surface,
          0.5,
        ),
      );
      // The near side keeps the source identity (no half-flash of the tag).
      expect(vt1.lerp(vt2, 0.25).isDark, isTrue);
      expect(vt1.lerp(vt2, 0.25).palette.preset, AppThemePreset.purple);
    });
  });
}

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The visual identity presets VoraTube exposes in Settings → Appearance.
///
/// Each preset pairs a name/mood with the accent colors and (optionally)
/// surface ramps that define a whole dark/light theme. Widget-specific colors
/// deliberately do NOT live here — that is the job of the theme/_ColorScheme_
/// produced from a palette.
enum AppThemePreset {
  purple('Purple', 'Default'),
  aurora('Aurora', 'Indigo / Sky'),
  ocean('Ocean', 'Blue'),
  ember('Ember', 'Amber / Orange'),
  emerald('Emerald', 'Green / Mint'),
  rose('Rosé', 'Pink'),
  midnight('Midnight', 'Cyan / Navy'),
  oled('OLED', 'Lime / True Black'),
  sepia('Sepia', 'Warm / Parchment');

  const AppThemePreset(this.label, this.mood);

  /// User-facing name shown in the Settings selector.
  final String label;

  /// Short mood description shown beneath the name in the selector.
  final String mood;
}

/// A resolved set of neutral surface/text/outline colors for one brightness.
///
/// Custom palettes (Midnight, OLED, Sepia) provide their own ramp; every
/// other palette falls back to the shared VoraTube neutrals so the whole app
/// keeps one consistent surface language.
@immutable
class AppSurfaceRamp {
  const AppSurfaceRamp({
    required this.surface,
    required this.surfaceLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.outline,
    required this.outlineVariant,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.inverseSurface,
    required this.inverseOnSurface,
    required this.card,
    required this.cardElevated,
    required this.cardPress,
    required this.overlay,
  });

  /// Deepest background (scaffold).
  final Color surface;

  /// Second-from-deep surface (cards, sheets).
  final Color surfaceLow;

  /// Generic container surface.
  final Color surfaceContainer;

  /// Raised surface (elevated cards, dialogs).
  final Color surfaceContainerHigh;

  /// Highest surface (tooltips, progress tracks).
  final Color surfaceContainerHighest;

  /// Strong borders / disabled outlines.
  final Color outline;

  /// Hairline/subtle borders.
  final Color outlineVariant;

  /// Hairline dividers.
  final Color divider;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color inverseSurface;
  final Color inverseOnSurface;

  /// Card face colors.
  final Color card;
  final Color cardElevated;
  final Color cardPress;

  /// Overlay/scrim.
  final Color overlay;

  /// Interpolates every ramp color toward [other]. Null [other] (or a t at the
  /// endpoints) yields this ramp unchanged, so a no-op band switch stays
  /// stable. Used by [VoraTheme.lerp] so Chameleon theme transitions animate
  /// the neutral surfaces smoothly instead of snapping.
  AppSurfaceRamp lerp(AppSurfaceRamp? other, double t) {
    if (other == null || t <= 0) return this;
    if (t >= 1) return other;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppSurfaceRamp(
      surface: c(surface, other.surface),
      surfaceLow: c(surfaceLow, other.surfaceLow),
      surfaceContainer: c(surfaceContainer, other.surfaceContainer),
      surfaceContainerHigh: c(surfaceContainerHigh, other.surfaceContainerHigh),
      surfaceContainerHighest: c(
        surfaceContainerHighest,
        other.surfaceContainerHighest,
      ),
      outline: c(outline, other.outline),
      outlineVariant: c(outlineVariant, other.outlineVariant),
      divider: c(divider, other.divider),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      inverseSurface: c(inverseSurface, other.inverseSurface),
      inverseOnSurface: c(inverseOnSurface, other.inverseOnSurface),
      card: c(card, other.card),
      cardElevated: c(cardElevated, other.cardElevated),
      cardPress: c(cardPress, other.cardPress),
      overlay: c(overlay, other.overlay),
    );
  }
}

/// The 9 [AppPalette] instances and the shared neutral ramps.
abstract final class AppPalettes {
  AppPalettes._();

  static const AppSurfaceRamp darkNeutral = AppSurfaceRamp(
    surface: AppColors.voidBlack,
    surfaceLow: AppColors.surfaceDark,
    surfaceContainer: AppColors.surfaceDark,
    surfaceContainerHigh: AppColors.surfaceRaisedDark,
    surfaceContainerHighest: AppColors.surfaceHighDark,
    outline: AppColors.outlineDark,
    outlineVariant: AppColors.borderSubtleDark,
    divider: AppColors.dividerDark,
    textPrimary: AppColors.textPrimaryDark,
    textSecondary: AppColors.textSecondaryDark,
    textTertiary: AppColors.textTertiaryDark,
    inverseSurface: AppColors.inverseSurfaceDark,
    inverseOnSurface: AppColors.inverseOnSurfaceDark,
    card: AppColors.cardDark,
    cardElevated: AppColors.cardElevatedDark,
    cardPress: AppColors.cardPressDark,
    overlay: AppColors.overlayDark,
  );

  static const AppSurfaceRamp lightNeutral = AppSurfaceRamp(
    surface: AppColors.paperLight,
    surfaceLow: AppColors.surfaceLight,
    surfaceContainer: AppColors.surfaceLight,
    surfaceContainerHigh: AppColors.surfaceRaisedLight,
    surfaceContainerHighest: AppColors.surfaceHighLight,
    outline: AppColors.outlineLight,
    outlineVariant: AppColors.borderSubtleLight,
    divider: AppColors.dividerLight,
    textPrimary: AppColors.textPrimaryLight,
    textSecondary: AppColors.textSecondaryLight,
    textTertiary: AppColors.textTertiaryLight,
    inverseSurface: AppColors.inverseSurfaceLight,
    inverseOnSurface: AppColors.inverseOnSurfaceLight,
    card: AppColors.cardLight,
    cardElevated: AppColors.cardElevatedLight,
    cardPress: AppColors.cardPressLight,
    overlay: AppColors.overlayLight,
  );

  /// Midnight: cyan accent over a navy-black ramp, muted slate text.
  static const AppSurfaceRamp midnightDark = AppSurfaceRamp(
    surface: Color(0xFF0B1120),
    surfaceLow: Color(0xFF101828),
    surfaceContainer: Color(0xFF141F33),
    surfaceContainerHigh: Color(0xFF1B2A40),
    surfaceContainerHighest: Color(0xFF243347),
    outline: Color(0xFF3A4A66),
    outlineVariant: Color(0xFF27364D),
    divider: Color(0xFF16202F),
    textPrimary: Color(0xFFF3F6FB),
    textSecondary: Color(0xFF9CA3AF),
    textTertiary: Color(0xFF6B7280),
    inverseSurface: Color(0xFFF2F2F4),
    inverseOnSurface: Color(0xFF0B1120),
    card: Color(0xFF0F1725),
    cardElevated: Color(0xFF151E2E),
    cardPress: Color(0xFF1F2B3E),
    overlay: Color(0xCC0B1120),
  );

  /// OLED: true-black canvas with only a whisper of elevated neutral so cards
  /// stay legible instead of collapsing into one flat black wall.
  static const AppSurfaceRamp oledDark = AppSurfaceRamp(
    surface: Color(0xFF000000),
    surfaceLow: Color(0xFF0A0A0B),
    surfaceContainer: Color(0xFF0C0C0E),
    surfaceContainerHigh: Color(0xFF121215),
    surfaceContainerHighest: Color(0xFF1A1A1F),
    outline: Color(0xFF24242B),
    outlineVariant: Color(0xFF1B1B21),
    divider: Color(0xFF111114),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB6B6BE),
    textTertiary: Color(0xFF7E7E88),
    inverseSurface: Color(0xFFF2F2F4),
    inverseOnSurface: Color(0xFF000000),
    card: Color(0xFF060607),
    cardElevated: Color(0xFF0E0E10),
    cardPress: Color(0xFF17171B),
    overlay: Color(0xCC000000),
  );

  /// Sepia dark: restrained warm charcoal — amber, never saturated brown.
  static const AppSurfaceRamp sepiaDark = AppSurfaceRamp(
    surface: Color(0xFF141210),
    surfaceLow: Color(0xFF1A1714),
    surfaceContainer: Color(0xFF1E1B17),
    surfaceContainerHigh: Color(0xFF262219),
    surfaceContainerHighest: Color(0xFF2D2922),
    outline: Color(0xFF4A443A),
    outlineVariant: Color(0xFF332F27),
    divider: Color(0xFF201D19),
    textPrimary: Color(0xFFF2EEE6),
    textSecondary: Color(0xFFC4BCAE),
    textTertiary: Color(0xFF8F877A),
    inverseSurface: Color(0xFFF2EEE6),
    inverseOnSurface: Color(0xFF141210),
    card: Color(0xFF181512),
    cardElevated: Color(0xFF201C18),
    cardPress: Color(0xFF2A251E),
    overlay: Color(0xCC141210),
  );

  /// Sepia light: warm parchment surfaces.
  static const AppSurfaceRamp sepiaLight = AppSurfaceRamp(
    surface: Color(0xFFF5EFE4),
    surfaceLow: Color(0xFFFBF7EE),
    surfaceContainer: Color(0xFFF7F1E6),
    surfaceContainerHigh: Color(0xFFEEE6D6),
    surfaceContainerHighest: Color(0xFFE4DAC6),
    outline: Color(0xFFC9BEA9),
    outlineVariant: Color(0xFFDFD5C2),
    divider: Color(0xFFE9E1D0),
    textPrimary: Color(0xFF2B2620),
    textSecondary: Color(0xFF6E665A),
    textTertiary: Color(0xFF978D7D),
    inverseSurface: Color(0xFF2B2620),
    inverseOnSurface: Color(0xFFF5EFE4),
    card: Color(0xFFFDFAF3),
    cardElevated: Color(0xFFF2EBDC),
    cardPress: Color(0xFFEBE2D1),
    overlay: Color(0xCCF5EFE4),
  );

  /// All 9 palettes in the selector's display order.
  static const List<AppPalette> all = [
    AppPalette.purple,
    AppPalette.aurora,
    AppPalette.ocean,
    AppPalette.ember,
    AppPalette.emerald,
    AppPalette.rose,
    AppPalette.midnight,
    AppPalette.oled,
    AppPalette.sepia,
  ];
}

/// The atmospheric identity of one theme preset.
///
/// Holds the accent pair used to build both dark and light themes plus the
/// optional surface ramps that distinguish Midnight (navy-black), OLED
/// (true black) and Sepia (parchment/charcoal) from the shared neutrals.
@immutable
class AppPalette {
  const AppPalette({
    required this.preset,
    required this.primary,
    required this.highlight,
    required this.lightDeep,
    this.accentGradient,
    this.glowColor,
    this.glassTint,
    this.darkSurfaces,
    this.lightSurfaces,
  });

  final AppThemePreset preset;

  /// Bold dark-mode / atmospheric accent (e.g. `#7C3AED`).
  final Color primary;

  /// Secondary/highlight accent used in gradients and secondary roles
  /// (e.g. `#8B5CF6`).
  final Color highlight;

  /// Deep variant used as the light-mode primary and inverse primary so
  /// accent text/icons keep strong contrast on pale surfaces.
  final Color lightDeep;

  /// Accent gradient stops (defaults to [primary] → [highlight]).
  final List<Color>? accentGradient;

  /// Splash/atmospheric glow colour (defaults to [primary]).
  final Color? glowColor;

  /// Glass/pill tint for the floating navigation pill (defaults to [primary]).
  final Color? glassTint;

  /// Optional dark surface ramp; falls back to the shared VoraTube neutrals.
  final AppSurfaceRamp? darkSurfaces;

  /// Optional light surface ramp; falls back to the shared VoraTube neutrals.
  final AppSurfaceRamp? lightSurfaces;

  AppSurfaceRamp get darkRamp => darkSurfaces ?? AppPalettes.darkNeutral;
  AppSurfaceRamp get lightRamp => lightSurfaces ?? AppPalettes.lightNeutral;

  List<Color> get gradient => accentGradient ?? [primary, highlight];
  Color get glow => glowColor ?? primary;
  Color get tint => glassTint ?? primary;

  AppPalette copyWith({
    AppThemePreset? preset,
    Color? primary,
    Color? highlight,
    Color? lightDeep,
    List<Color>? accentGradient,
    Color? glowColor,
    Color? glassTint,
    AppSurfaceRamp? darkSurfaces,
    AppSurfaceRamp? lightSurfaces,
  }) {
    return AppPalette(
      preset: preset ?? this.preset,
      primary: primary ?? this.primary,
      highlight: highlight ?? this.highlight,
      lightDeep: lightDeep ?? this.lightDeep,
      accentGradient: accentGradient ?? this.accentGradient,
      glowColor: glowColor ?? this.glowColor,
      glassTint: glassTint ?? this.glassTint,
      darkSurfaces: darkSurfaces ?? this.darkSurfaces,
      lightSurfaces: lightSurfaces ?? this.lightSurfaces,
    );
  }

  /// Purple — the default VoraTube identity.
  static const AppPalette purple = AppPalette(
    preset: AppThemePreset.purple,
    primary: Color(0xFF7C3AED),
    highlight: Color(0xFF8B5CF6),
    lightDeep: Color(0xFF5B21B6),
  );

  /// Aurora: indigo → sky.
  static const AppPalette aurora = AppPalette(
    preset: AppThemePreset.aurora,
    primary: Color(0xFF6366F1),
    highlight: Color(0xFF38BDF8),
    lightDeep: Color(0xFF4338CA),
  );

  /// Ocean: blue → light blue.
  static const AppPalette ocean = AppPalette(
    preset: AppThemePreset.ocean,
    primary: Color(0xFF3B82F6),
    highlight: Color(0xFF60A5FA),
    lightDeep: Color(0xFF1D4ED8),
  );

  /// Ember: amber → orange.
  static const AppPalette ember = AppPalette(
    preset: AppThemePreset.ember,
    primary: Color(0xFFF59E0B),
    highlight: Color(0xFFFB923C),
    lightDeep: Color(0xFFB45309),
  );

  /// Emerald: emerald → mint.
  static const AppPalette emerald = AppPalette(
    preset: AppThemePreset.emerald,
    primary: Color(0xFF10B981),
    highlight: Color(0xFF34D399),
    lightDeep: Color(0xFF047857),
  );

  /// Rosé: pink → soft pink.
  static const AppPalette rose = AppPalette(
    preset: AppThemePreset.rose,
    primary: Color(0xFFEC4899),
    highlight: Color(0xFFF472B6),
    lightDeep: Color(0xFFBE185D),
  );

  /// Midnight: cyan over navy-black.
  static const AppPalette midnight = AppPalette(
    preset: AppThemePreset.midnight,
    primary: Color(0xFF22D3EE),
    highlight: Color(0xFF67E8F9),
    lightDeep: Color(0xFF0E7490),
    darkSurfaces: AppPalettes.midnightDark,
  );

  /// OLED: neon lime over true black — a deliberate departure from the violet
  /// [AppPalette.purple] default so the same pure-black canvas reads as its
  /// own distinct identity.
  static const AppPalette oled = AppPalette(
    preset: AppThemePreset.oled,
    primary: Color(0xFFA3E635),
    highlight: Color(0xFFBEF264),
    lightDeep: Color(0xFF4D7C0F),
    darkSurfaces: AppPalettes.oledDark,
  );

  /// Sepia: warm amber over parchment/charcoal.
  static const AppPalette sepia = AppPalette(
    preset: AppThemePreset.sepia,
    primary: Color(0xFFD97706),
    highlight: Color(0xFFF59E0B),
    lightDeep: Color(0xFF92400E),
    darkSurfaces: AppPalettes.sepiaDark,
    lightSurfaces: AppPalettes.sepiaLight,
  );

  static AppPalette of(AppThemePreset preset) {
    for (final palette in AppPalettes.all) {
      if (palette.preset == preset) return palette;
    }
    throw ArgumentError.value(
      preset,
      'preset',
      'No AppPalette registered for this preset.',
    );
  }

  /// Interpolates the accent identity fields toward [other]. The preset tag and
  /// surface ramps snap across the midpoint (like [VoraTheme.lerp]) while the
  /// actual color fields crossfade, so Chameleon theme transitions stay smooth.
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null || t <= 0) return this;
    if (t >= 1) return other;
    Color? c(Color a, Color b) => Color.lerp(a, b, t);
    final gradient = accentGradient == null || other.accentGradient == null
        ? null
        : List<Color>.generate(
            accentGradient!.length,
            (i) => Color.lerp(
              accentGradient![i],
              other.accentGradient![i % other.accentGradient!.length],
              t,
            )!,
          );
    return AppPalette(
      preset: t < 0.5 ? preset : other.preset,
      primary: c(primary, other.primary)!,
      highlight: c(highlight, other.highlight)!,
      lightDeep: c(lightDeep, other.lightDeep)!,
      accentGradient: gradient,
      glowColor: glowColor == null || other.glowColor == null
          ? null
          : c(glow, other.glow),
      glassTint: glassTint == null || other.glassTint == null
          ? null
          : c(tint, other.tint),
      darkSurfaces: darkSurfaces?.lerp(other.darkSurfaces, t),
      lightSurfaces: lightSurfaces?.lerp(other.lightSurfaces, t),
    );
  }
}

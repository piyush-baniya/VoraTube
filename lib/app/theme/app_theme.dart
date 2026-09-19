import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';
import 'palettes.dart';

export 'palettes.dart'
    show AppPalette, AppPalettes, AppSurfaceRamp, AppThemePreset;

/// The theme extension resolved for the active [AppPalette] and brightness so
/// individual widgets can reach the named neutral colors the presets override
/// (Midnight navy-black, OLED true black, Sepia parchment/charcoal).
@immutable
class VoraTheme extends ThemeExtension<VoraTheme> {
  const VoraTheme({
    required this.palette,
    required this.surfaces,
    required this.isDark,
  });

  final AppPalette palette;
  final AppSurfaceRamp surfaces;
  final bool isDark;

  @override
  VoraTheme copyWith({
    AppPalette? palette,
    AppSurfaceRamp? surfaces,
    bool? isDark,
  }) {
    return VoraTheme(
      palette: palette ?? this.palette,
      surfaces: surfaces ?? this.surfaces,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  VoraTheme lerp(ThemeExtension<VoraTheme>? other, double t) {
    if (other is! VoraTheme) return this;
    // Chameleon theme transitions crossfade every color field smoothly; preset
    // switches stay instant because themeAnimationDuration is zero (t is always
    // 0 or 1 there, so the neutral return below equals the nearest side).
    return VoraTheme(
      palette: palette.lerp(other.palette, t),
      surfaces: surfaces.lerp(other.surfaces, t),
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

extension VoraThemeContext on BuildContext {
  /// The active [AppPalette] (accent identity). Falls back to the default
  /// Purple preset outside the app theme so standalone widgets/tests never
  /// crash.
  AppPalette get palette =>
      Theme.of(this).extension<VoraTheme>()?.palette ?? AppPalette.purple;

  /// The resolved neutral [AppSurfaceRamp] for the current brightness. Falls
  /// back to the shared neutral ramp outside the app theme.
  AppSurfaceRamp get surfaces {
    final resolved = Theme.of(this).extension<VoraTheme>()?.surfaces;
    if (resolved != null) return resolved;
    return Theme.of(this).brightness == Brightness.dark
        ? AppPalettes.darkNeutral
        : AppPalettes.lightNeutral;
  }
}

abstract final class AppTheme {
  /// Memoized per-preset ThemeData pairs so MaterialApp rebuilds (theme
  /// switches, root provider churn) reuse identical ThemeData instances.
  static final Map<AppThemePreset, ({ThemeData light, ThemeData dark})> _cache =
      {};

  /// Builds (or returns the cached) light + dark ThemeData pair for [preset].
  static ({ThemeData light, ThemeData dark}) of(AppThemePreset preset) {
    return _cache.putIfAbsent(preset, () {
      final palette = AppPalette.of(preset);
      return (
        light: buildThemeData(
          _lightScheme(palette, palette.lightRamp),
          palette.lightRamp,
          isDark: false,
          palette: palette,
        ),
        dark: buildThemeData(
          _darkScheme(palette, palette.darkRamp),
          palette.darkRamp,
          isDark: true,
          palette: palette,
        ),
      );
    });
  }

  static ThemeData light(AppThemePreset preset) => of(preset).light;
  static ThemeData dark(AppThemePreset preset) => of(preset).dark;

  /// Assembles the full VoraTube ThemeData chrome around an explicit
  /// [ColorScheme] and neutral [AppSurfaceRamp] (which also feed the [VoraTheme]
  /// extension). Shared by the preset themes and the artwork-driven Chameleon
  /// theme so dynamic mode inherits the exact same component styling.
  static ThemeData buildThemeData(
    ColorScheme scheme,
    AppSurfaceRamp ramp, {
    required bool isDark,
    required AppPalette palette,
  }) {
    return _build(scheme, ramp, isDark: isDark, palette: palette);
  }

  static ColorScheme _darkScheme(AppPalette p, AppSurfaceRamp r) {
    return ColorScheme.dark(
      primary: p.primary,
      // Dark-mode on-primary stays white; accent chips/buttons use white text
      // even on vivid accents like Ember amber.
      onPrimary: const Color(0xFFFFFFFF),
      primaryContainer: p.lightDeep,
      onPrimaryContainer: r.textPrimary,
      secondary: p.highlight,
      secondaryContainer: r.surfaceContainerHighest,
      onSecondaryContainer: r.textPrimary,
      tertiary: AppColors.success,
      tertiaryContainer: r.cardElevated,
      onTertiaryContainer: r.textPrimary,
      error: AppColors.error,
      onError: r.textPrimary,
      surface: r.surface,
      onSurface: r.textPrimary,
      surfaceContainerLowest: r.surface,
      surfaceContainerLow: r.surfaceLow,
      surfaceContainer: r.surfaceContainer,
      surfaceContainerHigh: r.surfaceContainerHigh,
      surfaceContainerHighest: r.surfaceContainerHighest,
      onSurfaceVariant: r.textSecondary,
      outline: r.outline,
      outlineVariant: r.outlineVariant,
      scrim: r.overlay,
      shadow: AppColors.voidBlack,
      inverseSurface: r.inverseSurface,
      onInverseSurface: r.inverseOnSurface,
      inversePrimary: p.lightDeep,
    );
  }

  static ColorScheme _lightScheme(AppPalette p, AppSurfaceRamp r) {
    return ColorScheme.light(
      primary: p.lightDeep,
      // Light mode uses a deep primary; its content must stay white for
      // contrast on the dark-violet button (near-black was muddy).
      onPrimary: const Color(0xFFFFFFFF),
      primaryContainer: Color.alphaBlend(
        p.primary.withValues(alpha: 0.16),
        r.surface,
      ),
      onPrimaryContainer: p.lightDeep,
      secondary: p.lightDeep,
      secondaryContainer: r.surfaceContainerHighest,
      onSecondaryContainer: r.textPrimary,
      tertiary: AppColors.success,
      tertiaryContainer: r.cardElevated,
      onTertiaryContainer: r.textPrimary,
      error: AppColors.error,
      onError: r.textPrimary,
      surface: r.surface,
      onSurface: r.textPrimary,
      surfaceContainerLowest: r.surfaceLow,
      surfaceContainerLow: r.surface,
      surfaceContainer: r.surface,
      surfaceContainerHigh: r.surfaceContainerHigh,
      surfaceContainerHighest: r.surfaceContainerHighest,
      onSurfaceVariant: r.textSecondary,
      outline: r.outline,
      outlineVariant: r.outlineVariant,
      scrim: r.overlay,
      shadow: AppColors.voidBlack,
      inverseSurface: r.inverseSurface,
      onInverseSurface: r.inverseOnSurface,
      inversePrimary: p.primary,
    );
  }

  static ThemeData _build(
    ColorScheme scheme,
    AppSurfaceRamp ramp, {
    required bool isDark,
    required AppPalette palette,
  }) {
    final textTheme = _textTheme(scheme);
    return _buildChromeTheme(
      scheme: scheme,
      ramp: ramp,
      isDark: isDark,
      palette: palette,
      textTheme: textTheme,
    );
  }

  static TextTheme _textTheme(ColorScheme scheme) {
    final baseText = Typography.material2021(colorScheme: scheme).black
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    return baseText.copyWith(
      displayLarge: baseText.displayLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        height: 1.15,
      ),
      displayMedium: baseText.displayMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        height: 1.2,
      ),
      displaySmall: baseText.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1.25,
      ),
      headlineLarge: baseText.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        height: 1.2,
      ),
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        height: 1.25,
      ),
      headlineSmall: baseText.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.3,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        height: 1.3,
      ),
      titleMedium: baseText.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        height: 1.35,
      ),
      titleSmall: baseText.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1.4,
      ),
      bodyLarge: baseText.bodyLarge?.copyWith(
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.5,
      ),
      bodyMedium: baseText.bodyMedium?.copyWith(
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        height: 1.45,
      ),
      bodySmall: baseText.bodySmall?.copyWith(
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
        height: 1.4,
      ),
      labelLarge: baseText.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelMedium: baseText.labelMedium?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      ),
      labelSmall: baseText.labelSmall?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0.4,
      ),
    );
  }

  static ThemeData _buildChromeTheme({
    required ColorScheme scheme,
    required AppSurfaceRamp ramp,
    required bool isDark,
    required AppPalette palette,
    required TextTheme textTheme,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      extensions: [VoraTheme(palette: palette, surfaces: ramp, isDark: isDark)],
      dividerTheme: DividerThemeData(
        color: ramp.divider,
        thickness: AppTokens.borderHairline,
        space: AppTokens.borderHairline,
        indent: 0,
        endIndent: 0,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.headlineSmall,
        toolbarHeight: 56,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.14 : 0.10),
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelSmall!.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.rMd),
          ),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          side: BorderSide(color: scheme.outline, width: AppTokens.borderThin),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.rMd),
          ),
          foregroundColor: scheme.onSurface,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(AppTokens.touchTarget, AppTokens.touchTarget),
          textStyle: textTheme.labelLarge,
          foregroundColor: scheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.rSm),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(AppTokens.touchTarget, AppTokens.touchTarget),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.rMd),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rMd),
        ),
        actionTextColor: scheme.primary,
        elevation: 4,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? ramp.surfaceContainer : ramp.surfaceLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.rXxl),
          ),
        ),
        showDragHandle: true,
        dragHandleSize: const Size(36, 4),
        dragHandleColor: ramp.textTertiary.withValues(alpha: 0.4),
        constraints: const BoxConstraints(maxWidth: AppTokens.contentMaxWidth),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? ramp.surfaceContainerHigh : ramp.surfaceLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rXxl),
        ),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
        alignment: Alignment.center,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rFull),
        ),
        side: BorderSide(
          color: ramp.outlineVariant,
          width: AppTokens.borderThin,
        ),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s3,
          vertical: AppTokens.s1,
        ),
        labelPadding: EdgeInsets.zero,
        backgroundColor: ramp.cardElevated,
        selectedColor: scheme.primary.withValues(alpha: 0.16),
        secondarySelectedColor: scheme.secondary.withValues(alpha: 0.16),
        pressElevation: 0,
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: ramp.card,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rLg),
          side: BorderSide(
            color: ramp.outlineVariant,
            width: AppTokens.borderHairline,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s1,
        ),
        dense: true,
        horizontalTitleGap: AppTokens.s3,
        minLeadingWidth: 40,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        leadingAndTrailingTextStyle: textTheme.bodyMedium,
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rMd),
        ),
        selectedColor: scheme.primary.withValues(alpha: 0.10),
        selectedTileColor: scheme.primary.withValues(alpha: 0.06),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ramp.cardElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s5,
          vertical: AppTokens.s3,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.rXl),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.rXl),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.rXl),
          borderSide: BorderSide(
            color: scheme.primary,
            width: AppTokens.borderThin * 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.rXl),
          borderSide: BorderSide(
            color: scheme.error,
            width: AppTokens.borderThin,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.rXl),
          borderSide: BorderSide.none,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: ramp.surfaceContainerHighest,
        circularTrackColor: ramp.surfaceContainerHighest,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: ramp.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        valueIndicatorColor: scheme.primary,
        valueIndicatorTextStyle: textTheme.labelSmall?.copyWith(
          color: scheme.onPrimary,
        ),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return ramp.textTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary.withValues(alpha: 0.32);
          }
          return ramp.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return ramp.outline;
        }),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          return scheme.primary.withValues(alpha: 0.12);
        }),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(scheme.onPrimary),
        side: BorderSide(color: ramp.outline, width: AppTokens.borderThin),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rSm),
        ),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return scheme.onSurfaceVariant;
        }),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStateProperty.all(
            isDark ? ramp.cardElevated : ramp.surfaceLow,
          ),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.rLg),
              side: BorderSide(
                color: ramp.outlineVariant,
                width: AppTokens.borderHairline,
              ),
            ),
          ),
          elevation: WidgetStateProperty.all(8),
          shadowColor: WidgetStateProperty.all(
            Colors.black.withValues(alpha: 0.4),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? ramp.cardElevated : ramp.surfaceLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rLg),
          side: BorderSide(
            color: ramp.outlineVariant,
            width: AppTokens.borderHairline,
          ),
        ),
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        textStyle: textTheme.bodyMedium,
        labelTextStyle: WidgetStateProperty.all(textTheme.bodyMedium),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: ramp.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTokens.rMd),
          border: Border.all(
            color: ramp.outlineVariant,
            width: AppTokens.borderHairline,
          ),
        ),
        textStyle: textTheme.labelSmall?.copyWith(color: ramp.textSecondary),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s3,
          vertical: AppTokens.s2,
        ),
        preferBelow: true,
        verticalOffset: 8,
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        overlayColor: WidgetStateProperty.resolveWith((states) {
          return scheme.primary.withValues(alpha: 0.08);
        }),
        splashFactory: NoSplash.splashFactory,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rMd),
          side: BorderSide.none,
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rMd),
          side: BorderSide.none,
        ),
        backgroundColor: ramp.cardElevated,
        collapsedBackgroundColor: ramp.surfaceContainer,
        textColor: scheme.onSurface,
        collapsedTextColor: scheme.onSurface,
        iconColor: scheme.onSurfaceVariant,
        collapsedIconColor: scheme.onSurfaceVariant,
        childrenPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s2,
        ),
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s1,
        ),
      ),
    );
  }
}

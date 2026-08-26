import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get dark => _build(_darkScheme, isDark: true);

  static ThemeData get light => _build(_lightScheme, isDark: false);

  static ColorScheme get _darkScheme => const ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    primaryContainer: AppColors.accentDeep,
    onPrimaryContainer: Colors.white,
    secondary: AppColors.accentBright,
    secondaryContainer: AppColors.surfaceHighDark,
    onSecondaryContainer: AppColors.textPrimaryDark,
    surface: AppColors.voidBlack,
    onSurface: AppColors.textPrimaryDark,
    surfaceContainerLowest: AppColors.voidBlack,
    surfaceContainerLow: AppColors.surfaceDark,
    surfaceContainer: AppColors.surfaceDark,
    surfaceContainerHigh: AppColors.surfaceRaisedDark,
    surfaceContainerHighest: AppColors.surfaceHighDark,
    onSurfaceVariant: AppColors.textSecondaryDark,
    outline: AppColors.outlineDark,
    outlineVariant: AppColors.outlineDark,
  );

  static ColorScheme get _lightScheme => const ColorScheme.light(
    primary: AppColors.accentDeep,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFFFE1EA),
    onPrimaryContainer: AppColors.accentDeep,
    secondary: AppColors.accentDeep,
    secondaryContainer: AppColors.surfaceHighLight,
    onSecondaryContainer: AppColors.textPrimaryLight,
    surface: AppColors.paperLight,
    onSurface: AppColors.textPrimaryLight,
    surfaceContainerLowest: AppColors.surfaceLight,
    surfaceContainerLow: AppColors.paperLight,
    surfaceContainer: AppColors.surfaceLight,
    surfaceContainerHigh: AppColors.surfaceRaisedLight,
    surfaceContainerHighest: AppColors.surfaceHighLight,
    onSurfaceVariant: AppColors.textSecondaryLight,
    outline: AppColors.outlineLight,
    outlineVariant: AppColors.outlineLight,
  );

  static ThemeData _build(ColorScheme scheme, {required bool isDark}) {
    final baseText = Typography.material2021(colorScheme: scheme).black
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    final textTheme = baseText.copyWith(
      displaySmall: baseText.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.7,
      ),
      headlineSmall: baseText.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleLarge: baseText.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: baseText.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleSmall: baseText.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: baseText.bodyMedium?.copyWith(height: 1.35),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.headlineSmall,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.16 : 0.12),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.titleSmall!.copyWith(
            fontSize: 12,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          textStyle: textTheme.titleSmall,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          side: BorderSide(color: scheme.outline),
          textStyle: textTheme.titleSmall,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: textTheme.titleSmall,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
    );
  }
}

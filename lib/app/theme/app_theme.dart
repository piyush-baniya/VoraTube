import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get dark => _base(
    ColorScheme.fromSeed(
      seedColor: AppColors.voraPink,
      brightness: Brightness.dark,
    ),
  );

  static ThemeData get light =>
      _base(ColorScheme.fromSeed(seedColor: AppColors.voraPink));

  static ThemeData _base(ColorScheme scheme) {
    final bool isDark = scheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: isDark
          ? scheme.copyWith(
              surface: AppColors.amoledBlack,
              surfaceContainerLowest: Colors.black,
              surfaceContainerLow: AppColors.surfaceDark,
              surfaceContainer: AppColors.surfaceContainerDark,
              surfaceContainerHigh: AppColors.surfaceContainerDark,
              surfaceContainerHighest: AppColors.surfaceContainerDark,
            )
          : scheme,
      scaffoldBackgroundColor: isDark ? AppColors.amoledBlack : scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: isDark ? AppColors.amoledBlack : scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: isDark
            ? AppColors.amoledBlack
            : scheme.surfaceContainer,
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
      ),
    );
  }
}

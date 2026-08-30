import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';

abstract final class AppTheme {
  /// Memoized so MaterialApp rebuilds (theme switches, root provider churn)
  /// reuse the identical ThemeData instead of reconstructing the whole theme
  /// graph every time.
  static final ThemeData dark = _build(_darkScheme, isDark: true);

  static final ThemeData light = _build(_lightScheme, isDark: false);

  static ColorScheme get _darkScheme => const ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: AppColors.textPrimaryDark,
    primaryContainer: AppColors.accentDeep,
    onPrimaryContainer: AppColors.textPrimaryDark,
    secondary: AppColors.accentBright,
    secondaryContainer: AppColors.surfaceHighDark,
    onSecondaryContainer: AppColors.textPrimaryDark,
    tertiary: AppColors.success,
    tertiaryContainer: AppColors.surfaceRaisedDark,
    onTertiaryContainer: AppColors.textPrimaryDark,
    error: AppColors.error,
    onError: AppColors.textPrimaryDark,
    surface: AppColors.voidBlack,
    onSurface: AppColors.textPrimaryDark,
    surfaceContainerLowest: AppColors.voidBlack,
    surfaceContainerLow: AppColors.surfaceDark,
    surfaceContainer: AppColors.surfaceDark,
    surfaceContainerHigh: AppColors.surfaceRaisedDark,
    surfaceContainerHighest: AppColors.surfaceHighDark,
    onSurfaceVariant: AppColors.textSecondaryDark,
    outline: AppColors.outlineDark,
    outlineVariant: AppColors.borderSubtleDark,
    scrim: AppColors.overlayDark,
    shadow: AppColors.voidBlack,
    inverseSurface: AppColors.inverseSurfaceDark,
    onInverseSurface: AppColors.inverseOnSurfaceDark,
    inversePrimary: AppColors.accentDeep,
  );

  static ColorScheme get _lightScheme => const ColorScheme.light(
    primary: AppColors.accentDeep,
    onPrimary: AppColors.textPrimaryLight,
    primaryContainer: Color(0xFFE9D5FF),
    onPrimaryContainer: AppColors.accentDeep,
    secondary: AppColors.accentDeep,
    secondaryContainer: AppColors.surfaceHighLight,
    onSecondaryContainer: AppColors.textPrimaryLight,
    tertiary: AppColors.success,
    tertiaryContainer: AppColors.surfaceRaisedLight,
    onTertiaryContainer: AppColors.textPrimaryLight,
    error: AppColors.error,
    onError: AppColors.textPrimaryLight,
    surface: AppColors.paperLight,
    onSurface: AppColors.textPrimaryLight,
    surfaceContainerLowest: AppColors.surfaceLight,
    surfaceContainerLow: AppColors.paperLight,
    surfaceContainer: AppColors.paperLight,
    surfaceContainerHigh: AppColors.surfaceRaisedLight,
    surfaceContainerHighest: AppColors.surfaceHighLight,
    onSurfaceVariant: AppColors.textSecondaryLight,
    outline: AppColors.outlineLight,
    outlineVariant: AppColors.borderSubtleLight,
    scrim: AppColors.overlayLight,
    shadow: AppColors.voidBlack,
    inverseSurface: AppColors.inverseSurfaceLight,
    onInverseSurface: AppColors.inverseOnSurfaceLight,
    inversePrimary: AppColors.accent,
  );

  static ThemeData _build(ColorScheme scheme, {required bool isDark}) {
    final baseText = Typography.material2021(colorScheme: scheme).black
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    final textTheme = baseText.copyWith(
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

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
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
        backgroundColor: isDark
            ? AppColors.surfaceDark
            : AppColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.rXxl),
          ),
        ),
        showDragHandle: true,
        dragHandleSize: const Size(36, 4),
        dragHandleColor: isDark
            ? AppColors.textTertiaryDark.withValues(alpha: 0.4)
            : AppColors.textTertiaryLight.withValues(alpha: 0.4),
        constraints: const BoxConstraints(maxWidth: AppTokens.contentMaxWidth),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark
            ? AppColors.surfaceRaisedDark
            : AppColors.surfaceLight,
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
          color: isDark
              ? AppColors.borderSubtleDark
              : AppColors.borderSubtleLight,
          width: AppTokens.borderThin,
        ),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s3,
          vertical: AppTokens.s1,
        ),
        labelPadding: EdgeInsets.zero,
        backgroundColor: isDark
            ? AppColors.surfaceRaisedDark
            : AppColors.surfaceRaisedLight,
        selectedColor: scheme.primary.withValues(alpha: 0.16),
        secondarySelectedColor: scheme.secondary.withValues(alpha: 0.16),
        pressElevation: 0,
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rLg),
          side: BorderSide(
            color: isDark
                ? AppColors.borderSubtleDark
                : AppColors.borderSubtleLight,
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
        fillColor: isDark
            ? AppColors.surfaceRaisedDark
            : AppColors.surfaceRaisedLight,
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
        linearTrackColor: isDark
            ? AppColors.surfaceHighDark
            : AppColors.surfaceHighLight,
        circularTrackColor: isDark
            ? AppColors.surfaceHighDark
            : AppColors.surfaceHighLight,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: isDark
            ? AppColors.surfaceHighDark
            : AppColors.surfaceHighLight,
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
          return isDark
              ? AppColors.textTertiaryDark
              : AppColors.textTertiaryLight;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary.withValues(alpha: 0.32);
          }
          return isDark
              ? AppColors.surfaceHighDark
              : AppColors.surfaceHighLight;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return isDark ? AppColors.outlineDark : AppColors.outlineLight;
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
        side: BorderSide(
          color: isDark ? AppColors.outlineDark : AppColors.outlineLight,
          width: AppTokens.borderThin,
        ),
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
            isDark ? AppColors.surfaceRaisedDark : AppColors.surfaceLight,
          ),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.rLg),
              side: BorderSide(
                color: isDark
                    ? AppColors.borderSubtleDark
                    : AppColors.borderSubtleLight,
                width: AppTokens.borderHairline,
              ),
            ),
          ),
          elevation: WidgetStateProperty.all(8),
          shadowColor: WidgetStateProperty.all(
            AppColors.voidBlack.withValues(alpha: 0.4),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? AppColors.surfaceRaisedDark : AppColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rLg),
          side: BorderSide(
            color: isDark
                ? AppColors.borderSubtleDark
                : AppColors.borderSubtleLight,
            width: AppTokens.borderHairline,
          ),
        ),
        elevation: 8,
        shadowColor: AppColors.voidBlack.withValues(alpha: 0.4),
        textStyle: textTheme.bodyMedium,
        labelTextStyle: WidgetStateProperty.all(textTheme.bodyMedium),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.surfaceHighestDark
              : AppColors.surfaceHighestLight,
          borderRadius: BorderRadius.circular(AppTokens.rMd),
          border: Border.all(
            color: isDark
                ? AppColors.borderSubtleDark
                : AppColors.borderSubtleLight,
            width: AppTokens.borderHairline,
          ),
        ),
        textStyle: textTheme.labelSmall?.copyWith(
          color: isDark
              ? AppColors.textSecondaryDark
              : AppColors.textSecondaryLight,
        ),
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
        backgroundColor: isDark
            ? AppColors.surfaceRaisedDark
            : AppColors.surfaceRaisedLight,
        collapsedBackgroundColor: isDark
            ? AppColors.surfaceDark
            : AppColors.surfaceLight,
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

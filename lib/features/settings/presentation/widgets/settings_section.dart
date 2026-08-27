import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';

/// A premium settings section with title and children.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.showBorder = true,
  });

  final String title;
  final List<Widget> children;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.s5,
            AppTokens.s1,
            AppTokens.s5,
            AppTokens.s3,
          ),
          child: Text(
            title.toUpperCase(),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
              letterSpacing: 1.0,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : AppColors.cardLight,
            borderRadius: BorderRadius.circular(AppTokens.rLg),
            border: showBorder
                ? Border.all(
                    color: isDark
                        ? AppColors.borderSubtleDark
                        : AppColors.borderSubtleLight,
                    width: AppTokens.borderHairline,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
                spreadRadius: -4,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// Settings section with an icon in the title.
class SettingsSectionWithIcon extends StatelessWidget {
  const SettingsSectionWithIcon({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.showBorder = true,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.s5,
            AppTokens.s1,
            AppTokens.s5,
            AppTokens.s3,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: AppTokens.s2),
              Text(
                title.toUpperCase(),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurfaceVariant,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : AppColors.cardLight,
            borderRadius: BorderRadius.circular(AppTokens.rLg),
            border: showBorder
                ? Border.all(
                    color: isDark
                        ? AppColors.borderSubtleDark
                        : AppColors.borderSubtleLight,
                    width: AppTokens.borderHairline,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
                spreadRadius: -4,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}
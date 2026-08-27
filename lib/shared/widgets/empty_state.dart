import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_tokens.dart';

/// Intentional empty-state with icon, message, and optional action.
///
/// Every empty screen in VoraTube uses this to ensure visual consistency
/// and a polished feel. The icon uses a subtle gradient background circle
/// rather than a flat icon.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.iconSize = 80,
    this.iconDiameter = 100,
    this.showGradientRing = true,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double iconSize;
  final double iconDiameter;
  final bool showGradientRing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon with premium gradient background.
          Stack(
            alignment: Alignment.center,
            children: [
              if (showGradientRing) ...[
                Container(
                  width: iconDiameter + 4,
                  height: iconDiameter + 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              colorScheme.primary.withValues(alpha: 0.2),
                              colorScheme.primary.withValues(alpha: 0.05),
                              Colors.transparent,
                            ]
                          : [
                              colorScheme.primary.withValues(alpha: 0.15),
                              colorScheme.primary.withValues(alpha: 0.03),
                              Colors.transparent,
                            ],
                      stops: const [0.0, 0.6, 1.0],
                    ),
                  ),
                ),
                Container(
                  width: iconDiameter,
                  height: iconDiameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                              colorScheme.surfaceContainerHigh.withValues(alpha: 0.3),
                            ]
                          : [
                              colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                              colorScheme.surfaceContainerHigh.withValues(alpha: 0.3),
                            ],
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  width: iconDiameter,
                  height: iconDiameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  ),
                ),
              ],
              Icon(
                icon,
                size: iconSize,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                semanticLabel: title,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s6),
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTokens.s3),
          Text(
            message,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppTokens.s7),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(actionLabel!),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s6,
                  vertical: AppTokens.s3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Section header with optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.actionLabel,
    this.onAction,
    this.showDivider = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppTokens.s1),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(width: AppTokens.s2),
                TextButton(
                  onPressed: onAction,
                  child: Text(
                    actionLabel!,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (showDivider) ...[
            const SizedBox(height: AppTokens.s3),
            Divider(
              height: AppTokens.borderHairline,
              thickness: AppTokens.borderHairline,
              color: colorScheme.outlineVariant,
              indent: 0,
              endIndent: 0,
            ),
          ],
        ],
      ),
    );
  }
}

/// Screen header with consistent styling.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.showBackButton = false,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool showBackButton;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.s5,
          AppTokens.s4,
          AppTokens.s5,
          AppTokens.s2,
        ),
        child: Row(
          children: [
            if (showBackButton)
              IconButton(
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                color: colorScheme.onSurfaceVariant,
                tooltip: 'Close',
              )
            else
              const SizedBox(width: 48),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
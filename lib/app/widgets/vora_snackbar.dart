import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// The semantic variants supported by [VoraSnackbar].
enum VoraSnackbarVariant { success, error, warning, info, progress }

/// A reusable, animated snackbar that matches the VoraTube design system.
class VoraSnackbar extends StatelessWidget {
  const VoraSnackbar({
    super.key,
    required this.variant,
    required this.message,
    this.title,
    this.secondaryText,
    this.actionLabel,
    this.onAction,
    this.progress,
  });

  final VoraSnackbarVariant variant;
  final String message;
  final String? title;
  final String? secondaryText;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double? progress;

  _ResolvedStyle _style(ColorScheme scheme) {
    switch (variant) {
      case VoraSnackbarVariant.success:
        return const _ResolvedStyle(
          icon: Icons.check_circle_rounded,
          color: AppColors.success,
        );
      case VoraSnackbarVariant.error:
        return _ResolvedStyle(icon: Icons.error_rounded, color: scheme.error);
      case VoraSnackbarVariant.warning:
        return const _ResolvedStyle(
          icon: Icons.warning_rounded,
          color: AppColors.warning,
        );
      case VoraSnackbarVariant.info:
        return const _ResolvedStyle(
          icon: Icons.info_rounded,
          color: AppColors.info,
        );
      case VoraSnackbarVariant.progress:
        return _ResolvedStyle(
          icon: Icons.hourglass_top_rounded,
          color: scheme.primary,
        );
    }
  }

  static void show(
    BuildContext context, {
    required VoraSnackbarVariant variant,
    required String message,
    String? title,
    String? secondaryText,
    String? actionLabel,
    VoidCallback? onAction,
    double? progress,
    Duration duration = const Duration(seconds: 4),
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: VoraSnackbar(
            variant: variant,
            message: message,
            title: title,
            secondaryText: secondaryText,
            actionLabel: actionLabel,
            onAction: onAction,
            progress: progress,
          ),
          duration: duration,
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          margin: const EdgeInsets.fromLTRB(
            AppTokens.s4,
            AppTokens.s4,
            AppTokens.s4,
            AppTokens.s10,
          ),
          padding: EdgeInsets.zero,
        ),
      );
  }

  static void success(BuildContext context, String message, {String? title}) {
    show(
      context,
      variant: VoraSnackbarVariant.success,
      message: message,
      title: title,
      duration: const Duration(seconds: 3),
    );
  }

  static void error(
    BuildContext context,
    String message, {
    String? title,
    String? retryLabel,
    VoidCallback? onRetry,
  }) {
    show(
      context,
      variant: VoraSnackbarVariant.error,
      message: message,
      title: title,
      actionLabel: retryLabel,
      onAction: onRetry,
      duration: const Duration(seconds: 6),
    );
  }

  static void warning(BuildContext context, String message, {String? title}) {
    show(
      context,
      variant: VoraSnackbarVariant.warning,
      message: message,
      title: title,
      duration: const Duration(seconds: 4),
    );
  }

  static void info(BuildContext context, String message, {String? title}) {
    show(
      context,
      variant: VoraSnackbarVariant.info,
      message: message,
      title: title,
      duration: const Duration(seconds: 3),
    );
  }

  static void showProgress(
    BuildContext context,
    String message, {
    String? title,
    double? progress,
  }) {
    show(
      context,
      variant: VoraSnackbarVariant.progress,
      message: message,
      title: title,
      progress: progress,
      duration: const Duration(seconds: 30),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = _style(scheme);
    final isDark = scheme.brightness == Brightness.dark;
    final surface = isDark
        ? AppColors.cardElevatedDark
        : AppColors.cardElevatedLight;
    final outline = isDark
        ? AppColors.borderSubtleDark
        : AppColors.borderSubtleLight;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppTokens.rMd),
        border: Border.all(color: outline, width: AppTokens.borderHairline),
        boxShadow: AppTokens.shadowMd(Colors.black),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s3,
        AppTokens.s2,
        AppTokens.s2,
        AppTokens.s2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(style.icon, color: style.color, size: 22),
              const SizedBox(width: AppTokens.s2),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(
                        title!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppTokens.s0),
                    ],
                    Text(
                      message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.9),
                      ),
                    ),
                    if (secondaryText != null) ...[
                      const SizedBox(height: AppTokens.s1),
                      Text(
                        secondaryText!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (actionLabel != null)
                Padding(
                  padding: const EdgeInsets.only(left: AppTokens.s2),
                  child: TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      foregroundColor: style.color,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.s2,
                        vertical: AppTokens.s1,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      actionLabel!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: AppTokens.s2),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTokens.rFull),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: isDark
                    ? AppColors.surfaceHighDark
                    : AppColors.surfaceHighLight,
                valueColor: AlwaysStoppedAnimation<Color>(style.color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResolvedStyle {
  const _ResolvedStyle({required this.icon, required this.color});
  final IconData icon;
  final Color color;
}

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_tokens.dart';
import 'update_models.dart';
import 'update_url_launcher.dart';

/// Presents the "Update Available" / "Update Required" dialog in VoraTube's
/// visual language. Responsible ONLY for presentation — the caller (the app
/// shell) decides when to show it and what to do after "Update Now"/"Later".
class UpdateAvailableDialog extends StatelessWidget {
  const UpdateAvailableDialog({
    super.key,
    required this.decision,
    required this.info,
  });

  final UpdateDecision decision;
  final UpdateInfo info;

  bool get isRequired => decision == UpdateDecision.required;

  void _dismiss(BuildContext context) => Navigator.of(context).pop();

  Future<void> _updateNow(BuildContext context) async {
    final launched = await const UpdateUrlLauncher().open();
    if (!context.mounted) return;
    if (!launched) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text(
              'Could not open the update page. Please check your connection and try again.',
            ),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _updateNow(context),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppColors.accent;

    final notes = info.hasReleaseNotes ? info.releaseNotes : const <String>[];

    return Dialog(
      backgroundColor: isDark
          ? AppColors.cardElevatedDark
          : AppColors.cardElevatedLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.rXl),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: AppTokens.s6),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.s6,
          AppTokens.s6,
          AppTokens.s6,
          AppTokens.s4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Icon badge + headline.
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent.withValues(alpha: 0.30),
                        accent.withValues(alpha: 0.08),
                      ],
                    ),
                  ),
                  child: Icon(
                    isRequired
                        ? Icons.error_rounded
                        : Icons.system_update_rounded,
                    color: isRequired ? AppColors.warning : accent,
                    size: 26,
                  ),
                ),
                const SizedBox(width: AppTokens.s3),
                Expanded(
                  child: Text(
                    isRequired ? 'Update Required' : 'VoraTube Update',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.s4),

            Text(
              isRequired
                  ? 'Your version is no longer supported. Update to continue.'
                  : 'A new version of VoraTube is ready.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),

            // Version chip.
            const SizedBox(height: AppTokens.s3),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s3,
                  vertical: AppTokens.s1,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppTokens.rFull),
                ),
                child: Text(
                  'v${info.latestVersion}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

            if (notes.isNotEmpty) ...[
              const SizedBox(height: AppTokens.s4),
              Text(
                'What\'s new',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppTokens.s1),
              for (final note in notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTokens.s1),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Icon(
                          Icons.check_circle_outline_rounded,
                          size: 14,
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(width: AppTokens.s2),
                      Expanded(
                        child: Text(note, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
            ],

            const SizedBox(height: AppTokens.s5),

            // Actions.
            FilledButton(
              onPressed: () => _updateNow(context),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(AppTokens.touchTarget),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s5,
                  vertical: AppTokens.s3,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.rLg),
                ),
              ),
              child: const Text(
                'Update Now',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            // Optional updates get a "Later" escape; required updates do not.
            if (!isRequired) ...[
              const SizedBox(height: AppTokens.s1),
              TextButton(
                onPressed: () => _dismiss(context),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(AppTokens.touchTarget),
                ),
                child: Text(
                  'Later',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows the update dialog for the given prompt and returns once it closes.
/// The caller is responsible for clearing the prompt from the controller.
Future<void> showUpdateDialog(
  BuildContext context, {
  required UpdateDecision decision,
  required UpdateInfo info,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpdateAvailableDialog(decision: decision, info: info),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../app/widgets/vora_snackbar.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import 'premium_models.dart';
import 'premium_providers.dart';

/// Opens the "Activate Premium" bottom sheet, styled with VoraTube's design
/// system (surfaces, radius, primary spacing, the shared pressable component).
///
/// The user types a code into an obscured field, taps Activate, and — if the
/// code is valid — Premium is activated, ads are disabled immediately, and a
/// small confirmation is shown. The actual code is never displayed, logged or
/// persisted.
Future<void> showPremiumActivationSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _PremiumActivationSheet(),
  );
}

/// Confirmation shown when the user taps "Disable Premium" in Settings.
Future<bool> showPremiumDisableDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Disable Premium?'),
      content: const Text('Ads will appear again in VoraTube.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          child: const Text('Disable'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _PremiumActivationSheet extends ConsumerStatefulWidget {
  const _PremiumActivationSheet();

  @override
  ConsumerState<_PremiumActivationSheet> createState() =>
      _PremiumActivationSheetState();
}

class _PremiumActivationSheetState
    extends ConsumerState<_PremiumActivationSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _obscured = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final entered = _controller.text;
    if (entered.isEmpty) {
      setState(() => _error = 'Enter your premium code.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    // Exact, case-sensitive validation against a derived digest. No logs, no
    // revealing which part (if any) was wrong.
    final valid = PremiumCodeValidator.validate(entered);

    if (!valid) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Invalid premium code.';
        });
      }
      return;
    }

    await ref.read(premiumProvider.notifier).activate();

    if (!mounted) return;
    Navigator.of(context).pop();
    VoraSnackbar.success(
      context,
      'Ads have been disabled.',
      title: 'Premium activated',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    // Keyboard inset padding so the field stays visible above the keyboard.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTokens.rXxl),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTokens.s6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.3,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.s5),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppTokens.rMd),
                      ),
                      child: Icon(
                        Icons.workspace_premium_rounded,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: AppTokens.s3),
                    Text(
                      'Activate Premium',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.s4),
                Text(
                  'Enter your premium code to enjoy VoraTube ad-free.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppTokens.s5),
                TextField(
                  controller: _controller,
                  obscureText: _obscured,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _activate(),
                  decoration: InputDecoration(
                    labelText: 'Premium code',
                    hintText: 'Enter your premium code',
                    errorText: _error,
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscured = !_obscured),
                      icon: Icon(
                        _obscured
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                      ),
                    ),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.rMd),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.s4),
                PressableScale(
                  onTap: _submitting ? null : _activate,
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [colorScheme.primary, colorScheme.secondary]
                            : [
                                colorScheme.primary,
                                colorScheme.primary.withValues(alpha: 0.85),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(AppTokens.rLg),
                    ),
                    child: _submitting
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: colorScheme.onPrimary,
                            ),
                          )
                        : Text(
                            'Activate',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.onPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

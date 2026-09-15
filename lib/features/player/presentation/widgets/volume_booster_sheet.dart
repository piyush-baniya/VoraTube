import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../settings/presentation/providers/settings_providers.dart';

/// Opens the Volume Boost bottom sheet.
///
/// Boost is +0..+12 dB on top of 100% playback volume, achieved by the native
/// loudness enhancer attached to the audio session (the same path the
/// Settings Preamp uses). 0 dB = off.
Future<void> showVolumeBoosterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _VolumeBoosterSheet(),
  );
}

class _VolumeBoosterSheet extends ConsumerWidget {
  const _VolumeBoosterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final audio = ref.watch(audioSettingsProvider);
    final boostDb = audio.preampDb.clamp(0.0, 12.0);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.rXxl),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle.
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: AppTokens.s3),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(AppTokens.rFull),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.s6,
                AppTokens.s4,
                AppTokens.s4,
                AppTokens.s1,
              ),
              child: Row(
                children: [
                  Text(
                    'Volume Boost',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.s6),
              child: Text(
                boostDb > 0
                    ? 'Boosting above 100% by +${boostDb.toStringAsFixed(1)} dB'
                    : 'No boost — playback at 100% volume.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.s6,
                vertical: AppTokens.s2,
              ),
              child: Slider(
                min: 0,
                max: 12,
                divisions: 24,
                label: '+${boostDb.toStringAsFixed(1)} dB',
                value: boostDb,
                onChanged: (value) {
                  ref
                      .read(audioSettingsProvider.notifier)
                      .setPreampDb(value);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.s5),
              child: Center(
                child: Text(
                  '${boostDb.toStringAsFixed(1)} dB',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: boostDb > 0
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
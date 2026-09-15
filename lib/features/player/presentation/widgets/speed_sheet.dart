import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/audio/audio_effects.dart';
import '../../../settings/presentation/providers/settings_providers.dart';

/// Opens the Playback speed bottom sheet.
///
/// Speed is a 0.25x–2x step selector. Just changing the speed never restarts
/// the track — it sliders over the currently loaded audio with the pitch
/// preserved.
Future<void> showSpeedSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _SpeedSheet(),
  );
}

class _SpeedSheet extends ConsumerWidget {
  const _SpeedSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final audio = ref.watch(audioSettingsProvider);

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
                    'Playback speed',
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
                'Pitch is preserved, so audio never sounds robotic.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: AppTokens.s2),
            for (final speed in kPlaybackSpeeds)
              RadioListTile<double>(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s6,
                ),
                value: speed,
                // Normalize for the wired comparison the framework uses.
                groupValue: audio.playbackSpeed,
                onChanged: (value) {
                  if (value == null) return;
                  ref
                      .read(audioSettingsProvider.notifier)
                      .setPlaybackSpeed(value);
                },
                title: Text('${speed.toStringAsFixed(2)}x'.replaceFirst(
                  '.00',
                  '',
                )),
                secondary: speed == 1.0
                    ? const Icon(Icons.speed_rounded)
                    : null,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.s6,
                AppTokens.s2,
                AppTokens.s6,
                AppTokens.s5,
              ),
              child: Text(
                'Applies instantly to the current song and sticks across '
                'track changes.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
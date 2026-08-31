import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../providers/sleep_timer_provider.dart';

/// The compact presets offered when the timer is not running.
const List<Duration> kSleepTimerPresets = [
  Duration(minutes: 5),
  Duration(minutes: 10),
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(minutes: 45),
  Duration(hours: 1),
];

/// Opens the Sleep Timer bottom sheet.
///
/// The sheet is a pure view over [sleepTimerProvider]. Starting or cancelling
/// a timer routes through the controller, so every entry point (Full Player,
/// song menu, Settings) sees the same canonical timer.
Future<void> showSleepTimerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _SleepTimerSheet(),
  );
}

class _SleepTimerSheet extends ConsumerStatefulWidget {
  const _SleepTimerSheet();

  @override
  ConsumerState<_SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends ConsumerState<_SleepTimerSheet> {
  /// The user's currently selected preset while the timer is inactive.
  Duration _selected = kSleepTimerPresets[1];

  Future<void> _start(Duration d) async {
    await ref.read(sleepTimerProvider.notifier).start(d);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(sleepTimerProvider);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.rXxl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
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
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.s5),
              Row(
                children: [
                  Icon(Icons.bedtime_rounded, color: colorScheme.primary),
                  const SizedBox(width: AppTokens.s3),
                  Text(
                    'Sleep Timer',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.s4),
              if (state.isActive)
                _buildActive(theme, colorScheme, state)
              else
                _buildInactive(theme, colorScheme),
              const SizedBox(height: AppTokens.s4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActive(
    ThemeData theme,
    ColorScheme colorScheme,
    SleepTimerState state,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Playback stops in ${formatSleepTimer(state.remaining)}',
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppTokens.s2),
        Text(
          'The timer keeps running in the background and when the screen is off.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTokens.s6),
        Wrap(
          spacing: AppTokens.s2,
          runSpacing: AppTokens.s2,
          children: [
            for (final d in kSleepTimerPresets)
              ChoiceChip(
                avatar: Icon(
                  Icons.bedtime_rounded,
                  size: 16,
                  color: d == _selected
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
                label: Text(_presetLabel(d)),
                onSelected: (_) => setState(() => _selected = d),
                selected: d == _selected,
              ),
          ],
        ),
        const SizedBox(height: AppTokens.s6),
        FilledButton.icon(
          onPressed: () => _start(_selected),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Restart'),
        ),
        const SizedBox(height: AppTokens.s2),
        OutlinedButton.icon(
          onPressed: () async {
            await ref.read(sleepTimerProvider.notifier).cancel();
            if (mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.bedtime_off_rounded),
          label: const Text('Turn off timer'),
        ),
      ],
    );
  }

  Widget _buildInactive(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Stop playback automatically. Playback pauses when the timer runs '
          'out — your spot is kept.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTokens.s6),
        Wrap(
          spacing: AppTokens.s2,
          runSpacing: AppTokens.s2,
          children: [
            for (final d in kSleepTimerPresets)
              ChoiceChip(
                label: Text(_presetLabel(d)),
                onSelected: (_) => setState(() => _selected = d),
                selected: d == _selected,
              ),
          ],
        ),
        if (_selected > kSleepTimerPresets.last) ...[
          const SizedBox(height: AppTokens.s2),
          Text(
            'Custom: ${formatSleepTimer(_selected)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: AppTokens.s6),
        FilledButton.icon(
          onPressed: () => _start(_selected),
          icon: const Icon(Icons.bedtime_rounded),
          label: const Text('Start timer'),
        ),
      ],
    );
  }

  String _presetLabel(Duration d) {
    if (d.inHours > 0) return '${d.inHours} h';
    return '${d.inMinutes} min';
  }
}

/// One-shot confirmation shown when the timer expires and playback stops.
///
/// Displayed by [HomeShell] only while the app is visible. Dismissing it
/// clears the [SleepTimerPhase.finished] marker so it never reappears by
/// itself.
Future<void> showSleepTimerFinishedDialog(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(Icons.bedtime_rounded, color: colorScheme.primary),
      title: const Text('Sleep Timer Finished'),
      content: const Text(
        'Playback was stopped by your sleep timer. Your spot has been kept.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_tokens.dart';
import '../../../../../shared/widgets/pressable_scale.dart';
import '../../data/mood_engine.dart';

class MoodSelector extends ConsumerWidget {
  const MoodSelector({
    super.key,
    this.selectedMood,
    this.onMoodChanged,
    this.showLabel = true,
  });

  final SongMood? selectedMood;
  final ValueChanged<SongMood?>? onMoodChanged;
  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final moodEngine = MoodEngine();

    final moods = moodEngine.getAllMoods();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel) ...[
          Text(
            'Mood',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTokens.s2),
        ],
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: moods.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: AppTokens.s2),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _MoodChip(
                  label: 'All',
                  emoji: '🎵',
                  isSelected: selectedMood == null,
                  onTap: () => onMoodChanged?.call(null),
                );
              }
              final mood = moods[index - 1];
              return _MoodChip(
                label: mood.label,
                emoji: mood.emoji,
                isSelected: selectedMood == mood,
                onTap: () => onMoodChanged?.call(mood),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MoodChip extends StatelessWidget {
  const _MoodChip({
    required this.label,
    required this.emoji,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String emoji;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s3,
          vertical: AppTokens.s2,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.rMd),
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MoodFilterChip extends ConsumerWidget {
  const MoodFilterChip({
    super.key,
    required this.mood,
    required this.isSelected,
    required this.onTap,
    this.count,
  });

  final SongMood mood;
  final bool isSelected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s3,
          vertical: AppTokens.s1,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.rLg),
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(mood.emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: AppTokens.s1),
            Text(
              mood.label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: AppTokens.s1),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTokens.rSm),
                  color: isSelected
                      ? colorScheme.primary.withValues(alpha: 0.2)
                      : colorScheme.surfaceContainerHighest,
                ),
                child: Text(
                  count.toString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
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

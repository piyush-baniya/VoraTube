import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../shared/widgets/transitions.dart';
import '../../data/mood_engine.dart';
import '../../data/smart_mix_service.dart';
import '../providers/smart_music_providers.dart';
import '../screens/smart_mix_detail_screen.dart';

class MoodStrip extends ConsumerWidget {
  const MoodStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mixesAsync = ref.watch(smartMixesProvider);
    return mixesAsync.when(
      skipLoadingOnRefresh: true,
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (mixes) {
        // Only show if we have at least a small library.
        final anySongs = mixes.any((m) => m.songs.isNotEmpty);
        if (!anySongs) return const SizedBox.shrink();

        final moodEngine = ref.watch(moodEngineProvider);
        final moods = moodEngine.getAllMoods();
        final moodMixes = {for (final mix in mixes) mix.kind: mix};

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(
              title: 'Mood',
              trailing: Text(
                'Pick a vibe',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s4,
                  vertical: AppTokens.s1,
                ),
                itemCount: moods.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppTokens.s2),
                itemBuilder: (context, index) {
                  final mood = moods[index];
                  final mixKind = _moodToMixKind(mood);
                  final mix = mixKind != null ? moodMixes[mixKind] : null;
                  final enabled = mix != null && mix.songs.isNotEmpty;
                  return _MoodCard(
                    mood: mood,
                    count: mix?.songs.length,
                    enabled: enabled,
                    onTap: enabled
                        ? () => Navigator.of(context).push(
                            pushSharedAxis<void>(
                              context,
                              SmartMixDetailScreen(mix: mix),
                            ),
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  SmartMixKind? _moodToMixKind(SongMood mood) {
    switch (mood) {
      case SongMood.chill:
        return SmartMixKind.chillMix;
      case SongMood.energetic:
        return SmartMixKind.energyMix;
      case SongMood.focus:
        return SmartMixKind.focusMix;
      case SongMood.happy:
        // Happy maps to Daily Mix (upbeat variety) when no direct happy mix.
        return SmartMixKind.dailyMix;
      case SongMood.sad:
        return SmartMixKind.throwbackMix;
      case SongMood.romantic:
        return SmartMixKind.favoritesMix;
      case SongMood.unknown:
        return null;
    }
  }
}

class _MoodCard extends StatelessWidget {
  const _MoodCard({
    required this.mood,
    this.count,
    required this.enabled,
    this.onTap,
  });

  final SongMood mood;
  final int? count;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = _moodColor(mood, colorScheme);

    final card = Container(
      width: 112,
      padding: const EdgeInsets.all(AppTokens.s3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.rMd),
        color: enabled
            ? accent.withValues(alpha: 0.14)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(
          color: enabled
              ? accent.withValues(alpha: 0.28)
              : colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(mood.emoji, style: const TextStyle(fontSize: 22)),
          const Spacer(),
          Text(
            mood.label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: enabled
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          if (count != null && enabled)
            Text(
              '$count songs',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            )
          else if (!enabled)
            Text(
              'Add songs',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
    );
    if (!enabled || onTap == null) return Opacity(opacity: 0.7, child: card);
    return PressableScale(onTap: onTap!, child: card);
  }

  Color _moodColor(SongMood mood, ColorScheme scheme) {
    switch (mood) {
      case SongMood.chill:
        return const Color(0xFF14B8A6);
      case SongMood.energetic:
        return const Color(0xFFF59E0B);
      case SongMood.focus:
        return const Color(0xFF3B82F6);
      case SongMood.happy:
        return const Color(0xFFEC4899);
      case SongMood.sad:
        return const Color(0xFF8B5CF6);
      case SongMood.romantic:
        return const Color(0xFFF43F5E);
      case SongMood.unknown:
        return scheme.onSurfaceVariant;
    }
  }
}

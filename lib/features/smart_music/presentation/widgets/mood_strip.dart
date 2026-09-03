import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/widgets/vora_snackbar.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../shared/widgets/transitions.dart';
import '../../../library/presentation/providers/library_view_providers.dart';
import '../../data/mood_engine.dart';
import '../../data/smart_mix_service.dart';
import '../providers/smart_music_providers.dart';
import '../screens/smart_mix_detail_screen.dart';

class MoodStrip extends ConsumerStatefulWidget {
  const MoodStrip({super.key});

  @override
  ConsumerState<MoodStrip> createState() => _MoodStripState();
}

class _MoodStripState extends ConsumerState<MoodStrip> {
  SongMood? _selected;

  @override
  Widget build(BuildContext context) {
    final mixesAsync = ref.watch(smartMixesProvider);
    // Default to "has songs" so we never claim the library is empty while the
    // count is still resolving — a misleading "add songs" is worse than a
    // momentary neutral state.
    final hasSongs = ref.watch(libraryHasSongsProvider).value ?? true;
    return mixesAsync.when(
      skipLoadingOnRefresh: true,
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (mixes) {
        final moodEngine = ref.watch(moodEngineProvider);
        final moods = moodEngine.getAllMoods();
        final moodMixes = {for (final mix in mixes) mix.kind: mix};

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(
              title: 'How are you feeling?',
              trailing: Text(
                'Pick a mood and we\'ll build a mix',
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
                separatorBuilder: (_, _) => const SizedBox(width: AppTokens.s2),
                itemBuilder: (context, index) {
                  final mood = moods[index];
                  final mixKind = _moodToMixKind(mood);
                  final mix = mixKind != null ? moodMixes[mixKind] : null;
                  final enabled = mix != null && mix.songs.isNotEmpty;
                  return _MoodCard(
                    mood: mood,
                    count: mix?.songs.length,
                    enabled: enabled,
                    hasSongs: hasSongs,
                    selected: _selected == mood,
                    onTap: () {
                      setState(() => _selected = mood);
                      if (!enabled) {
                        VoraSnackbar.info(
                          context,
                          hasSongs
                              ? 'No ${mood.label} recommendations available yet.'
                              : 'Add songs to your library to build a ${mood.label} mix.',
                          title: 'Smart Mix',
                        );
                        return;
                      }
                      Navigator.of(context).push(
                        pushSharedAxis<void>(
                          context,
                          SmartMixDetailScreen(mix: mix),
                        ),
                      );
                    },
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
        return SmartMixKind.happyMix;
      case SongMood.sad:
        return SmartMixKind.sadMix;
      case SongMood.romantic:
        return SmartMixKind.romanticMix;
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
    required this.hasSongs,
    required this.selected,
    required this.onTap,
  });

  final SongMood mood;
  final int? count;
  final bool enabled;
  final bool hasSongs;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = AppColors.accent;

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 112,
      padding: const EdgeInsets.all(AppTokens.s3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.rMd),
        color: selected
            ? accent.withValues(alpha: 0.9)
            : enabled
            ? accent.withValues(alpha: 0.14)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(
          color: selected
              ? Colors.transparent
              : enabled
              ? accent.withValues(alpha: 0.28)
              : colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(mood.emoji, style: const TextStyle(fontSize: 20, height: 1.0)),
          Text(
            mood.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.05,
              color: selected
                  ? colorScheme.onPrimary
                  : enabled
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          if (count != null && enabled)
            Text(
              '$count songs',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                height: 1.0,
                color: selected
                    ? colorScheme.onPrimary.withValues(alpha: 0.85)
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            )
          else if (!enabled)
            Text(
              hasSongs ? 'Not available' : 'Add songs',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                height: 1.0,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
    );
    if (!enabled) {
      return Opacity(
        opacity: 0.7,
        child: PressableScale(onTap: onTap, child: card),
      );
    }
    return PressableScale(onTap: onTap, child: card);
  }
}

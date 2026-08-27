import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../library/data/library_models.dart';
import '../../../library/data/library_repository.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../../../library/presentation/providers/library_view_providers.dart';
import '../../../library/presentation/screens/filtered_songs_screen.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../shared/widgets/transitions.dart';
import '../providers/collections_providers.dart';

final listeningStatsProvider = FutureProvider.autoDispose<ListeningStats>((
  ref,
) async {
  ref.watch(libraryRefreshTickProvider);
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.listeningStats();
});

class ListeningInsightsStrip extends ConsumerWidget {
  const ListeningInsightsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(listeningStatsProvider);
    return async.when(
      skipLoadingOnRefresh: true,
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (stats) {
        if (stats.totalSongs == 0) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.s4,
                AppTokens.s2,
                AppTokens.s4,
                AppTokens.s1,
              ),
              child: SectionLabel(
                title: 'Your Listening',
                trailing: Text(
                  stats.hasActivity
                      ? '${stats.totalPlays} plays'
                      : 'Start listening',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s4,
                  vertical: AppTokens.s1,
                ),
                children: [
                  _InsightCard(
                    icon: Icons.library_music_rounded,
                    label: 'Songs',
                    value: '${stats.totalSongs}',
                    subtitle: 'in library',
                    tint: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: AppTokens.s2),
                  _InsightCard(
                    icon: Icons.timer_outlined,
                    label: 'Listened',
                    value: stats.hasActivity
                        ? stats.formattedListeningTime
                        : '—',
                    subtitle: stats.hasActivity ? 'total time' : 'no plays yet',
                    tint: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(width: AppTokens.s2),
                  _InsightCard(
                    icon: Icons.favorite_rounded,
                    label: 'Favorites',
                    value: '${stats.favoritesCount}',
                    subtitle: 'saved',
                    tint: Theme.of(context).colorScheme.tertiary,
                    onTap: stats.favoritesCount > 0
                        ? () => Navigator.of(context).push(
                            pushSharedAxis<void>(
                              context,
                              FilteredSongsScreen.collection(
                                CollectionKind.favorites,
                                'Favorites',
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: AppTokens.s2),
                  _InsightCard(
                    icon: Icons.trending_up_rounded,
                    label: 'Most played',
                    value: '${stats.mostPlayedCount}',
                    subtitle: 'tracks',
                    tint: Theme.of(context).colorScheme.onSurfaceVariant,
                    onTap: stats.mostPlayedCount > 0
                        ? () => Navigator.of(context).push(
                            pushSharedAxis<void>(
                              context,
                              FilteredSongsScreen.collection(
                                CollectionKind.mostPlayed,
                                'Most played',
                              ),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.tint,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final Color tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final card = Container(
      width: 128,
      padding: const EdgeInsets.all(AppTokens.s3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.rMd),
        color: tint.withValues(alpha: 0.10),
        border: Border.all(color: tint.withValues(alpha: 0.18), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tint),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            subtitle,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return PressableScale(onTap: onTap!, child: card);
  }
}

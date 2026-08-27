import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../library/data/library_models.dart';
import '../../../library/data/library_repository.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../../../library/presentation/providers/library_view_providers.dart';
import '../../../library/presentation/screens/filtered_songs_screen.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../shared/widgets/transitions.dart';

final listeningStatsProvider = FutureProvider.autoDispose<ListeningStats>((
  ref,
) async {
  ref.watch(libraryRefreshTickProvider);
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.listeningStats();
});

/// "Your Listening" statistics block.
///
/// Shows a single featured card (your most played song) followed by a compact
/// row of complementary stat cards. The featured card is deliberately distinct
/// from the compact cards so the block reads as a hierarchy rather than four
/// interchangeable tiles.
class ListeningInsightsStrip extends ConsumerWidget {
  const ListeningInsightsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(listeningStatsProvider);
    return async.when(
      skipLoadingOnRefresh: true,
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
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
            // Featured: most played song (or library summary when idle).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
              child: _FeaturedCard(stats: stats),
            ),
            const SizedBox(height: AppTokens.s2),
            // Compact stat chips.
            // Compact stat chips. Height scales with text size so the cards
            // never overflow or clip at larger system font scales.
            SizedBox(
              height: MediaQuery.textScalerOf(context)
                  .scale(96)
                  .clamp(80.0, 160.0),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s4,
                  vertical: AppTokens.s1,
                ),
                children: [
                  _CompactCard(
                    icon: Icons.timer_outlined,
                    label: 'Listened',
                    value: stats.hasActivity
                        ? stats.formattedListeningTime
                        : '—',
                    subtitle: stats.hasActivity ? 'total time' : 'no plays yet',
                    tint: AppColors.accent,
                  ),
                  const SizedBox(width: AppTokens.s2),
                  _CompactCard(
                    icon: Icons.favorite_rounded,
                    label: 'Favorites',
                    value: '${stats.favoritesCount}',
                    subtitle: 'saved',
                    tint: AppColors.accent,
                    onTap: stats.favoritesCount > 0
                        ? () =>
                              _openCollection(context, CollectionKind.favorites)
                        : null,
                  ),
                  const SizedBox(width: AppTokens.s2),
                  _CompactCard(
                    icon: Icons.schedule_rounded,
                    label: 'Recently played',
                    value: '${stats.recentlyPlayedCount}',
                    subtitle: 'tracks',
                    tint: AppColors.accent,
                    onTap: stats.recentlyPlayedCount > 0
                        ? () => _openCollection(
                            context,
                            CollectionKind.recentlyPlayed,
                          )
                        : null,
                  ),
                  const SizedBox(width: AppTokens.s2),
                  _CompactCard(
                    icon: Icons.trending_up_rounded,
                    label: 'Most played',
                    value: '${stats.mostPlayedCount}',
                    subtitle: 'tracks',
                    tint: AppColors.accent,
                    onTap: stats.mostPlayedCount > 0
                        ? () => _openCollection(
                            context,
                            CollectionKind.mostPlayed,
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

  void _openCollection(BuildContext context, CollectionKind kind) {
    final label = switch (kind) {
      CollectionKind.favorites => 'Favorites',
      CollectionKind.recentlyPlayed => 'Recently played',
      CollectionKind.mostPlayed => 'Most played',
      CollectionKind.recentlyAdded => 'Recently added',
    };
    Navigator.of(context).push(
      pushSharedAxis<void>(
        context,
        FilteredSongsScreen.collection(kind, label),
      ),
    );
  }
}

/// A wide, prominent card for the single "most played" stat.
class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.stats});

  final ListeningStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = AppColors.accent;

    final String value;
    final String? artistLine;
    if (stats.hasMostPlayedSong) {
      value = stats.mostPlayedSongTitle!;
      artistLine = stats.hasActivity
          ? stats.mostPlayedSongArtist ?? 'Unknown artist'
          : null;
    } else {
      value = 'Your library';
      artistLine = '${stats.totalSongs} songs';
    }

    return PressableScale(
      onTap: () => _openMostPlayed(context),
      child: Container(
        padding: const EdgeInsets.all(AppTokens.s4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.rLg),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.22),
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            ],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.22), width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppTokens.rMd),
              ),
              child: Icon(Icons.military_tech_rounded, size: 22, color: accent),
            ),
            const SizedBox(width: AppTokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'MOST PLAYED',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (artistLine != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      artistLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (stats.hasMostPlayedSong) ...[
              const SizedBox(width: AppTokens.s2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s2,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppTokens.rFull),
                ),
                child: Text(
                  '${stats.mostPlayedSongCount} plays',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(width: AppTokens.s1),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  void _openMostPlayed(BuildContext context) {
    Navigator.of(context).push(
      pushSharedAxis<void>(
        context,
        FilteredSongsScreen.collection(
          CollectionKind.mostPlayed,
          'Most played',
        ),
      ),
    );
  }
}

/// A compact portrait stat card for the secondary stats.
class _CompactCard extends StatelessWidget {
  const _CompactCard({
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
      width: 120,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return PressableScale(onTap: onTap!, child: card);
  }
}

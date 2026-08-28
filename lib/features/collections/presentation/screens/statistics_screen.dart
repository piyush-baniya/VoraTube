import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../shared/widgets/empty_state.dart' show EmptyState;
import '../../../library/data/library_models.dart';
import '../../../library/data/song_ref_mapper.dart';
import '../../../library/presentation/widgets/song_tile.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../providers/statistics_providers.dart';
import '../widgets/listening_insights.dart';

/// Dedicated statistics screen — a deeper, scrollable view of listening
/// history than the compact "Your Listening" strip on the Library.
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Statistics',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: ref
          .watch(listeningStatsProvider)
          .when(
            skipLoadingOnRefresh: true,
            loading: () => const Center(
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            error: (_, _) => EmptyState(
              icon: Icons.bar_chart_rounded,
              title: 'Could not load statistics',
              message: 'Your data is safe. Try again in a moment.',
              actionLabel: 'Retry',
              onAction: () => ref.invalidate(listeningStatsProvider),
            ),
            data: (stats) {
              if (stats.totalSongs == 0) {
                return const EmptyState(
                  icon: Icons.bar_chart_rounded,
                  title: 'No data yet',
                  message:
                      'Scan or import music, then play a song to see '
                      'your listening statistics.',
                );
              }
              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _SummaryHeader(stats: stats)),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppTokens.s2),
                  ),
                  const _TopPlayedSection(),
                  const _RecentlyPlayedSection(),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppTokens.s8),
                  ),
                ],
              );
            },
          ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.stats});

  final ListeningStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = AppColors.accent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s4,
        AppTokens.s2,
        AppTokens.s4,
        AppTokens.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppTokens.s4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTokens.rXl),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.22),
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                ],
              ),
              border: Border.all(
                color: accent.withValues(alpha: 0.22),
                width: AppTokens.borderHairline,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LISTENING TIME',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: AppTokens.s1),
                Text(
                  stats.formattedListeningTime,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: AppTokens.s3),
                Wrap(
                  spacing: AppTokens.s2,
                  runSpacing: AppTokens.s2,
                  children: [
                    _StatChip(
                      icon: Icons.play_circle_outline_rounded,
                      label: 'Plays',
                      value: '${stats.totalPlays}',
                    ),
                    _StatChip(
                      icon: Icons.library_music_rounded,
                      label: 'Songs',
                      value: '${stats.totalSongs}',
                    ),
                    _StatChip(
                      icon: Icons.favorite_rounded,
                      label: 'Favorites',
                      value: '${stats.favoritesCount}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s3,
        vertical: AppTokens.s2,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppTokens.rFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.accent),
          const SizedBox(width: AppTokens.s1),
          Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopPlayedSection extends ConsumerWidget {
  const _TopPlayedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverToBoxAdapter(
      child: _SongListSection(
        title: 'Top played',
        subtitle: ref
            .watch(listeningStatsProvider)
            .maybeWhen(
              data: (s) => s.hasActivity ? null : 'No plays yet',
              orElse: () => null,
            ),
        provider: topPlayedSongsProvider,
        emptyIcon: Icons.military_tech_rounded,
        emptyMessage: 'Your most played songs will appear here.',
      ),
    );
  }
}

class _RecentlyPlayedSection extends ConsumerWidget {
  const _RecentlyPlayedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverToBoxAdapter(
      child: _SongListSection(
        title: 'Recently played',
        subtitle: null,
        provider: recentlyPlayedSongsProvider,
        emptyIcon: Icons.history_rounded,
        emptyMessage: 'Songs you play will show up here.',
      ),
    );
  }
}

class _SongListSection extends ConsumerWidget {
  const _SongListSection({
    required this.title,
    required this.subtitle,
    required this.provider,
    required this.emptyIcon,
    required this.emptyMessage,
  });

  final String title;
  final String? subtitle;
  final AutoDisposeFutureProvider<List<SongTileData>> provider;
  final IconData emptyIcon;
  final String emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(provider);

    Widget header() {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.s4,
          AppTokens.s3,
          AppTokens.s4,
          AppTokens.s1,
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            const SizedBox(width: AppTokens.s2),
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header(),
        async.when(
          skipLoadingOnRefresh: true,
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          ),
          error: (_, _) => Padding(
            padding: const EdgeInsets.all(AppTokens.s4),
            child: Text(
              subtitle ?? 'Could not load.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          data: (tiles) {
            if (tiles.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s4,
                  vertical: AppTokens.s2,
                ),
                child: Row(
                  children: [
                    Icon(
                      emptyIcon,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppTokens.s2),
                    Expanded(
                      child: Text(
                        emptyMessage,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < tiles.length; i++)
                  SongTile(
                    tile: tiles[i],
                    index: i,
                    onPlay: (_) => _playFrom(context, ref, tiles, i),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _playFrom(
    BuildContext context,
    WidgetRef ref,
    List<SongTileData> tiles,
    int startIndex,
  ) {
    final ctx = playContextFromTiles(tiles, startIndex);
    ref.read(playerProvider).playQueue(ctx.refs, startIndex: ctx.startIndex);
  }
}

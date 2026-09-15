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
import '../../../../shared/widgets/artwork_view.dart';
import '../providers/statistics_providers.dart';
import '../screens/statistics_screen.dart';

final listeningStatsProvider = FutureProvider.autoDispose<ListeningStats>((
  ref,
) async {
  ref.watch(libraryRefreshTickProvider);
  ref.watch(statsRefreshTickProvider);
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.listeningStats();
});

/// "Your Listening" statistics block.
///
/// Shows the section header with the "View Stats" escape into the full
/// statistics screen, followed by the compact stat cards and then a single
/// featured card for your most played song. The featured card is deliberately
/// distinct from the compact cards so the block reads as a hierarchy rather
/// than four interchangeable tiles. A single card (rather than a horizontal
/// strip) keeps "Most Played" focused on the #1 song.
///
/// Rendered **stale-while-refresh**: the block is drawn from the latest
/// committed stats snapshot even while a recompute is in flight. The stats
/// refresh tick bumps on every playback stats flush (play/pause credits, the
/// ~5s listening-time flush during playback), and Riverpod's plain
/// FutureProviders briefly drop their previous value for the frame those
/// recomputes re-run — which made this section blank out and flicker on Home
/// whenever playback state changed. Caching the last committed snapshots here
/// means a reload re-renders the old numbers until the new ones land, never a
/// blank hole.
class ListeningInsightsStrip extends ConsumerStatefulWidget {
  const ListeningInsightsStrip({super.key});

  @override
  ConsumerState<ListeningInsightsStrip> createState() =>
      _ListeningInsightsStripState();
}

class _ListeningInsightsStripState extends ConsumerState<ListeningInsightsStrip> {
  ListeningStats? _stats;
  ListeningBreakdown? _breakdown;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(listeningStatsProvider);
    final breakdownAsync = ref.watch(listeningBreakdownProvider);

    if (async is AsyncData<ListeningStats>) _stats = async.value;
    if (breakdownAsync is AsyncData<ListeningBreakdown>) {
      _breakdown = breakdownAsync.value;
    }

    final stats = _stats;
    if (stats == null || stats.totalSongs == 0) {
      return const SizedBox.shrink();
    }
    final accent = Theme.of(context).colorScheme.primary;
    final breakdown = _breakdown;
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
            trailing: PressableScale(
              onTap: () => Navigator.of(context).push(
                pushSharedAxis<void>(context, const StatisticsScreen()),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View Stats',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Compact stat chips. Height scales with text size so the cards
        // never overflow or clip at larger system font scales.
        SizedBox(
          height: MediaQuery.textScalerOf(context)
              .scale(96)
              .clamp(80.0, 160.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
            child: Row(
              children: [
                Expanded(
                  child: _CompactCard(
                    icon: Icons.play_circle_outline_rounded,
                    label: 'Songs played',
                    value: '${breakdown?.year.plays ?? 0}',
                    tint: accent,
                  ),
                ),
                const SizedBox(width: AppTokens.s2),
                Expanded(
                  child: _CompactCard(
                    icon: Icons.schedule_rounded,
                    label: 'Duration listened',
                    value: formatListeningDuration(
                      breakdown?.year.listenedMs ?? 0,
                    ),
                    tint: accent,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTokens.s2),
        // Featured: most played song (or library summary when idle).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
          child: _FeaturedCard(stats: stats),
        ),
        const SizedBox(height: AppTokens.s3),
      ],
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
    final accent = colorScheme.primary;

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
            SizedBox(
              width: 46,
              height: 46,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTokens.rMd),
                child: ArtworkView(
                  path: stats.mostPlayedSongArtPath,
                  size: 46,
                  radius: AppTokens.rMd,
                  square: true,
                ),
              ),
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

/// A compact stat chip sized to fit two-across in a [Row] via [Expanded].
///
/// Height scales with the system text scale so the chips never overflow or
/// clip at larger font sizes.
class _CompactCard extends StatelessWidget {
  const _CompactCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.s3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.rMd),
        color: tint.withValues(alpha: 0.10),
        border: Border.all(color: tint.withValues(alpha: 0.18), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(width: AppTokens.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
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
          ),
        ],
      ),
    );
  }
}

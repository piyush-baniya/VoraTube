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
                  const _PeakDaySection(),
                  const _WeeklyReportSection(),
                  const _YearlyReportSection(),
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

class _PeakDaySection extends ConsumerWidget {
  const _PeakDaySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peak = ref.watch(listeningBreakdownProvider).valueOrNull?.peakDay;
    return SliverToBoxAdapter(
      child: _SectionCard(
        title: 'Peak Day',
        icon: Icons.local_fire_department_rounded,
        child: peak == null
            ? const _SectionEmpty(
                message: 'Your most active day will appear here.',
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDay(peak.day),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AppTokens.s2),
                  Row(
                    children: [
                      _MiniStat(
                        icon: Icons.schedule_rounded,
                        value: formatListeningDuration(peak.listenedMs),
                        label: 'listened',
                      ),
                      const SizedBox(width: AppTokens.s3),
                      _MiniStat(
                        icon: Icons.play_circle_outline_rounded,
                        value: '${peak.plays}',
                        label: 'plays',
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _WeeklyReportSection extends ConsumerWidget {
  const _WeeklyReportSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdown = ref.watch(listeningBreakdownProvider).valueOrNull;
    return SliverToBoxAdapter(
      child: _ReportBody(
        title: 'This Week',
        icon: Icons.calendar_view_week_rounded,
        period: breakdown?.week,
        bars: breakdown?.weekDaily,
        barLabel: (d) =>
            const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1],
      ),
    );
  }
}

class _YearlyReportSection extends ConsumerWidget {
  const _YearlyReportSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdown = ref.watch(listeningBreakdownProvider).valueOrNull;
    return SliverToBoxAdapter(
      child: _ReportBody(
        title: 'This Year',
        icon: Icons.calendar_month_rounded,
        period: breakdown?.year,
        bars: breakdown?.yearMonthly,
        barLabel: (d) => const [
          'J',
          'F',
          'M',
          'A',
          'M',
          'J',
          'J',
          'A',
          'S',
          'O',
          'N',
          'D',
        ][d.month - 1],
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.title,
    required this.icon,
    required this.period,
    required this.bars,
    required this.barLabel,
  });

  final String title;
  final IconData icon;
  final PeriodStats? period;
  final List<DayListen>? bars;
  final String Function(DateTime day) barLabel;

  @override
  Widget build(BuildContext context) {
    final hasData = period != null && period!.plays > 0;
    return _SectionCard(
      title: title,
      icon: icon,
      child: !hasData
          ? _SectionEmpty(message: 'Nothing listened $title yet.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _MiniStat(
                      icon: Icons.schedule_rounded,
                      value: formatListeningDuration(period!.listenedMs),
                      label: 'listened',
                    ),
                    const SizedBox(width: AppTokens.s3),
                    _MiniStat(
                      icon: Icons.play_circle_outline_rounded,
                      value: '${period!.plays}',
                      label: 'plays',
                    ),
                    const SizedBox(width: AppTokens.s3),
                    _MiniStat(
                      icon: Icons.library_music_rounded,
                      value: '${period!.uniqueSongs}',
                      label: 'songs',
                    ),
                  ],
                ),
                if (period!.topSongs.isNotEmpty) ...[
                  const SizedBox(height: AppTokens.s3),
                  const _SubLabel('Top songs'),
                  const SizedBox(height: AppTokens.s1),
                  ...period!.topSongs.map(
                    (e) => _HistoryRow(
                      title: e.label,
                      subtitle: e.artist,
                      trailing: '${e.count} plays',
                    ),
                  ),
                ],
                if (period!.topArtist != null) ...[
                  const SizedBox(height: AppTokens.s3),
                  const _SubLabel('Top artist'),
                  const SizedBox(height: AppTokens.s1),
                  _HistoryRow(
                    title: period!.topArtist!.label,
                    subtitle: null,
                    trailing: '${period!.topArtist!.count} plays',
                  ),
                ],
                if (bars != null && bars!.any((b) => b.listenedMs > 0)) ...[
                  const SizedBox(height: AppTokens.s3),
                  const _SubLabel('By day'),
                  const SizedBox(height: AppTokens.s2),
                  _BarChart(bars: bars!, barLabel: barLabel),
                ],
              ],
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s4,
        AppTokens.s2,
        AppTokens.s4,
        AppTokens.s2,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTokens.s4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.rXl),
          color: theme.colorScheme.surfaceContainerLowest.withValues(
            alpha: 0.4,
          ),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: AppTokens.borderHairline,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: accent),
                const SizedBox(width: AppTokens.s2),
                Text(
                  title.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.s3),
            child,
          ],
        ),
      ),
    );
  }
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      message,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.accent),
            const SizedBox(width: 4),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SubLabel extends StatelessWidget {
  const _SubLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.title,
    this.subtitle,
    required this.trailing,
  });

  final String title;
  final String? subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.s2),
          Text(
            trailing,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.bars, required this.barLabel});

  final List<DayListen> bars;
  final String Function(DateTime day) barLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.accent;
    final maxMs = bars.fold<int>(
      0,
      (m, b) => b.listenedMs > m ? b.listenedMs : m,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final b in bars)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height:
                        (maxMs == 0
                            ? 0
                            : (b.listenedMs / maxMs).clamp(0.06, 1.0)) *
                        72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: b.listenedMs > 0
                          ? accent.withValues(
                              alpha:
                                  0.35 +
                                  0.65 *
                                      (b.listenedMs / (maxMs == 0 ? 1 : maxMs)),
                            )
                          : theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    barLabel(b.day),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

String _formatDay(DateTime day) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[day.month - 1]} ${day.day}, ${day.year}';
}

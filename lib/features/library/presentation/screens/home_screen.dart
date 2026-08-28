import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/empty_state.dart' show EmptyState;
import '../../../../shared/widgets/artwork_view.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../shared/widgets/transitions.dart';
import '../../../../shared/widgets/scroll_reveal.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/player/player_controller.dart';
import '../../../collections/presentation/widgets/listening_insights.dart';
import '../../../smart_music/presentation/widgets/mood_strip.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../../player/presentation/screens/full_player_screen.dart';
import '../../../library/data/library_models.dart';
import '../../../library/data/song_ref_mapper.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../../../library/presentation/providers/library_view_providers.dart';
import '../../../library/presentation/widgets/song_tile.dart';
import '../../../library/presentation/screens/all_songs_screen.dart';

/// The Home dashboard: a curated, glanceable view over the library —
/// favorites, listening insights, continue listening, mood, and a bounded
/// preview of all songs. Browsing the full collection lives on the Library
/// tab.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.onSeeAllSongs});

  /// Switches to the Library tab to browse all songs. When null, "See All"
  /// pushes the standalone [AllSongsScreen] instead.
  final VoidCallback? onSeeAllSongs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _HomeHeader(),
          Expanded(child: _DashboardBody(onSeeAllSongs: onSeeAllSongs)),
        ],
      ),
    );
  }
}

class _HomeHeader extends ConsumerWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Narrow watch: only rebuilds when the loaded track identity changes, so
    // play/pause, buffering, seek and duration-discovery emissions do not
    // repaint the dashboard header.
    final current = ref.watch(currentTrackProvider);

    final hour = DateTime.now().hour;
    String greeting;
    if (hour < 5) {
      greeting = 'Late night listening';
    } else if (hour < 12) {
      greeting = 'Good morning';
    } else if (hour < 17) {
      greeting = 'Good afternoon';
    } else if (hour < 22) {
      greeting = 'Good evening';
    } else {
      greeting = 'Late night listening';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s5,
        AppTokens.s4,
        AppTokens.s5,
        AppTokens.s2,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: Image.asset(
              'assets/voratube_logo.png',
              fit: BoxFit.contain,
              // The real logo is a full-colour asset; tinting it with the
              // theme's onSurface would flatten it to a monochrome silhouette
              // and lose the brand mark. `contain` keeps the original aspect
              // ratio, so the mark never distorts on any screen width.
              errorBuilder: (_, _, _) => Icon(
                Icons.music_note_rounded,
                size: 24,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: AppTokens.s1),
                Text(
                  'Home',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
              ],
            ),
          ),
          if (current != null) ...[
            const SizedBox(width: AppTokens.s3),
            _NowPlayingBadge(current: current),
          ],
        ],
      ),
    );
  }
}

class _NowPlayingBadge extends StatelessWidget {
  const _NowPlayingBadge({required this.current});

  final SongRef current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.accent;

    return PressableScale(
      onTap: () =>
          Navigator.of(context)
              .push(pushHero<void>(context, const FullPlayerScreen())),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s3,
          vertical: AppTokens.s2,
        ),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTokens.rFull),
          border: Border.all(
            color: accent.withValues(alpha: 0.2),
            width: AppTokens.borderHairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note_rounded, size: 14, color: accent),
            const SizedBox(width: AppTokens.s1),
            Text(
              'Now Playing',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({this.onSeeAllSongs});

  final VoidCallback? onSeeAllSongs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeSongs = ref.watch(homeSongsProvider);
    // Narrow watch so the whole dashboard body does not rebuild on coarse
    // playback emissions (play/pause, buffering, seeks). It only re-renders
    // when the loaded track identity changes.
    final current = ref.watch(currentTrackProvider);
    final scanState = ref.watch(scanControllerProvider);
    final isScanning = scanState is ScanRunning;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (current != null)
          SliverToBoxAdapter(child: _ContinueListeningHero(current: current))
        else
          SliverToBoxAdapter(child: _EmptyStateHero()),

        SliverToBoxAdapter(child: ListeningInsightsStrip()),

        SliverToBoxAdapter(child: MoodStrip()),

        SliverToBoxAdapter(
          child: _SectionHeader(
            title: 'All Songs',
            actionLabel: 'See All',
            onAction:
                onSeeAllSongs ??
                () => Navigator.of(
                  context,
                ).push(pushSharedAxis<void>(context, const AllSongsScreen())),
          ),
        ),

        AsyncValueSwitcher<List<SongTileData>>(
          value: homeSongs,
          loading: SliverFixedExtentList(
            itemExtent: 84,
            delegate: SliverChildBuilderDelegate(
              (_, index) => const _SkeletonSongTile(),
              childCount: 10,
            ),
          ),
          errorBuilder: (e, _) => SliverToBoxAdapter(
            child: _HomeError(retry: () => ref.invalidate(homeSongsProvider)),
          ),
          data: (tiles) {
            if (tiles.isEmpty) {
              return SliverToBoxAdapter(
                // Home's All Songs preview is always the whole library (a
                // bounded peek), so an empty preview genuinely means the
                // device has no music yet — unless a scan is still running, in
                // which case we surface a progress state instead of a dead end.
                child: isScanning
                    ? const _ScanningState()
                    : EmptyState(
                        icon: Icons.library_music_rounded,
                        title: 'Nothing here yet',
                        message: 'Scan or import music to fill your library.',
                        actionLabel: 'Scan Library',
                        onAction: () => ref
                            .read(scanControllerProvider.notifier)
                            .startScan(),
                      ),
              );
            }
            return SliverList.separated(
              itemCount: tiles.length,
              separatorBuilder: (_, i) => i == tiles.length - 1
                  ? const SizedBox.shrink()
                  : Divider(
                      height: AppTokens.borderHairline,
                      thickness: AppTokens.borderHairline,
                      indent: AppTokens.artworkLg + AppTokens.s3 + AppTokens.s4,
                      endIndent: AppTokens.s4,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
              itemBuilder: (context, index) {
                return ScrollReveal(
                  child: SongTile(
                    key: ValueKey(tiles[index].song.id),
                    tile: tiles[index],
                    index: index,
                    onPlay: (_) => _playFrom(context, ref, tiles, index),
                  ),
                );
              },
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

class _ContinueListeningHero extends ConsumerWidget {
  const _ContinueListeningHero({required this.current});

  final SongRef current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = AppColors.accent;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTokens.s4,
        AppTokens.s3,
        AppTokens.s4,
        AppTokens.s4,
      ),
      padding: const EdgeInsets.all(AppTokens.s4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.rXl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.18),
            accent.withValues(alpha: 0.06),
            colorScheme.surface,
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
        border: Border.all(
          color: accent.withValues(alpha: 0.2),
          width: AppTokens.borderHairline,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.1),
            blurRadius: 24,
            offset: const Offset(0, 8),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTokens.rLg),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                  spreadRadius: -2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTokens.rLg),
              child: ArtworkView(
                path: current.artPath,
                size: 112,
                radius: AppTokens.rLg,
                showShadow: true,
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Continue Listening',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: AppTokens.s1),
                Text(
                  current.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                if (current.artist != null) ...[
                  const SizedBox(height: AppTokens.s1),
                  Text(
                    current.artist!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: AppTokens.s3),
                PressableScale(
                  onTap: () => Navigator.of(context)
                      .push(pushHero<void>(context, const FullPlayerScreen())),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.s5,
                      vertical: AppTokens.s2,
                    ),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(AppTokens.rFull),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_arrow_rounded,
                          size: 18,
                          color: colorScheme.onPrimary,
                        ),
                        const SizedBox(width: AppTokens.s2),
                        Text(
                          'Play',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
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

class _EmptyStateHero extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = AppColors.accent;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTokens.s4,
        AppTokens.s3,
        AppTokens.s4,
        AppTokens.s4,
      ),
      padding: const EdgeInsets.all(AppTokens.s5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.rXl),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: AppTokens.borderHairline,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.12),
                  accent.withValues(alpha: 0.04),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
            child: Center(
              child: Icon(
                Icons.music_note_rounded,
                size: 40,
                color: accent.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(height: AppTokens.s3),
          Text(
            'Start Listening',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppTokens.s1),
          Text(
            'Your music library is ready. Scan or import to begin.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.s4),
          PressableScale(
            onTap: () => ref.read(scanControllerProvider.notifier).startScan(),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.s5,
                vertical: AppTokens.s2,
              ),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(AppTokens.rFull),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.folder_open_rounded,
                    size: 18,
                    color: colorScheme.onPrimary,
                  ),
                  const SizedBox(width: AppTokens.s2),
                  Text(
                    'Scan Library',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown in the All Songs preview slot while a scan is running and the library
/// is still empty. Surfaces the requested "Please wait, fetching songs..." copy
/// with a live progress indicator that tracks the actual scan state.
class _ScanningState extends ConsumerWidget {
  const _ScanningState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = AppColors.accent;
    final scanState = ref.watch(scanControllerProvider);
    final running = scanState is ScanRunning;
    final processed = running ? scanState.processedCount : 0;
    final totalHint = running ? scanState.totalHint : null;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s4,
        vertical: AppTokens.s6,
      ),
      child: Column(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 3, color: accent),
          ),
          const SizedBox(height: AppTokens.s4),
          Text(
            'Please wait, fetching songs...',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTokens.s1),
          Text(
            totalHint != null
                ? 'Scanned $processed of $totalHint'
                : 'Scanned $processed songs so far',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.accent;

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
              color: accent,
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
                color: accent,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionLabel!,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeError extends StatelessWidget {
  const _HomeError({required this.retry});

  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline_rounded,
      title: 'Could not load the library',
      message: 'Your music is safe. Try again in a moment.',
      actionLabel: 'Retry',
      onAction: retry,
    );
  }
}

class _SkeletonSongTile extends StatelessWidget {
  const _SkeletonSongTile();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = AppColors.accent;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s4,
        vertical: AppTokens.s1,
      ),
      child: Row(
        children: [
          Container(
            width: AppTokens.artworkLg,
            height: AppTokens.artworkLg,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTokens.rSm),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.12),
                  accent.withValues(alpha: 0.04),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
                        colorScheme.onSurfaceVariant.withValues(alpha: 0.06),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 80,
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
                        colorScheme.onSurfaceVariant.withValues(alpha: 0.06),
                      ],
                    ),
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

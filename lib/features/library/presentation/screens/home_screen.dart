import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/empty_state.dart' show EmptyState;
import '../../../../shared/widgets/artwork_view.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../shared/widgets/transitions.dart';
import '../../../../shared/widgets/scroll_reveal.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/player/player_controller.dart';
import '../../../../core/ui_customization/ui_component_registry.dart';
import '../../../../core/ui_customization/ui_layout.dart';
import '../../../ads/banner_ad_widget.dart';
import '../../../collections/presentation/widgets/listening_insights.dart';
import '../../../customization/presentation/providers/layout_providers.dart';
import '../../../customization/presentation/widgets/editable_layout_frame.dart';
import '../../../customization/presentation/widgets/layout_edit_scope.dart';
import '../../../playlists/presentation/widgets/home_playlist_strip.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../../player/presentation/screens/full_player_screen.dart';
import '../../../library/data/library_models.dart';
import '../../../library/data/library_repository.dart';
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
    // During live customization the unshelled screen is shown: the header and
    // ad are inert so only the editor controls respond.
    final editing = LayoutEditScope.isEditing(context);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IgnorePointer(
            ignoring: editing,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _HomeHeader(),
                // A single, small, unobtrusive banner that never overlaps
                // playback controls. It sits under the Home header and
                // collapses to nothing when Premium is active or the ad fails
                // to load.
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppTokens.s5),
                  child: VoraTubeBannerAd(),
                ),
              ],
            ),
          ),
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
            const SizedBox(width: AppTokens.s1),
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
    final accent = theme.colorScheme.primary;

    return PressableScale(
      // The full player is immersive: push it on the root navigator so it
      // covers the whole shell including the MiniPlayer and bottom bar.
      onTap: () => Navigator.of(
        context,
        rootNavigator: true,
      ).push(pushHero<void>(context, const FullPlayerScreen())),
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
    // The user's saved layout drives order, visibility, size and style. A
    // missing/loading profile resolves to the default arrangement, so Home
    // renders the pre-customization UI until (or unless) a profile exists.
    final variant = layoutVariantForSize(MediaQuery.sizeOf(context));
    final layout = ref.watch(homeScreenLayoutProvider(variant));
    // Narrow watch so the whole dashboard body does not rebuild on coarse
    // playback emissions (play/pause, buffering, seeks). It only re-renders
    // when the loaded track identity changes.
    final current = ref.watch(currentTrackProvider);
    final scanState = ref.watch(scanControllerProvider);
    final isScanning = scanState is ScanRunning;

    final slivers = <Widget>[];
    for (final component in layout.components) {
      if (!component.visible) continue;
      slivers.addAll(
        _sectionSlivers(context, ref, component, current, isScanning),
      );
    }

    // In a customization session the scroll view becomes a plain list of
    // framed panels so each section is directly draggable/resizable.
    if (LayoutEditScope.isEditing(context)) {
      final panels = <Widget>[];
      for (var i = 0; i < layout.components.length; i++) {
        final component = layout.components[i];
        if (!component.visible) continue;
        final definition = homeComponentRegistry.definitionFor(component.id);
        if (definition == null) continue;
        final child = _editPanel(context, ref, component, current, isScanning);
        if (child == null) continue;
        panels.add(
          EditableLayoutFrame(
            componentId: component.id,
            index: i,
            itemCount: layout.components.length,
            definition: definition,
            child: child,
          ),
        );
      }
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: panels,
      );
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: slivers,
    );
  }

  /// Non-sliver panel for one section during live customization.
  Widget? _editPanel(
    BuildContext context,
    WidgetRef ref,
    ComponentLayout component,
    SongRef? current,
    bool isScanning,
  ) {
    switch (component.id) {
      case 'home.continueListening':
        return current != null
            ? _ContinueListeningHero(
                current: current,
                size: component.size,
                styleId: component.styleId,
              )
            : _EmptyStateHero();
      case 'home.listeningInsights':
        return ListeningInsightsStrip(
          size: component.size,
          styleId: component.styleId,
        );
      case 'home.playlists':
        return HomePlaylistStrip(
          size: component.size,
          styleId: component.styleId,
        );
      case 'home.allSongs':
        return _allSongsEditPanel(context, ref, component, isScanning);
      default:
        return null;
    }
  }

  Widget _allSongsEditPanel(
    BuildContext context,
    WidgetRef ref,
    ComponentLayout component,
    bool isScanning,
  ) {
    final limit = homePreviewLimitFor(component.size);
    final homeSongs = ref.watch(homeSongsPreviewProvider(limit));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(title: 'All Songs'),
        homeSongs.when(
          loading: () => Column(
            children: [
              for (var i = 0; i < limit; i++) const _SkeletonSongTile(),
            ],
          ),
          error: (e, _) => _HomeError(
            retry: () => ref.invalidate(homeSongsPreviewProvider(limit)),
          ),
          data: (tiles) {
            if (tiles.isEmpty) {
              return isScanning
                  ? const _ScanningState()
                  : const EmptyState(
                      icon: Icons.library_music_rounded,
                      title: 'No Music',
                      message: 'Add music to your device to get started.',
                    );
            }
            return Column(
              children: [
                for (var i = 0; i < tiles.length; i++)
                  SongTile(
                    key: ValueKey(tiles[i].song.id),
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

  /// Expands one configured component into its slivers, in the saved order.
  List<Widget> _sectionSlivers(
    BuildContext context,
    WidgetRef ref,
    ComponentLayout component,
    SongRef? current,
    bool isScanning,
  ) {
    switch (component.id) {
      case 'home.continueListening':
        return [
          SliverToBoxAdapter(
            child: current != null
                ? _ContinueListeningHero(
                    current: current,
                    size: component.size,
                    styleId: component.styleId,
                  )
                : _EmptyStateHero(),
          ),
        ];
      case 'home.listeningInsights':
        return [
          SliverToBoxAdapter(
            child: ListeningInsightsStrip(
              size: component.size,
              styleId: component.styleId,
            ),
          ),
        ];
      case 'home.playlists':
        return [
          SliverToBoxAdapter(
            child: HomePlaylistStrip(
              size: component.size,
              styleId: component.styleId,
            ),
          ),
        ];
      case 'home.allSongs':
        return _allSongsSlivers(context, ref, component, isScanning);
      default:
        return const [];
    }
  }

  List<Widget> _allSongsSlivers(
    BuildContext context,
    WidgetRef ref,
    ComponentLayout component,
    bool isScanning,
  ) {
    final limit = homePreviewLimitFor(component.size);
    final homeSongs = ref.watch(homeSongsPreviewProvider(limit));
    return [
      SliverToBoxAdapter(
        child: _SectionHeader(
          title: 'All Songs',
          actionLabel: 'See All',
          onAction:
              onSeeAllSongs ??
              () => Navigator.of(context)
                  .push(pushSharedAxis<void>(context, const AllSongsScreen())),
        ),
      ),
      AsyncValueSwitcher<List<SongTileData>>(
        value: homeSongs,
        loading: SliverFixedExtentList(
          itemExtent: 84,
          delegate: SliverChildBuilderDelegate(
            (_, index) => const _SkeletonSongTile(),
            childCount: limit,
          ),
        ),
        errorBuilder: (e, _) => SliverToBoxAdapter(
          child: _HomeError(
            retry: () => ref.invalidate(homeSongsPreviewProvider(limit)),
          ),
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
                  : const EmptyState(
                      icon: Icons.library_music_rounded,
                      title: 'No Music',
                      message: 'Add music to your device to get started.',
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
                // Same scroll-jank rationale as All Songs: only the initial
                // screenful animates in.
                enabled: index < scrollRevealInitialItems,
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
    ];
  }

  Future<void> _playFrom(
    BuildContext context,
    WidgetRef ref,
    List<SongTileData> tiles,
    int startIndex,
  ) async {
    // Home's "All Songs" preview is only a bounded peek (see [homeSongsLimit]).
    // Playback must use the whole library, not just the visible rows, so the
    // tapped song stays current while every library song follows it.
    final tappedId = tiles[startIndex].song.id;
    final repository = ref.read(libraryRepositoryProvider);
    final counts = await repository.currentCounts();
    final page = await repository.songsPage(
      limit: counts.songs,
      offset: 0,
      sort: SongSort.recentlyAdded,
      favoritesOnly: false,
    );
    final full = page.songs;
    if (full.isEmpty) {
      return;
    }
    var start = full.indexWhere((t) => t.song.id == tappedId);
    if (start < 0) {
      start = 0;
    }
    final ctx = playContextFromTiles(full, start);
    ref.read(playerProvider).playQueue(ctx.refs, startIndex: ctx.startIndex);
  }
}

class _ContinueListeningHero extends ConsumerWidget {
  const _ContinueListeningHero({
    required this.current,
    this.size = ComponentSize.medium,
    this.styleId,
  });

  final SongRef current;
  final ComponentSize size;
  final String? styleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = theme.colorScheme.primary;
    final isPlaying = ref.watch(playbackIsPlayingProvider);
    final compact = styleId == 'compact';
    final artworkSize = switch (size) {
      ComponentSize.small => 72.0,
      ComponentSize.medium => 112.0,
      ComponentSize.large => 136.0,
    };
    // The compact style trades the artist line for a slimmer card; the size
    // preset never pushes the artwork past what a compact row can hold.
    final effectiveArtwork = compact && artworkSize > 88 ? 88.0 : artworkSize;
    final showArtist = !compact && current.artist != null;

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
          // Artwork opens the full player; the resumed song is whoever the
          // player restored, so the deep link carries the same track.
          GestureDetector(
            onTap: () => _openFullPlayer(context),
            child: Container(
              width: effectiveArtwork,
              height: effectiveArtwork,
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
                  size: effectiveArtwork,
                  radius: AppTokens.rLg,
                  showShadow: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => _openFullPlayer(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                      if (showArtist) ...[
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
                    ],
                  ),
                ),
                const SizedBox(height: AppTokens.s3),
                PressableScale(
                  // Resume the restored queue under the player's own state:
                  // this toggles the engine so the saved track/position plays
                  // immediately (MiniPlayer and full player follow the same
                  // authoritative snapshot).
                  onTap: () => ref.read(playerProvider).togglePlay(),
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
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 18,
                          color: colorScheme.onPrimary,
                        ),
                        const SizedBox(width: AppTokens.s2),
                        Text(
                          isPlaying ? 'Pause' : 'Play',
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

  void _openFullPlayer(BuildContext context) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(pushHero<void>(context, const FullPlayerScreen()));
  }
}

class _EmptyStateHero extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = theme.colorScheme.primary;

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
            'Select any track from your library to begin playback.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.s4),
          Consumer(
            builder: (context, ref, _) {
              final tiles =
                  ref.watch(homeSongsProvider).valueOrNull ?? const [];
              if (tiles.isEmpty) return const SizedBox.shrink();
              return PressableScale(
                onTap: () => startPlaybackOfWholeLibrary(ref),
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
                        size: 20,
                        color: colorScheme.onPrimary,
                      ),
                      const SizedBox(width: AppTokens.s2),
                      Text(
                        'Play Music',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
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
    final accent = theme.colorScheme.primary;
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
    final accent = theme.colorScheme.primary;

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
    final accent = theme.colorScheme.primary;

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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/empty_state.dart'
    show EmptyState, ScreenHeader, SectionHeader;
import '../../../../shared/widgets/artwork_view.dart';
import '../../../../shared/widgets/skeleton_list.dart';
import '../../../../shared/widgets/transitions.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../collections/presentation/providers/collections_providers.dart';
import '../../../collections/presentation/widgets/listening_insights.dart';
import '../../../smart_music/presentation/widgets/mood_strip.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../../player/presentation/screens/full_player_screen.dart';
import '../../../../../core/player/player_controller.dart';
import '../../data/library_models.dart';
import '../../data/song_ref_mapper.dart';
import '../providers/library_view_providers.dart';
import '../widgets/library_tiles.dart';
import '../widgets/section_selector.dart' hide SectionLabel;
import '../widgets/song_tile.dart';
import '../widgets/sort_sheet.dart';
import '../../data/library_repository.dart';
import '../providers/library_providers.dart';
import 'all_songs_screen.dart';
import 'filtered_songs_screen.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(librarySectionProvider);
    final isSongs = section == LibrarySection.songs;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _LibraryHeader(),
          SectionSelector(
            selected: section,
            onChanged: (s) =>
                ref.read(librarySectionProvider.notifier).state = s,
          ),
          if (isSongs) const _SongsToolbar(),
          Expanded(
            child: FadeThroughSwitcher(
              child: switch (section) {
                LibrarySection.songs => const _SongsView(),
                LibrarySection.albums => const _AlbumsView(),
                LibrarySection.artists => const _ArtistsView(),
                LibrarySection.genres => const _GenresView(),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryHeader extends ConsumerWidget {
  const _LibraryHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final snapshot = ref.watch(playbackStateProvider);

    // Time-aware greeting
    final hour = DateTime.now().hour;
    String greeting;
    if (hour < 5)
      greeting = 'Late night listening';
    else if (hour < 12)
      greeting = 'Good morning';
    else if (hour < 17)
      greeting = 'Good afternoon';
    else if (hour < 22)
      greeting = 'Good evening';
    else
      greeting = 'Late night listening';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s5,
        AppTokens.s4,
        AppTokens.s5,
        AppTokens.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand logo + greeting
          Row(
            children: [
              Image.asset(
                'assets/voratube_logo.png',
                height: 32,
                color: colorScheme.onSurface,
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
                      'Library',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ],
                ),
              ),
              if (snapshot != null && snapshot.hasTrack) ...[
                const SizedBox(width: AppTokens.s3),
                _NowPlayingBadge(current: snapshot.current!),
              ],
            ],
          ),
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
    final colorScheme = theme.colorScheme;
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

class _SongsToolbar extends ConsumerWidget {
  const _SongsToolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = AppColors.accent;
    final favoritesOnly = ref.watch(favoritesOnlyProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s4,
        AppTokens.s1,
        AppTokens.s4,
        AppTokens.s1,
      ),
      child: Row(
        children: [
          // Favorites filter chip
          FilterChip(
            label: const Text('Favorites'),
            selected: favoritesOnly,
            showCheckmark: false,
            avatar: Icon(
              favoritesOnly
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              size: 16,
              color: favoritesOnly ? accent : colorScheme.onSurfaceVariant,
            ),
            selectedColor: accent.withValues(alpha: 0.12),
            checkmarkColor: accent,
            backgroundColor: colorScheme.surfaceContainerHigh,
            side: BorderSide(
              color: favoritesOnly ? accent : colorScheme.outlineVariant,
              width: favoritesOnly ? 1.5 : AppTokens.borderHairline,
            ),
            labelStyle: theme.textTheme.labelMedium?.copyWith(
              color: favoritesOnly ? accent : colorScheme.onSurfaceVariant,
              fontWeight: favoritesOnly ? FontWeight.w600 : FontWeight.w500,
            ),
            onSelected: (v) =>
                ref.read(favoritesOnlyProvider.notifier).state = v,
          ),
          const Spacer(),
          // Sort button
          PressableScale(
            onTap: () => showSortSheet(context, ref),
            child: Container(
              padding: const EdgeInsets.all(AppTokens.s2),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppTokens.rMd),
              ),
              child: Icon(
                Icons.swap_vert_rounded,
                size: 22,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SongsView extends ConsumerWidget {
  const _SongsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Bounded Home query — at most 10 preview tiles, never the whole library.
    final homeSongs = ref.watch(homeSongsProvider);
    final snapshot = ref.watch(playbackStateProvider);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // Favorites — a single tap opens the full Favorites collection.
        SliverToBoxAdapter(child: _FavoritesCard()),

        // Your Listening
        SliverToBoxAdapter(child: ListeningInsightsStrip()),

        // Continue Listening
        if (snapshot != null && snapshot.hasTrack)
          SliverToBoxAdapter(
            child: _ContinueListeningHero(current: snapshot.current!),
          )
        else
          SliverToBoxAdapter(child: _EmptyStateHero()),

        // How are you feeling?
        SliverToBoxAdapter(child: MoodStrip()),

        // All Songs (bounded preview, full collection behind See All)
        SliverToBoxAdapter(
          child: _SectionHeader(
            title: 'All Songs',
            actionLabel: 'See All',
            onAction: () => Navigator.of(context)
                .push(pushSharedAxis<void>(context, const AllSongsScreen())),
          ),
        ),

        // Song preview list
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
            child: _LibraryError(
              retry: () => ref.invalidate(homeSongsProvider),
            ),
          ),
          data: (tiles) {
            if (tiles.isEmpty) {
              final favoritesOnly = ref.watch(favoritesOnlyProvider);
              return SliverToBoxAdapter(
                child: EmptyState(
                  icon: favoritesOnly
                      ? Icons.favorite_border_rounded
                      : Icons.library_music_rounded,
                  title: favoritesOnly
                      ? 'No favorites yet'
                      : 'Nothing here yet',
                  message: favoritesOnly
                      ? 'Tap the heart on any song to keep it close.'
                      : 'Scan or import music to fill your library.',
                  actionLabel: favoritesOnly ? null : 'Scan Library',
                  onAction: favoritesOnly
                      ? null
                      : () => ref
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
                return SongTile(
                  tile: tiles[index],
                  index: index,
                  onPlay: (_) => _playFrom(context, ref, tiles, index),
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

// Continue Listening Hero
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
          // Artwork with subtle glow
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
          // Metadata and controls
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
                // Play button
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

// Empty State Hero
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

// Section Header
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

/// Home "Favorites" entry — a compact tappable card that opens the existing
/// Favorites collection screen. Shows the real count; hidden while the count
/// is still resolving so it never flashes a wrong number.
class _FavoritesCard extends ConsumerWidget {
  const _FavoritesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = AppColors.accent;
    final summaries = ref.watch(collectionSummariesProvider);

    return summaries.maybeWhen(
      skipLoadingOnRefresh: true,
      data: (list) {
        final favorites = list.firstWhere(
          (s) => s.kind == CollectionKind.favorites,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.s4,
            AppTokens.s3,
            AppTokens.s4,
            AppTokens.s1,
          ),
          child: PressableScale(
            onTap: () => Navigator.of(context).push(
              pushSharedAxis<void>(
                context,
                FilteredSongsScreen.collection(
                  CollectionKind.favorites,
                  'Favorites',
                ),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.s4,
                vertical: AppTokens.s3,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTokens.rLg),
                color: accent.withValues(alpha: 0.10),
                border: Border.all(
                  color: accent.withValues(alpha: 0.22),
                  width: AppTokens.borderHairline,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.favorite_rounded, size: 22, color: accent),
                  const SizedBox(width: AppTokens.s3),
                  Expanded(
                    child: Text(
                      'Favorites',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${favorites.count} songs',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppTokens.s1),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _AlbumsView extends ConsumerWidget {
  const _AlbumsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(albumsOverviewProvider);
    return async.when(
      loading: () => const SkeletonGrid(columns: 2, rows: 4, aspectRatio: 0.85),
      error: (e, _) =>
          _LibraryError(retry: () => ref.invalidate(albumsOverviewProvider)),
      data: (albums) {
        if (albums.isEmpty) {
          return const EmptyState(
            icon: Icons.album_rounded,
            title: 'No albums yet',
            message: 'Albums appear once your library has music.',
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(AppTokens.s3),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisSpacing: AppTokens.s2,
            crossAxisSpacing: AppTokens.s2,
            childAspectRatio: 0.82,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            return AlbumCard(
              album: album,
              onTap: () => Navigator.of(context).push(
                pushSharedAxis<void>(context, FilteredSongsScreen.album(album)),
              ),
            );
          },
        );
      },
    );
  }
}

class _ArtistsView extends ConsumerWidget {
  const _ArtistsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(artistsOverviewProvider);
    return async.when(
      loading: () => const SkeletonList(rows: 8, type: SkeletonType.artist),
      error: (e, _) =>
          _LibraryError(retry: () => ref.invalidate(artistsOverviewProvider)),
      data: (artists) {
        if (artists.isEmpty) {
          return const EmptyState(
            icon: Icons.person_off_rounded,
            title: 'No artists yet',
            message: 'Artists appear once your library has music.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s4,
            vertical: AppTokens.s3,
          ),
          itemCount: artists.length,
          separatorBuilder: (_, _) => Divider(
            height: AppTokens.borderHairline,
            thickness: AppTokens.borderHairline,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          itemBuilder: (context, index) {
            final artist = artists[index];
            return ArtistTile(
              artist: artist,
              onTap: () => Navigator.of(context).push(
                pushSharedAxis<void>(
                  context,
                  FilteredSongsScreen.artist(artist),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _GenresView extends ConsumerWidget {
  const _GenresView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(genresOverviewProvider);
    return async.when(
      loading: () => const SkeletonList(rows: 8, type: SkeletonType.song),
      error: (e, _) =>
          _LibraryError(retry: () => ref.invalidate(genresOverviewProvider)),
      data: (genres) {
        if (genres.isEmpty) {
          return const EmptyState(
            icon: Icons.style_rounded,
            title: 'No genre information',
            message:
                'Genres come from your files\u2019 tags. Many files '
                'simply don\u2019t carry them.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s4,
            vertical: AppTokens.s3,
          ),
          itemCount: genres.length,
          separatorBuilder: (_, _) => Divider(
            height: AppTokens.borderHairline,
            thickness: AppTokens.borderHairline,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          itemBuilder: (context, index) =>
              GenreTile(genre: genres[index], onTap: () {}),
        );
      },
    );
  }
}

class _LibraryError extends StatelessWidget {
  const _LibraryError({required this.retry});

  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return EmptyState(
      icon: Icons.error_outline_rounded,
      title: 'Could not load the library',
      message: 'Your music is safe. Try again in a moment.',
      actionLabel: 'Retry',
      onAction: retry,
    );
  }
}

// Skeleton song tile for loading state in CustomScrollView
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

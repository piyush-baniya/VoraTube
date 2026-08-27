import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/empty_state.dart'
    show EmptyState, ScreenHeader, SectionHeader;
import '../../../../shared/widgets/skeleton_list.dart';
import '../../../../shared/widgets/transitions.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../collections/presentation/widgets/collections_strip.dart';
import '../../../collections/presentation/widgets/listening_insights.dart';
import '../../../smart_music/presentation/widgets/mood_strip.dart';
import '../../../smart_music/presentation/widgets/smart_mix_strip.dart';
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
import '../providers/library_providers.dart';
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
          // Greeting + now playing indicator
          Row(
            children: [
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
          color: colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTokens.rFull),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.2),
            width: AppTokens.borderHairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_note_rounded,
              size: 14,
              color: colorScheme.primary,
            ),
            const SizedBox(width: AppTokens.s1),
            Text(
              'Now Playing',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
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
              color: favoritesOnly
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            selectedColor: colorScheme.primary.withValues(alpha: 0.12),
            checkmarkColor: colorScheme.primary,
            backgroundColor: colorScheme.surfaceContainerHigh,
            side: BorderSide(
              color: favoritesOnly
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: favoritesOnly ? 1.5 : AppTokens.borderHairline,
            ),
            labelStyle: theme.textTheme.labelMedium?.copyWith(
              color: favoritesOnly
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
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

class _SongsView extends ConsumerStatefulWidget {
  const _SongsView();

  @override
  ConsumerState<_SongsView> createState() => _SongsViewState();
}

class _SongsViewState extends ConsumerState<_SongsView> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (_controller.position.extentAfter < 600) {
      ref.read(pagedSongsProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncValue = ref.watch(pagedSongsProvider);

    return Column(
      children: [
        const ListeningInsightsStrip(),
        const CollectionsStrip(),
        const MoodStrip(),
        const SmartMixStrip(),
        Expanded(
          child: AsyncValueSwitcher<List<SongTileData>>(
            value: asyncValue,
            loading: const SkeletonList(rows: 10, type: SkeletonType.song),
            errorBuilder: (e, _) =>
                _LibraryError(retry: () => ref.invalidate(pagedSongsProvider)),
            data: (tiles) {
              if (tiles.isEmpty) {
                final favoritesOnly = ref.watch(favoritesOnlyProvider);
                return EmptyState(
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
                );
              }
              return ListView.separated(
                controller: _controller,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: AppTokens.s8),
                itemCount:
                    tiles.length +
                    (ref.read(pagedSongsProvider.notifier).hasMore ? 1 : 0),
                separatorBuilder: (_, i) => i == tiles.length - 1
                    ? const SizedBox.shrink()
                    : Divider(
                        height: AppTokens.borderHairline,
                        thickness: AppTokens.borderHairline,
                        indent:
                            AppTokens.artworkLg + AppTokens.s3 + AppTokens.s4,
                        endIndent: AppTokens.s4,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                itemBuilder: (context, index) {
                  if (index >= tiles.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      ),
                    );
                  }
                  return SongTile(
                    tile: tiles[index],
                    index: index,
                    onPlay: (_) => _playFrom(tiles, index),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _playFrom(List<SongTileData> tiles, int startIndex) {
    final ctx = playContextFromTiles(tiles, startIndex);
    ref.read(playerProvider).playQueue(ctx.refs, startIndex: ctx.startIndex);
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

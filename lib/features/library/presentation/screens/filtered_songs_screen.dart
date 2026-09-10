import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/artwork_view.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/initials_avatar.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../shared/widgets/skeleton_list.dart';
import '../../../../shared/widgets/transitions.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../data/library_models.dart';
import '../../data/library_repository.dart';
import '../../data/song_ref_mapper.dart';
import '../providers/library_view_providers.dart';
import '../widgets/library_tiles.dart';
import '../widgets/song_tile.dart';

/// Songs of one album, artist, or collection — the drill-down target.
class FilteredSongsScreen extends ConsumerStatefulWidget {
  const FilteredSongsScreen({
    super.key,
    this.album,
    this.artist,
    this.genre,
    this.collectionKind,
    this.collectionLabel,
  });

  factory FilteredSongsScreen.album(AlbumSummary album) =>
      FilteredSongsScreen(album: album);
  factory FilteredSongsScreen.artist(ArtistSummary artist) =>
      FilteredSongsScreen(artist: artist);
  factory FilteredSongsScreen.genre(String genre) =>
      FilteredSongsScreen(genre: genre);
  factory FilteredSongsScreen.collection(CollectionKind kind, String label) =>
      FilteredSongsScreen(collectionKind: kind, collectionLabel: label);

  final AlbumSummary? album;
  final ArtistSummary? artist;
  final String? genre;
  final CollectionKind? collectionKind;
  final String? collectionLabel;

  @override
  ConsumerState<FilteredSongsScreen> createState() =>
      _FilteredSongsScreenState();
}

class _FilteredSongsScreenState extends ConsumerState<FilteredSongsScreen> {
  /// Reactive query key for [filteredSongsProvider]. The list is re-read from
  /// the database whenever the library refresh (or stats/favorites) ticks
  /// move, so a delete, rescan or import committed while this page is open
  /// can never leave a stale song list — or stale Song objects whose content
  /// URIs no longer resolve — on screen.
  FilteredSongsQuery get _query => (
    albumRowId: widget.album?.albumRowId,
    artistRowId: widget.artist?.artistRowId,
    genre: widget.genre,
    collectionKind: widget.collectionKind,
  );

  /// True while a shuffled playback session started from this screen is being
  /// set up. During that window the Shuffle button disables itself so a double
  /// tap cannot start two interleaved shuffled sessions; it re-enables the
  /// moment the session is committed (highlighting follows global playback
  /// state, not this local flag).
  bool _shuffleLoading = false;

  Future<void> _playShuffled(List<SongTileData> tiles) async {
    if (_shuffleLoading) {
      return;
    }
    setState(() => _shuffleLoading = true);
    try {
      final player = ref.read(playerProvider);
      await player.setShuffle(true);
      await player.playQueue([
        for (final t in (List.of(tiles)..shuffle())) songTileToRef(t),
      ]);
    } finally {
      if (mounted) {
        setState(() => _shuffleLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title =
        widget.collectionLabel ??
        widget.album?.name ??
        widget.artist?.name ??
        widget.genre ??
        'Songs';
    final subtitle =
        widget.album?.artistName ??
        (widget.artist != null ? '${widget.artist!.songCount} songs' : null);
    final songsAsync = ref.watch(filteredSongsProvider(_query));
    final artistAlbumsAsync = widget.artist == null
        ? null
        : ref.watch(artistAlbumsProvider(widget.artist!.artistRowId));
    // The Shuffle button reflects the player's global shuffle state — it stays
    // lit whenever a shuffle is in effect, even after a track finished, and
    // un-lights only when the user toggles shuffle off elsewhere.
    final shuffleEnabled = ref.watch(playbackStateProvider).shuffleEnabled;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      // Artist detail: same prominent controls as the Library's Songs section
      // (and playlist detail) — float Shuffle/Play above the Mini Player
      // instead of keeping them inline with the song count.
      floatingActionButton: widget.artist != null
          ? songsAsync.maybeWhen(
              data: (tiles) {
                if (tiles.isEmpty) {
                  return const SizedBox.shrink();
                }
                return _ArtistPlayerButtons(
                  tiles: tiles,
                  shuffleActive: shuffleEnabled,
                  onShuffle: _shuffleLoading
                      ? null
                      : () => _playShuffled(tiles),
                  onPlay: () => ref.read(playerProvider).playQueue([
                    for (final t in tiles) songTileToRef(t),
                  ]),
                );
              },
              orElse: () => const SizedBox.shrink(),
            )
          : null,
      body: songsAsync.when(
        loading: () => const SkeletonList(rows: 8),
        error: (_, _) => const EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load songs',
          message: 'Go back and try again.',
        ),
        data: (tiles) => tiles.isEmpty
            ? const EmptyState(
                icon: Icons.music_off_rounded,
                title: 'No songs here',
                message: 'This entry has no playable songs right now.',
              )
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _EntryHeader(
                      album: widget.album,
                      artist: widget.artist,
                      genre: widget.genre,
                      collectionKind: widget.collectionKind,
                      collectionLabel: widget.collectionLabel,
                      subtitle: subtitle,
                    ),
                  ),
                  // Artist detail page: albums the artist appears on, shown as a
                  // horizontally scrolling strip (like the Home playlist strip),
                  // separated from the song list by a divider.
                  if (widget.artist != null && artistAlbumsAsync != null)
                    SliverToBoxAdapter(
                      child: artistAlbumsAsync.maybeWhen(
                        data: (albums) {
                          if (albums.isEmpty) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppTokens.s5,
                                  AppTokens.s1,
                                  AppTokens.s5,
                                  AppTokens.s2,
                                ),
                                child: Text(
                                  'Albums',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 176,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppTokens.s4,
                                  ),
                                  itemCount: albums.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: AppTokens.s3),
                                  itemBuilder: (context, index) =>
                                      _AlbumStripCard(
                                        album: albums[index],
                                        onTap: () => Navigator.of(context).push(
                                          pushSharedAxis<void>(
                                            context,
                                            FilteredSongsScreen.album(
                                              albums[index],
                                            ),
                                          ),
                                        ),
                                      ),
                                ),
                              ),
                              const SizedBox(height: AppTokens.s2),
                              Divider(
                                height: AppTokens.borderHairline,
                                thickness: AppTokens.borderHairline,
                                color: colorScheme.outlineVariant,
                              ),
                            ],
                          );
                        },
                        orElse: () => const SizedBox.shrink(),
                      ),
                    ),
                  if (widget.genre != null)
                    const SliverToBoxAdapter(child: GenreDisclaimer()),
                  if (tiles.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppTokens.s5,
                          AppTokens.s1,
                          AppTokens.s5,
                          AppTokens.s1,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${tiles.length} ${tiles.length == 1 ? 'song' : 'songs'}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            // The artist page floats these buttons above the Mini
                            // Player instead of keeping them inline here.
                            if (widget.artist == null) ...[
                              FilledButton.tonalIcon(
                                onPressed: _shuffleLoading
                                    ? null
                                    : () => _playShuffled(tiles),
                                icon: const Icon(
                                  Icons.shuffle_rounded,
                                  size: 20,
                                ),
                                label: const Text('Shuffle'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: shuffleEnabled
                                      ? colorScheme.primary
                                      : null,
                                  foregroundColor: shuffleEnabled
                                      ? colorScheme.onPrimary
                                      : null,
                                ),
                              ),
                              const SizedBox(width: AppTokens.s3),
                              FilledButton.icon(
                                onPressed: () =>
                                    ref.read(playerProvider).playQueue([
                                      for (final t in tiles) songTileToRef(t),
                                    ]),
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 22,
                                ),
                                label: const Text('Play all'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  SliverList.separated(
                    itemCount: tiles.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 0.5,
                      indent: 80,
                      endIndent: AppTokens.s4,
                    ),
                    itemBuilder: (context, index) => SongTile(
                      key: ValueKey(tiles[index].song.id),
                      tile: tiles[index],
                      index: index,
                      onPlay: (_) => ref.read(playerProvider).playQueue([
                        for (final t in tiles) songTileToRef(t),
                      ], startIndex: index),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppTokens.s8),
                  ),
                  // Extra clearance so the floating Play/Shuffle buttons never
                  // cover the last song of an artist page.
                  if (widget.artist != null)
                    const SliverToBoxAdapter(
                      child: SizedBox(height: AppTokens.s2),
                    ),
                ],
              ),
      ),
    );
  }
}

class _EntryHeader extends StatelessWidget {
  const _EntryHeader({
    this.album,
    this.artist,
    this.genre,
    this.collectionKind,
    this.collectionLabel,
    this.subtitle,
  });

  final AlbumSummary? album;
  final ArtistSummary? artist;
  final String? genre;
  final CollectionKind? collectionKind;
  final String? collectionLabel;
  final String? subtitle;

  static IconData collectionIconFor(CollectionKind kind) => switch (kind) {
    CollectionKind.favorites => Icons.favorite_rounded,
    CollectionKind.mostPlayed => Icons.local_fire_department_rounded,
    CollectionKind.recentlyPlayed => Icons.history_rounded,
    CollectionKind.recentlyAdded => Icons.schedule_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCollection = collectionKind != null;
    // Collections (Favourites / Most played / Recently played) and genre
    // pages have no album/artist art, so they fall back to a themed icon or
    // the genre's initial instead of an empty InitialsAvatar ("?").
    final title = album?.name ?? artist?.name ?? collectionLabel ?? genre ?? '';
    final isAlbum = album != null;
    final artPath = album?.artPath ?? artist?.artPath;

    final Widget? leading;
    if (isAlbum) {
      leading = ArtworkView(
        path: artPath,
        size: AppTokens.artworkXl,
        radius: AppTokens.rLg,
      );
    } else if (artist != null) {
      leading = (artPath != null
          ? ArtworkView(
              path: artPath,
              size: AppTokens.artworkXl,
              radius: AppTokens.artworkXl / 2,
            )
          : InitialsAvatar(name: artist!.name, size: AppTokens.artworkXl));
    } else if (isCollection) {
      leading = Container(
        width: AppTokens.artworkXl,
        height: AppTokens.artworkXl,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(
          collectionIconFor(collectionKind!),
          size: AppTokens.artworkXl * 0.4,
          color: colorScheme.primary,
        ),
      );
    } else if (genre != null && genre!.trim().isNotEmpty) {
      leading = InitialsAvatar(name: genre!, size: AppTokens.artworkXl);
    } else {
      leading = null;
    }

    if (leading == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s5,
        AppTokens.s4,
        AppTokens.s5,
        AppTokens.s3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(child: leading),
          const SizedBox(width: AppTokens.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: AppTokens.s1),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The floating Shuffle + Play buttons above the Mini Player on the artist
/// detail page - the same prominent controls the Library's Songs section and
/// playlist detail use. Shuffle disables only while a shuffled session is
/// being set up, then stays lit while the player's shuffle state is on
/// (mirroring the inline row it replaced).
class _ArtistPlayerButtons extends ConsumerWidget {
  const _ArtistPlayerButtons({
    required this.tiles,
    required this.shuffleActive,
    required this.onShuffle,
    required this.onPlay,
  });

  final List<SongTileData> tiles;
  final bool shuffleActive;
  final VoidCallback? onShuffle;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton.tonalIcon(
            onPressed: onShuffle,
            icon: const Icon(Icons.shuffle_rounded, size: 20),
            label: const Text('Shuffle'),
            style: FilledButton.styleFrom(
              backgroundColor: shuffleActive ? colorScheme.primary : null,
              foregroundColor: shuffleActive ? colorScheme.onPrimary : null,
            ),
          ),
          const SizedBox(width: AppTokens.s3),
          FilledButton.icon(
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow_rounded, size: 22),
            label: const Text('Play'),
          ),
        ],
      ),
    );
  }
}

/// Compact album card for the horizontal strip on the artist detail page —
/// the same visual language as the Home playlist cards.
class _AlbumStripCard extends StatelessWidget {
  const _AlbumStripCard({required this.album, required this.onTap});

  final AlbumSummary album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 148,
        padding: const EdgeInsets.all(AppTokens.s3),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppTokens.rLg),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: AppTokens.borderHairline,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ArtworkView(
              path: album.artPath,
              size: 104,
              radius: AppTokens.rMd,
              showShadow: true,
            ),
            const SizedBox(height: AppTokens.s2),
            Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Flexible(
              child: Text(
                album.artistName ??
                    '${album.songCount} ${album.songCount == 1 ? 'song' : 'songs'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

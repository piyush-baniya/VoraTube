import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/artwork_view.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/initials_avatar.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../shared/widgets/skeleton_list.dart';
import '../../../../shared/widgets/transitions.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../collections/presentation/providers/collections_providers.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../data/library_models.dart';
import '../../data/library_repository.dart';
import '../../data/song_ref_mapper.dart';
import '../providers/library_providers.dart';
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
  late final Future<List<SongTileData>> _future = _load();

  /// Albums the artist appears on — only loaded on the artist detail page,
  /// where they render as a horizontal strip above the song list.
  late final Future<List<AlbumSummary>>? _albumsFuture = widget.artist == null
      ? null
      : ref
          .read(libraryRepositoryProvider)
          .albumsForArtist(widget.artist!.artistRowId);

  /// True while a shuffled playback session started from this screen is
  /// active. Only used to highlight the Shuffle button.
  bool _shuffleActive = false;

  Future<List<SongTileData>> _load() {
    final collectionKind = widget.collectionKind;
    if (collectionKind != null) {
      final collections = ref.read(collectionsProvider);
      return collections.songsOf(collectionKind);
    }
    final repository = ref.read(libraryRepositoryProvider);
    final album = widget.album;
    if (album != null) {
      return repository.songsForAlbum(album.albumRowId);
    }
    final genre = widget.genre;
    if (genre != null) {
      return repository.songsForGenre(genre);
    }
    return repository.songsForArtist(widget.artist!.artistRowId);
  }

  /// Starts the whole list in shuffled playback. The on-screen order is never
  /// reordered: shuffling happens inside the player, which keeps the queue's
  /// chosen song first and randomises everything after it.
  Future<void> _playShuffled(List<SongTileData> tiles) async {
    final player = ref.read(playerProvider);
    await player.setShuffle(true);
    player.playQueue([for (final t in tiles) songTileToRef(t)]);
    if (mounted) {
      setState(() => _shuffleActive = true);
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

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<List<SongTileData>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SkeletonList(rows: 8);
          }
          if (snapshot.hasError) {
            return const EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Could not load songs',
              message: 'Go back and try again.',
            );
          }
          final tiles = snapshot.data ?? const [];
          if (tiles.isEmpty) {
            return const EmptyState(
              icon: Icons.music_off_rounded,
              title: 'No songs here',
              message: 'This entry has no playable songs right now.',
            );
          }
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _EntryHeader(
                  album: widget.album,
                  artist: widget.artist,
                  subtitle: subtitle,
                ),
              ),
              // Artist detail page: albums the artist appears on, shown as a
              // horizontally scrolling strip (like the Home playlist strip),
              // separated from the song list by a divider.
              if (widget.artist != null && _albumsFuture != null)
                SliverToBoxAdapter(
                  child: FutureBuilder<List<AlbumSummary>>(
                    future: _albumsFuture,
                    builder: (context, albumSnapshot) {
                      final albums = albumSnapshot.data ?? const [];
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
                              itemBuilder: (context, index) => _AlbumStripCard(
                                album: albums[index],
                                onTap: () => Navigator.of(context).push(
                                  pushSharedAxis<void>(
                                    context,
                                    FilteredSongsScreen.album(albums[index]),
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
                        FilledButton.tonalIcon(
                          onPressed: _shuffleActive ? null : () => _playShuffled(tiles),
                          icon: const Icon(Icons.shuffle_rounded, size: 20),
                          label: const Text('Shuffle'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _shuffleActive
                                ? colorScheme.primary
                                : null,
                            foregroundColor: _shuffleActive
                                ? colorScheme.onPrimary
                                : null,
                          ),
                        ),
                        const SizedBox(width: AppTokens.s3),
                        FilledButton.icon(
                          onPressed: () => ref.read(playerProvider).playQueue([
                            for (final t in tiles) songTileToRef(t),
                          ]),
                          icon: const Icon(Icons.play_arrow_rounded, size: 22),
                          label: const Text('Play all'),
                        ),
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
              const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s8)),
            ],
          );
        },
      ),
    );
  }
}

class _EntryHeader extends StatelessWidget {
  const _EntryHeader({this.album, this.artist, this.subtitle});

  final AlbumSummary? album;
  final ArtistSummary? artist;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = album?.name ?? artist?.name ?? '';
    final isAlbum = album != null;
    final artPath = album?.artPath ?? artist?.artPath;

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
          Flexible(
            child: isAlbum
                ? ArtworkView(
                    path: artPath,
                    size: AppTokens.artworkXl,
                    radius: AppTokens.rLg,
                  )
                : (artPath != null
                      ? ArtworkView(
                          path: artPath,
                          size: AppTokens.artworkXl,
                          radius: AppTokens.artworkXl / 2,
                        )
                      : InitialsAvatar(
                          name: title,
                          size: AppTokens.artworkXl,
                        )),
          ),
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

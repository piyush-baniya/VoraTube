import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/skeleton_list.dart';
import '../../../collections/presentation/providers/collections_providers.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../data/library_models.dart';
import '../../data/library_repository.dart';
import '../../data/song_ref_mapper.dart';
import '../providers/library_providers.dart';
import '../widgets/song_tile.dart';

/// Songs of one album, artist, or collection — the drill-down target from the
/// library grids/lists. Loads once; supports play-all in context.
class FilteredSongsScreen extends ConsumerStatefulWidget {
  const FilteredSongsScreen({
    super.key,
    this.album,
    this.artist,
    this.collectionKind,
    this.collectionLabel,
  });

  factory FilteredSongsScreen.album(AlbumSummary album) =>
      FilteredSongsScreen(album: album);
  factory FilteredSongsScreen.artist(ArtistSummary artist) =>
      FilteredSongsScreen(artist: artist);
  factory FilteredSongsScreen.collection(CollectionKind kind, String label) =>
      FilteredSongsScreen(collectionKind: kind, collectionLabel: label);

  final AlbumSummary? album;
  final ArtistSummary? artist;
  final CollectionKind? collectionKind;
  final String? collectionLabel;

  @override
  ConsumerState<FilteredSongsScreen> createState() =>
      _FilteredSongsScreenState();
}

class _FilteredSongsScreenState extends ConsumerState<FilteredSongsScreen> {
  late final Future<List<SongTileData>> _future = _load();

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
    return repository.songsForArtist(widget.artist!.artistRowId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title =
        widget.collectionLabel ??
        widget.album?.name ??
        widget.artist?.name ??
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        subtitle ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => ref.read(playerProvider).playQueue([
                        for (final t in tiles) songTileToRef(t),
                      ]),
                      icon: const Icon(Icons.play_arrow_rounded, size: 22),
                      label: const Text('Play all'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: tiles.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 78),
                  itemBuilder: (context, index) => SongTile(
                    tile: tiles[index],
                    index: index,
                    onPlay: (_) => ref.read(playerProvider).playQueue([
                      for (final t in tiles) songTileToRef(t),
                    ], startIndex: index),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

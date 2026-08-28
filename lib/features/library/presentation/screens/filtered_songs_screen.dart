import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/artwork_view.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/skeleton_list.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../collections/presentation/providers/collections_providers.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../data/library_models.dart';
import '../../data/library_repository.dart';
import '../../data/song_ref_mapper.dart';
import '../providers/library_providers.dart';
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
                : Container(
                    width: AppTokens.artworkXl,
                    height: AppTokens.artworkXl,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colorScheme.primary.withValues(alpha: 0.18),
                          colorScheme.primary.withValues(alpha: 0.04),
                        ],
                      ),
                    ),
                    child: Icon(
                      Icons.person_rounded,
                      size: AppTokens.artworkXl * 0.45,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.6,
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

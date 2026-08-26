import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';

import '../../../../shared/widgets/artwork_view.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/screen_header.dart';
import '../../../../shared/widgets/transitions.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../playlists/presentation/screens/playlist_detail_screen.dart';

import 'package:vora_tube/features/library/data/library_models.dart';
import 'package:vora_tube/features/library/presentation/screens/filtered_songs_screen.dart';
import 'package:vora_tube/features/library/data/song_ref_mapper.dart'
    show playContextFromTiles;

import '../providers/search_providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _fieldController = TextEditingController();

  @override
  void dispose() {
    _fieldController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final query = ref.watch(debouncedSearchQueryProvider);
    final resultsAsync = ref.watch(searchResultsProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ScreenHeader(title: 'Search'),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.s4,
              AppTokens.s1,
              AppTokens.s4,
              AppTokens.s2,
            ),
            child: TextField(
              controller: _fieldController,
              onChanged: (text) => submitSearchText(ref, text),
              textInputAction: TextInputAction.search,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: 'Songs, artists, albums, playlists',
                hintStyle: TextStyle(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 22,
                  color: colorScheme.onSurfaceVariant,
                ),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () {
                          _fieldController.clear();
                          submitSearchText(ref, '');
                        },
                      ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s5,
                  vertical: AppTokens.s3,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTokens.rXl),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: resultsAsync.when(
              skipLoadingOnRefresh: true,
              loading: () => const SizedBox.shrink(),
              error: (e, _) => const EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Search failed',
                message: 'Try a different term.',
              ),
              data: (results) {
                if (query.isEmpty) {
                  return const EmptyState(
                    icon: Icons.search_rounded,
                    title: 'Search your library',
                    message: 'Everything stays on this device.',
                  );
                }
                if (results.isEmpty) {
                  return EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No matches for \u201C$query\u201D',
                    message: 'Check the spelling or try fewer words.',
                  );
                }
                return _Results(results: results);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.results});

  final SearchResults results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = <Widget>[
      for (final tile in results.songs)
        _SongResultTile(tile: tile, allTiles: results.songs),
      for (final album in results.albums)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: AppTokens.s5),
          leading: ArtworkView(path: album.artPath, size: 48),
          title: Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            'Album \u00b7 ${album.artistName ?? ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.of(context).push(
            pushSharedAxis<void>(context, FilteredSongsScreen.album(album)),
          ),
        ),
      for (final artist in results.artists)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: AppTokens.s5),
          leading: const Icon(Icons.person_rounded, size: 26),
          title: Text(
            artist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: const Text('Artist'),
          onTap: () => Navigator.of(context).push(
            pushSharedAxis<void>(context, FilteredSongsScreen.artist(artist)),
          ),
        ),
      for (final playlist in results.playlists)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: AppTokens.s5),
          leading: const Icon(Icons.queue_music_rounded, size: 26),
          title: Text(
            playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: const Text('Playlist'),
          onTap: () => Navigator.of(context).push(
            pushSharedAxis<void>(
              context,
              PlaylistDetailScreen(
                playlistId: playlist.id,
                name: playlist.name,
              ),
            ),
          ),
        ),
    ];

    return FadeThroughSwitcher(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: children,
      ),
    );
  }
}

class _SongResultTile extends ConsumerWidget {
  const _SongResultTile({required this.tile, required this.allTiles});

  final SongTileData tile;
  final List<SongTileData> allTiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = tile.song;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppTokens.s5),
      leading: ArtworkView(path: tile.artPath, size: 48),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        song.artist ?? '\u2014',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.play_arrow_rounded, size: 24),
      onTap: () {
        final ctx = playContextFromTiles(allTiles, allTiles.indexOf(tile));
        ref
            .read(playerProvider)
            .playQueue(ctx.refs, startIndex: ctx.startIndex);
      },
    );
  }
}

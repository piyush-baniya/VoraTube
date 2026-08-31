import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vora_tube/features/ads/banner_ad_widget.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';

import '../../../../shared/widgets/artwork_view.dart';
import '../../../../shared/widgets/empty_state.dart' show EmptyState;
import '../../../../shared/widgets/scroll_reveal.dart';
import '../../../../shared/widgets/transitions.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../playlists/presentation/screens/playlist_detail_screen.dart';

import 'package:vora_tube/features/library/data/library_models.dart';
import 'package:vora_tube/features/library/presentation/screens/filtered_songs_screen.dart';
import 'package:vora_tube/features/library/presentation/widgets/song_tile.dart';
import 'package:vora_tube/features/library/data/song_ref_mapper.dart'
    show playContextFromTiles;

import '../../data/search_rank.dart' show highlightOccurrences;
import '../providers/search_providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.onBack});

  /// Called when the user taps the back arrow while Search is shown as a tab
  /// (i.e. when the navigator cannot pop). When Search is pushed as a route,
  /// the back arrow pops instead.
  final VoidCallback? onBack;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _fieldController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Auto-focus the search field once the first frame has been laid out.
    // Guarded because the screen can be unmounted within the same frame it was
    // created, and a disposed FocusNode must never be touched.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _fieldController.dispose();
    _focusNode.dispose();
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
          // Header with back button
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.s3,
              AppTokens.s3,
              AppTokens.s3,
              AppTokens.s2,
            ),
            child: Row(
              children: [
                PressableScale(
                  onTap: () {
                    final navigator = Navigator.of(context);
                    if (navigator.canPop()) {
                      navigator.pop();
                    } else {
                      widget.onBack?.call();
                    }
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      size: 24,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: AppTokens.s3),
                Expanded(
                  child: Text(
                    'Search',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Search field
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.s4,
              AppTokens.s1,
              AppTokens.s4,
              AppTokens.s3,
            ),
            child: TextField(
              controller: _fieldController,
              focusNode: _focusNode,
              onChanged: (text) => submitSearchText(ref, text),
              onSubmitted: (_) => _focusNode.unfocus(),
              textInputAction: TextInputAction.search,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: 'Songs, artists, albums, playlists',
                hintStyle: TextStyle(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 24,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                suffixIcon: query.isEmpty
                    ? null
                    : PressableScale(
                        onTap: () {
                          _fieldController.clear();
                          submitSearchText(ref, '');
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(AppTokens.s3),
                          child: Icon(
                            Icons.close_rounded,
                            size: 22,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
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
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTokens.rXl),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTokens.rXl),
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
              ),
            ),
          ),
          // A single, small, unobtrusive banner that never overlaps playback
          // controls. It sits under the search field and collapses to nothing
          // when Premium is active or the ad fails to load.
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppTokens.s5),
            child: VoraTubeBannerAd(),
          ),
          Expanded(
            child: resultsAsync.when(
              skipLoadingOnRefresh: true,
              loading: () => const SizedBox.shrink(),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Search failed',
                message: 'Try a different term.',
              ),
              data: (results) {
                if (query.isEmpty) {
                  return _EmptySearchState();
                }
                if (results.isEmpty) {
                  return _NoResultsState(query: query);
                }
                return _Results(results: results, query: query);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary.withValues(alpha: 0.15),
                  colorScheme.primary.withValues(alpha: 0.03),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
            child: Icon(
              Icons.search_rounded,
              size: 44,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppTokens.s6),
          Text(
            'Search your library',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTokens.s3),
          Text(
            'Everything stays on this device.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.error.withValues(alpha: 0.15),
                  colorScheme.error.withValues(alpha: 0.03),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
            child: Icon(
              Icons.search_off_rounded,
              size: 44,
              color: colorScheme.error.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: AppTokens.s6),
          Text(
            'No matches for "$query"',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTokens.s3),
          Text(
            'Try different or fewer words.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.results, required this.query});

  final SearchResults results;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return CustomScrollView(
      slivers: [
        if (results.songs.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(title: 'Songs', count: results.songs.length),
          ),
          SliverList.separated(
            itemCount: results.songs.length,
            separatorBuilder: (_, _) => Divider(
              height: AppTokens.borderHairline,
              thickness: AppTokens.borderHairline,
              color: colorScheme.outlineVariant,
              indent: AppTokens.artworkMd + AppTokens.s3 + AppTokens.s5,
              endIndent: AppTokens.s5,
            ),
            itemBuilder: (context, index) => ScrollReveal(
              child: SongTile(
                key: ValueKey(results.songs[index].song.id),
                tile: results.songs[index],
                index: index,
                highlightQuery: query,
                onPlay: (ctx) {
                  // Play the whole result list from the tapped song, matching the
                  // behaviour of every other song list in the app.
                  final start = results.songs.indexOf(results.songs[index]);
                  final playCtx = playContextFromTiles(results.songs, start);
                  ref
                      .read(playerProvider)
                      .playQueue(playCtx.refs, startIndex: playCtx.startIndex);
                },
              ),
            ),
          ),
        ],
        if (results.albums.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'Albums',
              count: results.albums.length,
            ),
          ),
          SliverList.separated(
            itemCount: results.albums.length,
            separatorBuilder: (_, _) => Divider(
              height: AppTokens.borderHairline,
              thickness: AppTokens.borderHairline,
              color: colorScheme.outlineVariant,
              indent: AppTokens.artworkMd + AppTokens.s3 + AppTokens.s5,
              endIndent: AppTokens.s5,
            ),
            itemBuilder: (context, index) {
              final album = results.albums[index];
              return _AlbumResultTile(album: album, query: query);
            },
          ),
        ],
        if (results.artists.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'Artists',
              count: results.artists.length,
            ),
          ),
          SliverList.separated(
            itemCount: results.artists.length,
            separatorBuilder: (_, _) => Divider(
              height: AppTokens.borderHairline,
              thickness: AppTokens.borderHairline,
              color: colorScheme.outlineVariant,
              indent: AppTokens.artworkMd + AppTokens.s3 + AppTokens.s5,
              endIndent: AppTokens.s5,
            ),
            itemBuilder: (context, index) {
              final artist = results.artists[index];
              return _ArtistResultTile(artist: artist, query: query);
            },
          ),
        ],
        if (results.playlists.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'Playlists',
              count: results.playlists.length,
            ),
          ),
          SliverList.separated(
            itemCount: results.playlists.length,
            separatorBuilder: (_, _) => Divider(
              height: AppTokens.borderHairline,
              thickness: AppTokens.borderHairline,
              color: colorScheme.outlineVariant,
              indent: AppTokens.artworkMd + AppTokens.s3 + AppTokens.s5,
              endIndent: AppTokens.s5,
            ),
            itemBuilder: (context, index) {
              final playlist = results.playlists[index];
              final songCount = results.playlistCountsById[playlist.id] ?? 0;
              return _PlaylistResultTile(
                playlist: playlist,
                songCount: songCount,
                query: query,
              );
            },
          ),
        ],
        SliverToBoxAdapter(child: SizedBox(height: AppTokens.s8)),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s5,
        AppTokens.s4,
        AppTokens.s5,
        AppTokens.s2,
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: AppTokens.s3),
          Expanded(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                letterSpacing: 1.0,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s3),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s2,
              vertical: 1,
            ),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTokens.rFull),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumResultTile extends ConsumerWidget {
  const _AlbumResultTile({required this.album, required this.query});

  final dynamic album;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PressableScale(
      onTap: () => Navigator.of(
        context,
      ).push(pushSharedAxis<void>(context, FilteredSongsScreen.album(album))),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s5,
          vertical: AppTokens.s1,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              ArtworkView(
                path: album.artPath,
                size: AppTokens.artworkMd,
                radius: AppTokens.rSm,
              ),
              const SizedBox(width: AppTokens.s3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HighlightedText(
                      text: album.name,
                      query: query,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Album ${album.artistName ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtistResultTile extends ConsumerWidget {
  const _ArtistResultTile({required this.artist, required this.query});

  final dynamic artist;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PressableScale(
      onTap: () => Navigator.of(
        context,
      ).push(pushSharedAxis<void>(context, FilteredSongsScreen.artist(artist))),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s5,
          vertical: AppTokens.s1,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_rounded,
                  size: 24,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: AppTokens.s3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HighlightedText(
                      text: artist.name,
                      query: query,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistResultTile extends ConsumerWidget {
  const _PlaylistResultTile({
    required this.playlist,
    required this.songCount,
    required this.query,
  });

  final dynamic playlist;
  final int songCount;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PressableScale(
      onTap: () => Navigator.of(context).push(
        pushSharedAxis<void>(
          context,
          PlaylistDetailScreen(playlistId: playlist.id, name: playlist.name),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s5,
          vertical: AppTokens.s1,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppTokens.rSm),
                ),
                child: Icon(
                  Icons.queue_music_rounded,
                  size: 24,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: AppTokens.s3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HighlightedText(
                      text: playlist.name,
                      query: query,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Playlist · $songCount ${songCount == 1 ? 'song' : 'songs'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders [text] with the substrings matching [query] emphasized using the
/// theme's primary colour, so the user can immediately see why a result
/// surfaced. Falls back to a plain [Text] when nothing matches.
class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.query,
    this.style,
    this.maxLines = 1,
  });

  final String text;
  final String query;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final spans = highlightOccurrences(text, query);
    final hasHighlight = spans.any((s) => s.highlight);

    if (!hasHighlight) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style,
        children: [
          for (final span in spans)
            TextSpan(
              text: span.text,
              style: span.highlight
                  ? TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}

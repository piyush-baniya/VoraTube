import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/empty_state.dart' show EmptyState;
import '../../../../shared/widgets/skeleton_list.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../data/library_models.dart';
import '../../data/song_ref_mapper.dart';
import '../providers/library_view_providers.dart';
import '../widgets/song_tile.dart';

/// The complete local song collection, opened from Home's "See All".
///
/// Reuses the existing paginated [pagedSongsProvider] so it streams the whole
/// library a page at a time instead of loading it at once.
class AllSongsScreen extends ConsumerStatefulWidget {
  const AllSongsScreen({super.key});

  @override
  ConsumerState<AllSongsScreen> createState() => _AllSongsScreenState();
}

class _AllSongsScreenState extends ConsumerState<AllSongsScreen> {
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
    final theme = Theme.of(context);
    final asyncValue = ref.watch(pagedSongsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'All Songs',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: asyncValue.when(
        skipLoadingOnRefresh: true,
        loading: () => const SkeletonList(rows: 12),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load songs',
          message: 'Your music is safe. Try again in a moment.',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(pagedSongsProvider),
        ),
        data: (tiles) {
          if (tiles.isEmpty) {
            return const EmptyState(
              icon: Icons.library_music_rounded,
              title: 'No songs yet',
              message: 'Scan or import music to fill your library.',
            );
          }
          return CustomScrollView(
            controller: _controller,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverList.separated(
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
                        color: theme.colorScheme.outlineVariant,
                      ),
                itemBuilder: (context, index) {
                  if (index >= tiles.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
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
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s8)),
            ],
          );
        },
      ),
    );
  }

  void _playFrom(List<SongTileData> tiles, int startIndex) {
    final ctx = playContextFromTiles(tiles, startIndex);
    ref.read(playerProvider).playQueue(ctx.refs, startIndex: ctx.startIndex);
  }
}

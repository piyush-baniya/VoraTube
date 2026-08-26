import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/artwork_view.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/transitions.dart';
import '../../../library/data/library_models.dart';
import '../../../library/data/song_ref_mapper.dart';
import '../../../library/presentation/widgets/song_tile.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../data/playlist_models.dart';
import '../../data/playlist_repository.dart';
import '../providers/playlist_providers.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    required this.name,
  });

  final int playlistId;
  final String name;

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (_controller.position.extentAfter < 600) {
      ref.read(playlistDetailProvider(widget.playlistId).notifier).loadMore();
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
    final asyncSongs = ref.watch(playlistDetailProvider(widget.playlistId));
    final notifier = ref.read(
      playlistDetailProvider(widget.playlistId).notifier,
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DetailHeader(name: widget.name, playlistId: widget.playlistId),
            Expanded(
              child: asyncSongs.when(
                skipLoadingOnRefresh: true,
                loading: () => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                error: (e, _) => EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Could not load songs',
                  message: 'Try again in a moment.',
                  actionLabel: 'Retry',
                  onAction: () =>
                      ref.invalidate(playlistDetailProvider(widget.playlistId)),
                ),
                data: (tiles) {
                  if (tiles.isEmpty) {
                    return const EmptyState(
                      icon: Icons.music_note_rounded,
                      title: 'Empty playlist',
                      message: 'Add songs from your library.',
                    );
                  }
                  return ListView.separated(
                    controller: _controller,
                    padding: const EdgeInsets.only(bottom: 120),
                    itemCount: tiles.length + (notifier.hasMore ? 1 : 0),
                    separatorBuilder: (_, i) => i == tiles.length - 1
                        ? const SizedBox.shrink()
                        : const Divider(height: 1, indent: 78),
                    itemBuilder: (context, index) {
                      if (index >= tiles.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
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
        ),
      ),
      floatingActionButton: asyncSongs.whenOrNull(
        data: (tiles) => tiles.isNotEmpty
            ? _PlayerButtons(playlistId: widget.playlistId, tiles: tiles)
            : null,
      ),
    );
  }

  void _playFrom(List<SongTileData> tiles, int startIndex) {
    final ctx = playContextFromTiles(tiles, startIndex);
    ref.read(playerProvider).playQueue(ctx.refs, startIndex: ctx.startIndex);
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.name, required this.playlistId});

  final String name;
  final int playlistId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _PlaylistMenuButton(playlistId: playlistId, name: name),
        ],
      ),
    );
  }
}

class _PlaylistMenuButton extends ConsumerWidget {
  const _PlaylistMenuButton({required this.playlistId, required this.name});

  final int playlistId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final overview = ref.watch(playlistsOverviewProvider);
    final isPinned =
        overview.whenOrNull(
          data: (list) => list.any((p) => p.id == playlistId && p.pinned),
        ) ??
        false;

    return PopupMenuButton<String>(
      tooltip: 'More',
      onSelected: (action) async {
        final repository = ref.read(playlistRepositoryProvider);
        switch (action) {
          case 'rename':
            await _rename(context, ref, repository);
          case 'pin':
            await repository.setPinned(playlistId, !isPinned);
            ref.read(playlistRefreshTickProvider.notifier).state++;
          case 'delete':
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete playlist?'),
                content: Text('"$name" will be permanently deleted.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                    ),
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              await repository.deletePlaylist(playlistId);
              ref.read(playlistRefreshTickProvider.notifier).state++;
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'rename',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.edit_rounded, size: 22),
            title: const Text('Rename'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'pin',
          child: ListTile(
            dense: true,
            leading: Icon(
              isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
              size: 22,
            ),
            title: Text(isPinned ? 'Unpin' : 'Pin'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            dense: true,
            leading: Icon(
              Icons.delete_rounded,
              size: 22,
              color: theme.colorScheme.error,
            ),
            title: Text(
              'Delete',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    PlaylistRepository repository,
  ) async {
    final controller = TextEditingController(text: name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'Playlist name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && result != name) {
      try {
        await repository.renamePlaylist(playlistId, result);
        ref.read(playlistRefreshTickProvider.notifier).state++;
      } on DuplicatePlaylistNameException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }
  }
}

class _PlayerButtons extends ConsumerWidget {
  const _PlayerButtons({required this.playlistId, required this.tiles});

  final int playlistId;
  final List<SongTileData> tiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton.icon(
            onPressed: () {
              final ctx = playContextFromTiles(tiles, 0);
              ref.read(playerProvider).setShuffle(true);
              ref
                  .read(playerProvider)
                  .playQueue(ctx.refs, startIndex: ctx.startIndex);
            },
            icon: const Icon(Icons.shuffle_rounded, size: 20),
            label: const Text('Shuffle'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: () {
              final ctx = playContextFromTiles(tiles, 0);
              ref.read(playerProvider).setShuffle(false);
              ref
                  .read(playerProvider)
                  .playQueue(ctx.refs, startIndex: ctx.startIndex);
            },
            icon: const Icon(Icons.play_arrow_rounded, size: 22),
            label: const Text('Play'),
          ),
        ],
      ),
    );
  }
}

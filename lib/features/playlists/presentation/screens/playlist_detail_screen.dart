import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/empty_state.dart';
import '../../../../app/widgets/vora_snackbar.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../features/ads/interstitial_ads_provider.dart';
import '../../../ads/banner_ad_widget.dart';
import '../../../library/data/library_models.dart';
import '../../../library/data/song_ref_mapper.dart';
import '../../../library/presentation/widgets/song_tile.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../data/playlist_models.dart';
import '../../data/playlist_repository.dart';
import '../providers/playlist_providers.dart';
import '../widgets/add_songs_sheet.dart';

/// Maps a [ReorderableListView.onReorderItem] pair to a playlist move target.
///
/// [newIndex] is already in the post-removal index space (the framework
/// adjusts it), so no extra shift is needed here. Drops that land on/past the
/// loading footer (which is rendered outside the reorderable items) simply
/// mean "move to the very end", so [length] clamps to the last index instead
/// of being rejected (which used to make the row snap back).
int playlistDropTarget(int oldIndex, int newIndex, int length) {
  if (length < 2) return -1;
  if (oldIndex < 0 || oldIndex >= length) return -1;
  if (newIndex < 0) return -1;
  if (newIndex > length - 1) newIndex = length - 1;
  return newIndex == oldIndex ? -1 : newIndex;
}

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
  /// Shuffled song order shown while the Shuffle button is active. `null`
  /// means the list displays the playlist's persisted order. The shuffled view
  /// is intentionally NOT persisted so the playlist order stays user-controlled.
  List<SongTileData>? _shuffled;

  /// True while a reorder drag is in flight so pagination does not reload the
  /// list mid-drag (which would cancel the drag and snap the row back).
  bool _dragging = false;

  List<SongTileData>? _viewTiles(List<SongTileData> tiles) =>
      _shuffled ?? tiles;

  @override
  void initState() {
    super.initState();
    // Interstitial ad trigger: the user opened a playlist.
    Future.microtask(
      () => ref.read(interstitialAdControllerProvider).showOnTrigger(),
    );
  }

  void _onScroll(ScrollMetrics metrics) {
    if (!_dragging && metrics.extentAfter < 600) {
      ref.read(playlistDetailProvider(widget.playlistId).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncSongs = ref.watch(playlistDetailProvider(widget.playlistId));
    final notifier = ref.read(
      playlistDetailProvider(widget.playlistId).notifier,
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DetailHeader(
              name: widget.name,
              playlistId: widget.playlistId,
              onAddSongs: _addSongs,
            ),
            // A single, small, unobtrusive banner that never overlaps playback
            // controls. It sits under the playlist header and collapses to
            // nothing when Premium is active or the ad fails to load.
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppTokens.s5),
              child: VoraTubeBannerAd(),
            ),
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
                    return EmptyState(
                      icon: Icons.music_note_rounded,
                      title: 'Empty playlist',
                      message: 'Add songs from your library.',
                      actionLabel: 'Add songs',
                      onAction: _addSongs,
                    );
                  }
                  final viewTiles = _viewTiles(tiles)!;
                  return NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      _onScroll(notification.metrics);
                      return false;
                    },
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.only(bottom: 120),
                      buildDefaultDragHandles: false,
                      onReorderStart: (_) => _dragging = true,
                      onReorderEnd: (_) => _dragging = false,
                      onReorderItem: (oldIndex, newIndex) {
                        final target = playlistDropTarget(
                          oldIndex,
                          newIndex,
                          tiles.length,
                        );
                        if (target < 0) return;
                        ref
                            .read(
                              playlistDetailProvider(widget.playlistId)
                                  .notifier,
                            )
                            .move(oldIndex, target);
                      },
                      itemCount: viewTiles.length,
                      footer: notifier.hasMore
                          ? const Padding(
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
                            )
                          : null,
                      proxyDecorator: (child, index, animation) =>
                          Material(color: Colors.transparent, child: child),
                      itemBuilder: (context, index) {
                        final tile = viewTiles[index];
                        return SongTile(
                          key: ValueKey(tile.song.id),
                          tile: tile,
                          index: index,
                          onPlay: (_) => _playFrom(viewTiles, index),
                          removeFromPlaylistId: widget.playlistId,
                          dragHandle: !_shuffling,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: asyncSongs.whenOrNull(
        data: (tiles) => tiles.isNotEmpty
            ? _PlayerButtons(
                tiles: _viewTiles(tiles)!,
                shuffling: _shuffling,
                onShuffle: () => _shuffle(tiles),
                onPlay: () => _play(tiles),
              )
            : null,
      ),
    );
  }

  bool get _shuffling => _shuffled != null;

  void _shuffle(List<SongTileData> tiles) {
    // Reorder the on-screen list AND play that same order so the visible
    // playlist matches playback.
    final shuffled = List<SongTileData>.of(tiles)..shuffle();
    setState(() => _shuffled = shuffled);
    _playFrom(shuffled, 0);
  }

  void _play(List<SongTileData> tiles) {
    // Play follows the currently displayed order. If the shuffled view is
    // active it is kept (and played) rather than reset to the persisted order.
    _playFrom(_viewTiles(tiles)!, 0);
  }

  void _playFrom(List<SongTileData> tiles, int startIndex) {
    final ctx = playContextFromTiles(tiles, startIndex);
    ref.read(playerProvider).playQueue(ctx.refs, startIndex: ctx.startIndex);
  }

  Future<void> _addSongs() async {
    final result = await showAddSongsSheet(
      context,
      playlistId: widget.playlistId,
    );
    if (result == null || !mounted) {
      return;
    }
    final notifier = ref.read(
      playlistDetailProvider(widget.playlistId).notifier,
    );
    // Remove marked songs first (by their current index in the list).
    if (result.toRemove.isNotEmpty) {
      final songs = await ref.read(
        playlistDetailProvider(widget.playlistId).future,
      );
      final indices = <int>[];
      for (final id in result.toRemove) {
        final idx = songs.indexWhere((s) => s.song.id == id);
        if (idx >= 0) indices.add(idx);
      }
      // Remove from highest index first so earlier indices stay valid.
      indices.sort((a, b) => b.compareTo(a));
      for (final idx in indices) {
        await notifier.removeAt(idx);
      }
    }
    if (result.toAdd.isNotEmpty) {
      await notifier.appendSongs(result.toAdd);
    }
    ref.read(playlistRefreshTickProvider.notifier).state++;
    if (!mounted) return;
    final added = result.toAdd.length;
    final removed = result.toRemove.length;
    if (added > 0 && removed > 0) {
      VoraSnackbar.success(
        context,
        '$added song${added == 1 ? '' : 's'} added, $removed removed.',
        title: 'Playlist updated',
      );
    } else if (added > 0) {
      VoraSnackbar.success(
        context,
        '$added song${added == 1 ? '' : 's'} added to "${widget.name}".',
        title: 'Added to playlist',
      );
    } else if (removed > 0) {
      VoraSnackbar.success(
        context,
        "$removed song${removed == 1 ? "" : "s"} removed.",
        title: 'Removed from playlist',
      );
    }
  }
}

class _DetailHeader extends ConsumerWidget {
  const _DetailHeader({
    required this.name,
    required this.playlistId,
    required this.onAddSongs,
  });

  /// Initial name supplied by the caller. The live title is resolved from the
  /// playlists overview so a rename reflects immediately (no stale header).
  final String name;
  final int playlistId;
  final VoidCallback onAddSongs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Drive the shown title from the authoritative overview so renames update
    // in place. Falls back to [name] while the overview is still loading.
    final overview = ref.watch(playlistsOverviewProvider).valueOrNull;
    var displayName = name;
    if (overview != null) {
      for (final p in overview) {
        if (p.id == playlistId) {
          displayName = p.name;
          break;
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s1,
        vertical: AppTokens.s1,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Add songs',
            onPressed: onAddSongs,
            icon: const Icon(Icons.add_rounded),
          ),
          _PlaylistMenuButton(playlistId: playlistId, name: displayName),
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
          height: 44,
          child: Row(
            children: [
              const Icon(Icons.edit_rounded, size: 20),
              const SizedBox(width: AppTokens.s3),
              const Text('Rename'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'pin',
          height: 44,
          child: Row(
            children: [
              Icon(
                isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                size: 20,
              ),
              const SizedBox(width: AppTokens.s3),
              Text(isPinned ? 'Unpin' : 'Pin'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          height: 44,
          child: Row(
            children: [
              Icon(
                Icons.delete_rounded,
                size: 20,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: AppTokens.s3),
              Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
            ],
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
          VoraSnackbar.error(
            context,
            'A playlist with this name already exists.',
            title: 'Couldn\'t rename playlist',
          );
        }
      }
    }
  }
}

class _PlayerButtons extends ConsumerWidget {
  const _PlayerButtons({
    required this.tiles,
    required this.shuffling,
    required this.onShuffle,
    required this.onPlay,
  });

  final List<SongTileData> tiles;

  /// Whether the shuffled view is currently displayed.
  final bool shuffling;
  final VoidCallback onShuffle;
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
              backgroundColor: shuffling ? colorScheme.primary : null,
              foregroundColor: shuffling ? colorScheme.onPrimary : null,
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

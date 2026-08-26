import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/song_ref_mapper.dart'
    show OnPlaySong, PlayContext, songTileToRef;
import '../../../player/presentation/providers/player_providers.dart';
import '../../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../../../../shared/widgets/artwork_view.dart';
import '../../data/library_models.dart';
import '../providers/library_view_providers.dart';

class SongTile extends ConsumerStatefulWidget {
  const SongTile({
    super.key,
    required this.tile,
    required this.index,
    required this.onPlay,
  });

  final SongTileData tile;
  final int index;
  final OnPlaySong onPlay;

  @override
  ConsumerState<SongTile> createState() => _SongTileState();
}

class _SongTileState extends ConsumerState<SongTile> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = widget.tile.song;
    final isFavorite = ref.watch(
      favoriteIdsProvider.select((ids) => ids.contains(song.id)),
    );

    return InkWell(
      onTap: () => widget.onPlay(
        PlayContext(refs: [songTileToRef(widget.tile)], startIndex: 0),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              ArtworkView(path: widget.tile.artPath, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist ?? song.albumName ?? '\u2014',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(song.durationMs),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                padding: EdgeInsets.zero,
                iconSize: 22,
                splashRadius: 20,
                onSelected: (action) => _onMenuAction(action),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'play_next',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.skip_next_rounded, size: 22),
                      title: Text('Play next'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'add_to_queue',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.queue_music_rounded, size: 22),
                      title: Text('Add to queue'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'add_to_playlist',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.playlist_add_rounded, size: 22),
                      title: Text('Add to playlist'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
              IconButton(
                tooltip: isFavorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                onPressed: () =>
                    ref.read(favoriteIdsProvider.notifier).toggle(song.id),
                icon: Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 22,
                  color: isFavorite ? theme.colorScheme.primary : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int ms) {
    if (ms <= 0) {
      return '';
    }
    final total = Duration(milliseconds: ms);
    final s = total.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${total.inMinutes}:$s';
  }

  void _onMenuAction(String action) {
    final player = ref.read(playerProvider);
    final songRef = songTileToRef(widget.tile);
    switch (action) {
      case 'play_next':
        player.playNext(songRef);
      case 'add_to_queue':
        player.enqueue(songRef);
      case 'add_to_playlist':
        if (context.mounted) {
          showAddToPlaylistSheet(context, widget.tile.song.id);
        }
    }
  }
}

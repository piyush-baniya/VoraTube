import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/song_ref_mapper.dart'
    show OnPlaySong, PlayContext, songTileToRef;
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
}

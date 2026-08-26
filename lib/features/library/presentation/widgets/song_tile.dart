import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/song_ref_mapper.dart'
    show OnPlaySong, PlayContext, songTileToRef;
import '../../../player/presentation/providers/player_providers.dart';
import '../../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../../../../shared/widgets/artwork_view.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../data/library_models.dart';
import '../providers/library_view_providers.dart';

/// Premium song tile with 64px artwork, clean typography, and
/// subtle press feedback. Uses PressableScale for GPU-friendly
/// scale animation on tap.
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
    final colorScheme = theme.colorScheme;
    final song = widget.tile.song;
    final isFavorite = ref.watch(
      favoriteIdsProvider.select((ids) => ids.contains(song.id)),
    );

    return PressableScale(
      onTap: () => widget.onPlay(
        PlayContext(refs: [songTileToRef(widget.tile)], startIndex: 0),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s1,
        ),
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              ArtworkView(
                path: widget.tile.artPath,
                size: AppTokens.artworkLg,
                radius: AppTokens.rSm,
              ),
              const SizedBox(width: AppTokens.s3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist ?? song.albumName ?? '\u2014',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.s2),
              if (song.durationMs > 0)
                Text(
                  _formatDuration(song.durationMs),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              const SizedBox(width: AppTokens.s1),
              PopupMenuButton<String>(
                tooltip: 'More',
                padding: EdgeInsets.zero,
                iconSize: 20,
                splashRadius: 18,
                color: theme.colorScheme.surfaceContainerHigh,
                onSelected: (action) => _onMenuAction(action),
                itemBuilder: (context) => [
                  _menuItem(
                    icon: Icons.skip_next_rounded,
                    label: 'Play next',
                    value: 'play_next',
                  ),
                  _menuItem(
                    icon: Icons.queue_music_rounded,
                    label: 'Add to queue',
                    value: 'add_to_queue',
                  ),
                  _menuItem(
                    icon: Icons.playlist_add_rounded,
                    label: 'Add to playlist',
                    value: 'add_to_playlist',
                  ),
                ],
              ),
              _FavoriteButton(
                isFavorite: isFavorite,
                onTap: () =>
                    ref.read(favoriteIdsProvider.notifier).toggle(song.id),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return PopupMenuItem(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppTokens.s3),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  String _formatDuration(int ms) {
    if (ms <= 0) return '';
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

/// Minimal favorite heart with scale animation on toggle.
class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.isFavorite, required this.onTap});

  final bool isFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: AppTokens.touchTarget,
      height: AppTokens.touchTarget,
      child: IconButton(
        tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
        onPressed: onTap,
        icon: Icon(
          isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 20,
        ),
        color: isFavorite
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
    );
  }
}

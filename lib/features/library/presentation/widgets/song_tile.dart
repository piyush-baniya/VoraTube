import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/song_ref_mapper.dart'
    show OnPlaySong, PlayContext, songTileToRef;
import '../../../player/presentation/providers/player_providers.dart';
import '../../../../shared/widgets/artwork_view.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../data/library_models.dart';
import '../providers/library_view_providers.dart';
import 'song_actions.dart';

/// Premium song tile with 64px artwork, clean typography,
/// playing indicator, and subtle press feedback.
class SongTile extends ConsumerStatefulWidget {
  const SongTile({
    super.key,
    required this.tile,
    required this.index,
    required this.onPlay,
    this.removeFromPlaylistId,
    this.dragHandle = false,
  });

  final SongTileData tile;
  final int index;
  final OnPlaySong onPlay;

  /// When non-null (playlist detail), the overflow menu additionally offers
  /// "Remove from playlist".
  final int? removeFromPlaylistId;

  /// Renders a draggable reorder handle (for use inside a ReorderableListView).
  final bool dragHandle;

  @override
  ConsumerState<SongTile> createState() => _SongTileState();
}

class _SongTileState extends ConsumerState<SongTile> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final song = widget.tile.song;

    // Watch playback state for the playing indicator. Two narrow providers
    // (current track identity + a play/pause boolean) are watched instead of
    // the whole snapshot, so buffering/duration/seek/queue emissions do not
    // rebuild every visible song row. The playing state is only read when this
    // tile is the current song.
    final currentTrackKey = ref.watch(currentTrackIdentityProvider);
    final isPlaying = ref.watch(playbackIsPlayingProvider);
    final isCurrentSong =
        currentTrackKey != null && currentTrackKey == _tileKey;
    final isFavorite = ref.watch(
      favoriteIdsProvider.select((ids) => ids.contains(song.id)),
    );

    return PressableScale(
      onTap: () => widget.onPlay(
        PlayContext(refs: [songTileToRef(widget.tile)], startIndex: 0),
      ),
      onLongPress: () => _showMenu(context),
      child: AnimatedContainer(
        duration: AppTokens.fast,
        curve: AppTokens.easeOut,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s1,
        ),
        decoration: isCurrentSong
            ? BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.06),
                border: Border(
                  left: BorderSide(color: colorScheme.primary, width: 3),
                ),
              )
            : null,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              // Artwork with playing animation overlay
              Stack(
                alignment: Alignment.center,
                children: [
                  ArtworkView(
                    path: widget.tile.artPath,
                    size: AppTokens.artworkLg,
                    radius: AppTokens.rSm,
                    showShadow: isCurrentSong,
                  ),
                  if (isCurrentSong && isPlaying)
                    _PlayingIndicator(size: AppTokens.artworkLg),
                ],
              ),
              const SizedBox(width: AppTokens.s3),
              // Metadata
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: isCurrentSong
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isCurrentSong
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (isCurrentSong && isPlaying) ...[
                          const SizedBox(width: AppTokens.s2),
                          _EqualizerAnimation(color: colorScheme.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist ?? song.albumName ?? '\u2014',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: isCurrentSong
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.s2),
              // Duration
              if (song.durationMs > 0)
                Text(
                  _formatDuration(song.durationMs),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isCurrentSong
                        ? colorScheme.primary.withValues(alpha: 0.8)
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              const SizedBox(width: AppTokens.s1),
              // Overflow menu
              PressableScale(
                onTap: () => _showMenu(context),
                child: SizedBox(
                  width: AppTokens.touchTarget,
                  height: AppTokens.touchTarget,
                  child: IconButton(
                    tooltip: 'More options',
                    onPressed: () => _showMenu(context),
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.s1),
              // Favorite button
              _FavoriteButton(
                isFavorite: isFavorite,
                isCurrent: isCurrentSong,
                onTap: () =>
                    ref.read(favoriteIdsProvider.notifier).toggle(song.id),
              ),
              if (widget.dragHandle) ...[
                const SizedBox(width: AppTokens.s1),
                ReorderableDragStartListener(
                  index: widget.index,
                  child: SizedBox(
                    width: AppTokens.touchTarget,
                    height: AppTokens.touchTarget,
                    child: Icon(
                      Icons.drag_handle_rounded,
                      size: 20,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String get _tileKey => widget.tile.song.source == 'mediastore'
      ? 'ms:${widget.tile.song.mediaStoreId}'
      : 'h:${widget.tile.song.contentHash}';

  void _showMenu(BuildContext context) {
    SongActions.show(
      context,
      ref,
      tile: widget.tile,
      removeFromPlaylistId: widget.removeFromPlaylistId,
    );
  }

  void _showSongInfo(BuildContext context) {
    final song = widget.tile.song;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTokens.rXxl),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: AppTokens.s3),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTokens.s5),
              child: Row(
                children: [
                  ArtworkView(
                    path: widget.tile.artPath,
                    size: AppTokens.artworkXl,
                    radius: AppTokens.rMd,
                  ),
                  const SizedBox(width: AppTokens.s4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (song.artist != null) ...[
                          const SizedBox(height: AppTokens.s1),
                          Text(
                            song.artist!,
                            maxLines: 1,
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
            ),
            Divider(
              height: 1,
              color: colorScheme.outlineVariant,
              indent: AppTokens.s5,
              endIndent: AppTokens.s5,
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s5,
                  vertical: AppTokens.s3,
                ),
                children: [
                  _InfoRow(
                    icon: Icons.album_rounded,
                    label: 'Album',
                    value: song.albumName ?? 'Unknown',
                  ),
                  if (song.genre != null && song.genre!.isNotEmpty)
                    _InfoRow(
                      icon: Icons.style_rounded,
                      label: 'Genre',
                      value: song.genre!,
                    ),
                  if (song.year != null && song.year! > 0)
                    _InfoRow(
                      icon: Icons.calendar_today_rounded,
                      label: 'Year',
                      value: song.year.toString(),
                    ),
                  if (song.trackNumber != null && song.trackNumber! > 0)
                    _InfoRow(
                      icon: Icons.format_list_numbered_rounded,
                      label: 'Track',
                      value: song.trackNumber.toString(),
                    ),
                  if (song.discNumber != null && song.discNumber! > 1)
                    _InfoRow(
                      icon: Icons.format_list_numbered_rounded,
                      label: 'Disc',
                      value: song.discNumber.toString(),
                    ),
                  _InfoRow(
                    icon: Icons.timer_rounded,
                    label: 'Duration',
                    value: _formatDuration(song.durationMs),
                  ),
                  if (song.format != null && song.format!.isNotEmpty)
                    _InfoRow(
                      icon: Icons.file_present_rounded,
                      label: 'Format',
                      value: song.format!.toUpperCase(),
                    ),
                  if (song.sizeBytes != null && song.sizeBytes! > 0)
                    _InfoRow(
                      icon: Icons.storage_rounded,
                      label: 'Size',
                      value: _formatBytes(song.sizeBytes!),
                    ),
                  if (song.contentUri.isNotEmpty)
                    _InfoRow(
                      icon: Icons.link_rounded,
                      label: 'Source',
                      value: song.contentUri,
                      isLong: true,
                    ),
                ],
              ),
            ),
            SizedBox(
              height: MediaQuery.paddingOf(context).bottom + AppTokens.s4,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int ms) {
    if (ms <= 0) return '';
    final total = Duration(milliseconds: ms);
    final s = total.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${total.inMinutes}:$s';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _PlayingIndicator extends StatefulWidget {
  const _PlayingIndicator({required this.size});

  final double size;

  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.rSm),
            border: Border.all(
              color: colorScheme.primary.withValues(
                alpha: 0.3 * _controller.value + 0.1,
              ),
              width: 2,
            ),
          ),
        );
      },
    );
  }
}

class _EqualizerAnimation extends StatefulWidget {
  const _EqualizerAnimation({required this.color});

  final Color color;

  @override
  State<_EqualizerAnimation> createState() => _EqualizerAnimationState();
}

class _EqualizerAnimationState extends State<_EqualizerAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(3, (index) {
            final delay = index * 0.15;
            final value = (_controller.value + delay) % 1.0;
            final height = 4.0 + (value * 12.0);

            return Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Container(
                width: 3,
                height: height,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({
    required this.isFavorite,
    required this.isCurrent,
    required this.onTap,
  });

  final bool isFavorite;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: AppTokens.touchTarget,
      height: AppTokens.touchTarget,
      child: PressableScale(
        onTap: onTap,
        child: IconButton(
          tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
          onPressed: onTap,
          icon: AnimatedSwitcher(
            duration: AppTokens.fast,
            transitionBuilder: (child, animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            child: Icon(
              isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              key: ValueKey(isFavorite),
              size: 20,
            ),
          ),
          color: isFavorite
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PressableScale(
      onTap: onTap,
      child: ListTile(
        leading: Icon(
          icon,
          size: 22,
          color: iconColor ?? colorScheme.onSurfaceVariant,
        ),
        title: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s5,
          vertical: AppTokens.s1,
        ),
        dense: true,
        onTap: onTap,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.isLong = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(width: AppTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: isLong ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

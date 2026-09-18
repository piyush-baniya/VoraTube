import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/song_ref_mapper.dart'
    show OnPlaySong, PlayContext, songTileToRef;
import '../../../search/data/search_rank.dart' show highlightOccurrences;
import '../../../player/presentation/providers/player_providers.dart';
import '../../../player/presentation/screens/full_player_screen.dart';
import '../../../../shared/widgets/artwork_view.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../shared/widgets/transitions.dart' show pushHero;
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
    this.highlightQuery,
  });

  final SongTileData tile;
  final int index;
  final OnPlaySong onPlay;

  /// When non-null (playlist detail), the overflow menu additionally offers
  /// "Remove from playlist".
  final int? removeFromPlaylistId;

  /// Renders a draggable reorder handle (for use inside a ReorderableListView).
  final bool dragHandle;

  /// When non-null (search results), the title's matching substring is
  /// highlighted to explain why the row surfaced.
  final String? highlightQuery;

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

    // Gesture split:
    //  - Inside a reorderable list (dragHandle), long-press on the card body
    //    starts the existing ReorderableListView drag via a delayed drag
    //    listener — it must NOT open the actions menu (the explicit three-dot
    //    button remains the only way to open it).
    //  - Outside reorderable lists, keep the previous long-press-to-open-menu
    //    behavior.
    final cardBody = AnimatedContainer(
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
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
                        child: widget.highlightQuery == null
                            ? Text(
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
                              )
                            : _HighlightedTitle(
                                title: song.title,
                                query: widget.highlightQuery!,
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
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    // Reorderable list: the whole card body is a delayed drag start listener
    // (long-press-and-hold starts the reorder). Long press does not open the
    // actions menu here — the three-dot button does that.
    if (widget.dragHandle) {
      return ReorderableDelayedDragStartListener(
        index: widget.index,
        child: PressableScale(
          onTap: () => _handleTap(context, currentTrackKey),
          child: cardBody,
        ),
      );
    }

    // Non-reorderable lists: keep the previous long-press-to-open-menu
    // behavior.
    return PressableScale(
      onTap: () => _handleTap(context, currentTrackKey),
      onLongPress: () => _showMenu(context),
      child: cardBody,
    );
  }

  /// Distinguishes "tap the already-playing song" from "tap a different song".
  ///
  /// When the tapped row is the exact song the player currently has loaded
  /// (compared by the stable MediaStore/content-hash identity key, never by
  /// title), the card must NOT restart, seek, pause, toggle or rebuild the
  /// queue. Playing or paused, it simply opens the Full Player and leaves every
  /// bit of playback state untouched. Any other row keeps the existing
  /// behaviour of letting the screen decide what to play through
  /// [widget.onPlay].
  void _handleTap(BuildContext context, String? currentTrackKey) {
    if (currentTrackKey != null && currentTrackKey == _tileKey) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).push(pushHero<void>(context, const FullPlayerScreen()));
      return;
    }
    widget.onPlay(
      PlayContext(refs: [songTileToRef(widget.tile)], startIndex: 0),
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

  String _formatDuration(int ms) {
    if (ms <= 0) return '';
    final total = Duration(milliseconds: ms);
    final s = total.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${total.inMinutes}:$s';
  }
}

class _PlayingIndicator extends StatelessWidget {
  const _PlayingIndicator({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return RepaintBoundary(
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.rSm),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}

class _EqualizerAnimation extends StatefulWidget {
  const _EqualizerAnimation({required this.color});

  final Color color;

  @override
  State<_EqualizerAnimation> createState() => _EqualizerAnimationState();
}

class _EqualizerAnimationState extends State<_EqualizerAnimation> {
  static const Duration _period = Duration(milliseconds: 150);
  Timer? _timer;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_period, (_) {
      if (!mounted) return;
      setState(() => _tick++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _tick.toDouble();

    return RepaintBoundary(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (index) {
          final wave = (math.sin(t * 0.42 + index * 1.1) + 1) / 2;
          final height = 3.5 + (wave * 12.5);

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
      ),
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

/// Title row that highlights the substrings matching a search query.
///
/// Reuses the same cheap span computation as the search screen so SongTiles in
/// search results stay visually consistent with the dedicated result tiles.
class _HighlightedTitle extends StatelessWidget {
  const _HighlightedTitle({
    required this.title,
    required this.query,
    this.style,
  });

  final String title;
  final String query;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final spans = highlightOccurrences(title, query);
    final hasHighlight = spans.any((s) => s.highlight);

    if (!hasHighlight) {
      return Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    return RichText(
      maxLines: 1,
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

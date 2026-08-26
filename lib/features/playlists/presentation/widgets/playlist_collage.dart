import 'package:flutter/material.dart';

import '../../../../shared/widgets/artwork_view.dart';
import '../../data/playlist_models.dart';

/// Mosaic artwork for a playlist: a single cover, a 2-up split, a 3-up
/// (two top, one wide bottom) or the classic 4-tile grid — with a glyph
/// fallback for empty playlists.
class PlaylistCollage extends StatelessWidget {
  const PlaylistCollage({
    super.key,
    required this.summary,
    this.size = 56,
    this.radius = 12,
  });

  final PlaylistSummary summary;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final covers = summary.covers.take(4).toList();

    if (covers.isEmpty) {
      return _fallback(theme);
    }

    Widget art(String? path, {double? radius}) =>
        ArtworkView(path: path, size: size, radius: radius ?? 0);

    final Widget mosaic;
    switch (covers.length) {
      case 1:
        return art(covers[0], radius: radius);
      case 2:
        mosaic = Row(
          children: [
            Expanded(child: art(covers[0])),
            Expanded(child: art(covers[1])),
          ],
        );
      case 3:
        mosaic = Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: art(covers[0])),
                  Expanded(child: art(covers[1])),
                ],
              ),
            ),
            Expanded(child: art(covers[2])),
          ],
        );
      default:
        mosaic = Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: art(covers[0])),
                  Expanded(child: art(covers[1])),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: art(covers[2])),
                  Expanded(child: art(covers[3])),
                ],
              ),
            ),
          ],
        );
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            Positioned.fill(child: mosaic),
            // Hairline separators keep tiles distinct on any background.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.fromBorderSide(
                      BorderSide(
                        color: theme.colorScheme.surface.withValues(alpha: 0.9),
                        width: 1,
                      ),
                    ),
                    borderRadius: BorderRadius.circular(radius),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback(ThemeData theme) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        Icons.queue_music_rounded,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );
  }
}

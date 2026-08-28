import 'package:flutter/material.dart';

import '../../../../shared/widgets/artwork_view.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../data/library_models.dart';

/// Album card with larger artwork, clean typography, and subtle
/// press feedback. Uses PressableScale for GPU-friendly animation.
class AlbumCard extends StatelessWidget {
  const AlbumCard({super.key, required this.album, required this.onTap});

  final AlbumSummary album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PressableScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Artwork flexes to fill the vertical space left by the fixed
            // text block below, so the card never overflows its grid cell
            // regardless of cell height or text scale.
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ArtworkView(
                    path: album.artPath,
                    size: 160,
                    radius: AppTokens.rMd,
                    showShadow: true,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppTokens.s2),
            Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 1),
            Text(
              album.artistName ?? '${album.songCount} songs',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Artist tile with circular artwork and chevron indicator.
class ArtistTile extends StatelessWidget {
  const ArtistTile({super.key, required this.artist, required this.onTap});

  final ArtistSummary artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PressableScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s2,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              ArtworkView(
                path: artist.artPath,
                size: 52,
                square: false,
                iconSize: 24,
              ),
              const SizedBox(width: AppTokens.s3),
              Expanded(
                child: Text(
                  artist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                '${artist.songCount}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppTokens.s2),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Genre tile with subtle border and clean layout.
class GenreTile extends StatelessWidget {
  const GenreTile({super.key, required this.genre, required this.onTap});

  final GenreSummary genre;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PressableScale(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.rMd),
          color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s5,
          vertical: AppTokens.s3,
        ),
        child: Row(
          children: [
            Icon(
              Icons.music_note_rounded,
              size: 20,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: AppTokens.s3),
            Expanded(
              child: Text(
                genre.genre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
            Text(
              '${genre.songCount}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

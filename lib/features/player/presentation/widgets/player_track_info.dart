import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';

/// The song title / artist / album block used by the player and the collapsed
/// lyrics reveal.
///
/// [compact] reproduces the narrow-phone stepping: title / artist step down
/// one size so the block stays proportionate to the smaller responsive
/// artwork.
class PlayerTrackInfo extends StatelessWidget {
  const PlayerTrackInfo({
    super.key,
    required this.title,
    this.artist,
    this.album,
    this.compact = false,
  });

  final String title;
  final String? artist;
  final String? album;

  /// True on narrow phones: title / artist step down one size so the block
  /// stays proportionate to the smaller responsive artwork.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final titleStyle = compact
        ? theme.textTheme.titleLarge
        : theme.textTheme.headlineSmall;
    final artistStyle = compact
        ? theme.textTheme.bodyMedium
        : theme.textTheme.bodyLarge;

    return Column(
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: titleStyle?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.2,
          ),
        ),
        if (artist != null) ...[
          const SizedBox(height: AppTokens.s1),
          Text(
            artist!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: artistStyle?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.2,
            ),
          ),
        ],
        if (album != null && !compact) ...[
          const SizedBox(height: AppTokens.s1),
          Text(
            album!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }
}

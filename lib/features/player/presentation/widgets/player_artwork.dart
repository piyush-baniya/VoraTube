import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/ingest/artwork/artwork_file_cache.dart';

/// Large album artwork for the full-screen player with Hero transition
/// and smooth fade when the song changes.
///
/// The artwork is the visual centerpiece of the player. When the path
/// is null/empty or the file doesn't exist, a beautiful fallback is
/// shown using a gradient and decorative elements.
class PlayerArtwork extends StatelessWidget {
  const PlayerArtwork({
    super.key,
    required this.path,
    this.heroTag,
    this.size = 320,
    this.showRings = true,
    this.showShadow = true,
    this.borderRadius = AppTokens.rXl,
  });

  final String? path;

  /// Must be unique among the widgets mounted on this route. The immersive
  /// background deliberately carries no Hero for exactly this reason.
  final Object? heroTag;
  final double size;
  final bool showRings;
  final bool showShadow;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    // Existence is resolved through the shared cache rather than a `stat` per
    // build: the player rebuilds far more often than the song changes, and this
    // widget sits at the top of that subtree.
    final effectiveFile = ArtworkFileCache.resolve(path);
    final effectiveRadius = BorderRadius.circular(borderRadius);

    Widget artwork = AnimatedSwitcher(
      duration: AppTokens.slow,
      switchInCurve: AppTokens.easeOut,
      switchOutCurve: AppTokens.easeIn,
      child: effectiveFile != null
          ? _ArtworkImage(
              // Keyed by path so a song change cross-fades instead of swapping
              // the bitmap inside one element.
              key: ValueKey(path),
              file: effectiveFile,
              path: path,
              size: size,
              borderRadius: effectiveRadius,
              showShadow: showShadow,
            )
          : _ArtworkFallback(
              key: const ValueKey('fallback'),
              size: size,
              borderRadius: effectiveRadius,
              showRings: showRings,
              showShadow: showShadow,
            ),
    );

    if (heroTag != null) {
      artwork = Hero(tag: heroTag!, child: artwork);
    }

    return artwork;
  }
}

class _ArtworkImage extends StatelessWidget {
  const _ArtworkImage({
    super.key,
    required this.file,
    required this.path,
    required this.size,
    required this.borderRadius,
    this.showShadow = true,
  });

  final File file;

  /// Kept alongside [file] purely so a decode failure can invalidate the
  /// memoized existence answer for the same path.
  final String? path;
  final double size;
  final BorderRadius borderRadius;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget child = ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: Image.file(
          file,
          fit: BoxFit.cover,
          cacheWidth: ArtworkFileCache.decodeWidth(
            size,
            MediaQuery.devicePixelRatioOf(context),
          ),
          gaplessPlayback: false,
          frameBuilder: (context, child, frame, wasLoaded) {
            if (wasLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: child,
            );
          },
          // Without this a truncated or removed file rendered Flutter's red
          // error box across the centrepiece of the player.
          errorBuilder: (_, _, _) {
            ArtworkFileCache.forget(path);
            return _ArtworkFallback(
              size: size,
              borderRadius: borderRadius,
              showShadow: false,
            );
          },
        ),
      ),
    );

    if (showShadow) {
      child = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: _artworkShadow(theme, isDark),
        ),
        child: child,
      );
    }

    return child;
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({
    super.key,
    required this.size,
    required this.borderRadius,
    this.showRings = true,
    this.showShadow = true,
  });

  final double size;
  final BorderRadius borderRadius;
  final bool showRings;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // One Container carries both the gradient and the shadow. The previous
    // version followed this with `if (showShadow && child is! Container)`,
    // which could never be true — the branch was 24 lines of unreachable code
    // duplicating the shadow that had already been applied.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppColors.voidBlack,
                  AppColors.surfaceDark,
                  AppColors.surfaceRaisedDark,
                ]
              : [
                  AppColors.paperLight,
                  AppColors.surfaceLight,
                  AppColors.surfaceRaisedLight,
                ],
          stops: const [0.0, 0.5, 1.0],
        ),
        boxShadow: showShadow ? _artworkShadow(theme, isDark) : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (showRings)
            // Concentric rings read as a record sleeve behind the note.
            ...List.generate(3, (i) {
              final scale = 0.4 + i * 0.2;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.primary.withValues(
                        alpha: 0.03 + i * 0.01,
                      ),
                      width: 1,
                    ),
                  ),
                ),
              );
            }),
          Icon(
            Icons.music_note_rounded,
            size: size * 0.28,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
          ),
        ],
      ),
    );
  }
}

/// Shared elevation for the player centrepiece, so the image and its fallback
/// cannot drift apart.
List<BoxShadow> _artworkShadow(ThemeData theme, bool isDark) => [
  BoxShadow(
    color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.3),
    blurRadius: 32,
    offset: const Offset(0, 16),
    spreadRadius: -8,
  ),
  BoxShadow(
    color: theme.colorScheme.primary.withValues(alpha: 0.08),
    blurRadius: 24,
    offset: const Offset(0, 8),
    spreadRadius: -4,
  ),
];

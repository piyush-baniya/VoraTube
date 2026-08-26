import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Large album artwork for the full-screen player with Hero transition
/// and smooth fade when the song changes.
///
/// The artwork is the visual centerpiece of the player. When the path
/// is null/empty or the file doesn't exist, a beautiful fallback is
/// shown using a gradient and music note icon.
class PlayerArtwork extends StatelessWidget {
  const PlayerArtwork({
    super.key,
    required this.path,
    this.heroTag,
    this.size = 320,
  });

  final String? path;
  final Object? heroTag;
  final double size;

  @override
  Widget build(BuildContext context) {
    final effectiveFile = _resolveFile();
    final cardSize = size;
    final borderRadius = BorderRadius.circular(20);

    Widget artwork = AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: effectiveFile != null
          ? _ArtworkImage(
              key: ValueKey(path),
              file: effectiveFile,
              size: cardSize,
              borderRadius: borderRadius,
            )
          : _ArtworkFallback(
              key: const ValueKey('fallback'),
              size: cardSize,
              borderRadius: borderRadius,
            ),
    );

    if (heroTag != null) {
      artwork = Hero(tag: heroTag!, child: artwork);
    }

    return artwork;
  }

  File? _resolveFile() {
    final p = path;
    if (p == null || p.isEmpty) return null;
    final f = File(p);
    return f.existsSync() ? f : null;
  }
}

class _ArtworkImage extends StatelessWidget {
  const _ArtworkImage({
    super.key,
    required this.file,
    required this.size,
    required this.borderRadius,
  });

  final File file;
  final double size;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Image.file(
          file,
          fit: BoxFit.cover,
          cacheWidth: (size * 2).round(),
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasLoaded) {
            if (wasLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: child,
            );
          },
        ),
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({
    super.key,
    required this.size,
    required this.borderRadius,
  });

  final double size;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.surfaceContainerHigh,
            theme.colorScheme.surfaceContainerHighest,
            theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Subtle decorative rings.
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
                    color: theme.colorScheme.outline.withValues(
                      alpha: 0.06 + i * 0.02,
                    ),
                    width: 1,
                  ),
                ),
              ),
            );
          }),
          Icon(
            Icons.album_rounded,
            size: size * 0.3,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}

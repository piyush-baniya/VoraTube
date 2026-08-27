import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';

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
  final Object? heroTag;
  final double size;
  final bool showRings;
  final bool showShadow;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final effectiveFile = _resolveFile();
    final effectiveRadius = BorderRadius.circular(borderRadius);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget artwork = AnimatedSwitcher(
      duration: AppTokens.slow,
      switchInCurve: AppTokens.easeOut,
      switchOutCurve: AppTokens.easeIn,
      child: effectiveFile != null
          ? _ArtworkImage(
              key: ValueKey(path),
              file: effectiveFile,
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
    this.showShadow = true,
  });

  final File file;
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

    if (showShadow) {
      child = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
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
          ],
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

    Widget child = Container(
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
        boxShadow: showShadow
            ? [
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
              ]
            : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (showRings) ...[
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
                      color: colorScheme.primary.withValues(
                        alpha: 0.03 + i * 0.01,
                      ),
                      width: 1,
                    ),
                  ),
                ),
              );
            }),
          ],
          Icon(
            Icons.music_note_rounded,
            size: size * 0.28,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
          ),
        ],
      ),
    );

    if (showShadow && child is! Container) {
      child = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
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
          ],
        ),
        child: child,
      );
    }

    return child;
  }
}
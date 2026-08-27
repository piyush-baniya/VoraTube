import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_tokens.dart';

/// Shared artwork rendering with graceful fallback, fade-in, and
/// consistent sizing. Files come from the existing artwork pipeline.
///
/// Performance: uses [cacheWidth] to limit decode memory, [gaplessPlayback]
/// for smooth transitions, and a fast existence check.
class ArtworkView extends StatelessWidget {
  const ArtworkView({
    super.key,
    required this.path,
    this.size = AppTokens.artworkSm,
    this.radius = AppTokens.rSm,
    this.iconSize,
    this.square = true,
    this.showShadow = false,
    this.heroTag,
    this.fit = BoxFit.cover,
    this.enableFadeIn = true,
  });

  final String? path;
  final double size;
  final double radius;
  final double? iconSize;
  final bool square;
  final bool showShadow;
  final Object? heroTag;
  final BoxFit fit;
  final bool enableFadeIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveFile = _resolveFile();
    final effectiveRadius = square ? radius : size / 2;

    Widget artwork = _buildArtwork(effectiveFile, theme, effectiveRadius);

    if (showShadow) {
      artwork = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(effectiveRadius),
          boxShadow: AppTokens.shadowMd(Colors.black),
        ),
        child: artwork,
      );
    }

    return artwork;
  }

  Widget _buildArtwork(File? file, ThemeData theme, double effectiveRadius) {
    final Widget child = ClipRRect(
      borderRadius: BorderRadius.circular(effectiveRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: file != null
            ? Image.file(
                file,
                fit: fit,
                cacheWidth: (size * 2).round(),
                gaplessPlayback: true,
                frameBuilder: (context, child, frame, wasLoaded) {
                  if (!enableFadeIn || wasLoaded) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: AppTokens.normal,
                    curve: AppTokens.easeOut,
                    child: child,
                  );
                },
                errorBuilder: (_, _, _) => _fallback(theme),
              )
            : _fallback(theme),
      ),
    );

    if (heroTag != null) {
      return Hero(tag: heroTag!, child: child);
    }
    return child;
  }

  File? _resolveFile() {
    final p = path;
    if (p == null || p.isEmpty) return null;
    final f = File(p);
    return f.existsSync() ? f : null;
  }

  Widget _fallback(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final colors = isDark
        ? [
            AppColors.voidBlack,
            AppColors.surfaceDark,
            AppColors.surfaceRaisedDark,
          ]
        : [
            AppColors.paperLight,
            AppColors.surfaceLight,
            AppColors.surfaceRaisedLight,
          ];

    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Center(
          child: Icon(
            square ? Icons.music_note_rounded : Icons.person_rounded,
            size: iconSize ?? size * 0.45,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

/// Large immersive artwork for the full-screen player.
///
/// Uses a subtle gradient ring decoration for visual depth
/// and a premium fallback when artwork is unavailable.
class PlayerArtwork extends StatelessWidget {
  const PlayerArtwork({
    super.key,
    required this.path,
    required this.heroTag,
    required this.size,
    this.showRings = true,
    this.showShadow = true,
    this.borderRadius = AppTokens.rXl,
  });

  final String? path;
  final Object heroTag;
  final double size;
  final bool showRings;
  final bool showShadow;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final file = _resolveFile();

    Widget artwork = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: file != null
            ? Image.file(
                file,
                fit: BoxFit.cover,
                cacheWidth: (size * 2).round(),
                gaplessPlayback: true,
                frameBuilder: (context, child, frame, wasLoaded) {
                  if (wasLoaded) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: AppTokens.medium,
                    curve: AppTokens.easeOut,
                    child: child,
                  );
                },
                errorBuilder: (_, _, _) => _premiumFallback(theme, isDark),
              )
            : _premiumFallback(theme, isDark),
      ),
    );

    if (showRings) {
      artwork = Stack(
        alignment: Alignment.center,
        children: [
          // Subtle outer glow ring
          Container(
            width: size + 4,
            height: size + 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
          ),
          // Main artwork
          artwork,
          // Inner accent ring
          if (isDark)
            Container(
              width: size - 2,
              height: size - 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.04),
                  width: 0.5,
                ),
              ),
            ),
        ],
      );
    }

    if (showShadow) {
      artwork = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.2),
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
        child: artwork,
      );
    }

    return Hero(tag: heroTag, child: artwork);
  }

  Widget _premiumFallback(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
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
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Decorative rings
          if (showRings) ...[
            Container(
              width: size * 0.7,
              height: size * 0.7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.06),
                  width: 1,
                ),
              ),
            ),
            Container(
              width: size * 0.5,
              height: size * 0.5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.04),
                  width: 0.5,
                ),
              ),
            ),
            Container(
              width: size * 0.3,
              height: size * 0.3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.03),
                  width: 0.5,
                ),
              ),
            ),
          ],
          // Center icon
          Icon(
            Icons.music_note_rounded,
            size: size * 0.22,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  File? _resolveFile() {
    final p = path;
    if (p == null || p.isEmpty) return null;
    final f = File(p);
    return f.existsSync() ? f : null;
  }
}

/// Small circular artwork for MiniPlayer and queue.
class CompactArtwork extends StatelessWidget {
  const CompactArtwork({
    super.key,
    required this.path,
    required this.size,
    this.heroTag,
    this.borderRadius,
    this.showShadow = false,
  });

  final String? path;
  final double size;
  final Object? heroTag;
  final double? borderRadius;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = _resolveFile();
    final effectiveRadius = borderRadius ?? (size / 2);

    Widget artwork = ClipRRect(
      borderRadius: BorderRadius.circular(effectiveRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: file != null
            ? Image.file(
                file,
                fit: BoxFit.cover,
                cacheWidth: (size * 2).round(),
                gaplessPlayback: true,
              )
            : _compactFallback(theme),
      ),
    );

    if (heroTag != null) {
      artwork = Hero(tag: heroTag!, child: artwork);
    }

    if (showShadow) {
      artwork = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(effectiveRadius),
          boxShadow: AppTokens.shadowSm(Colors.black),
        ),
        child: artwork,
      );
    }

    return artwork;
  }

  Widget _compactFallback(ThemeData theme) {
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: size * 0.5,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  File? _resolveFile() {
    final p = path;
    if (p == null || p.isEmpty) return null;
    final f = File(p);
    return f.existsSync() ? f : null;
  }
}

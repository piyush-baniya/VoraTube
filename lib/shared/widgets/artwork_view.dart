import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/ingest/artwork/artwork_file_cache.dart';

/// Shared artwork rendering with graceful fallback, fade-in, and
/// consistent sizing. Files come from the existing artwork pipeline.
///
/// Performance: existence is resolved through [ArtworkFileCache] rather than a
/// `stat` per build, [ArtworkFileCache.decodeWidth] bounds decode memory, and
/// [gaplessPlayback] avoids a blank frame when the path changes underneath a
/// reused element.
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

  /// Must be unique among the widgets mounted on one route. Two Heroes sharing a
  /// tag on the same route throws inside Flutter's Hero bookkeeping, and the
  /// damage surfaces later as an unrelated `_dependents.isEmpty` assertion.
  final Object? heroTag;
  final BoxFit fit;
  final bool enableFadeIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveFile = ArtworkFileCache.resolve(path);
    final effectiveRadius = square ? radius : size / 2;

    Widget artwork = _buildArtwork(
      effectiveFile,
      theme,
      effectiveRadius,
      ArtworkFileCache.decodeWidth(
        size,
        MediaQuery.devicePixelRatioOf(context),
      ),
    );

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

  Widget _buildArtwork(
    File? file,
    ThemeData theme,
    double effectiveRadius,
    int decodeWidth,
  ) {
    final Widget child = ClipRRect(
      borderRadius: BorderRadius.circular(effectiveRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: file != null
            ? Image.file(
                file,
                fit: fit,
                cacheWidth: decodeWidth,
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
                errorBuilder: (_, _, _) {
                  // The file existed when it was checked but cannot be decoded
                  // now: deleted, truncated, or on an unmounted volume. Drop the
                  // memoized answer so the next lookup re-examines it instead of
                  // handing back a path that is known to fail.
                  ArtworkFileCache.forget(path);
                  return _fallback(theme);
                },
              )
            : _fallback(theme),
      ),
    );

    if (heroTag != null) {
      return Hero(tag: heroTag!, child: child);
    }
    return child;
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
    final file = ArtworkFileCache.resolve(path);
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
                cacheWidth: ArtworkFileCache.decodeWidth(
                  size,
                  MediaQuery.devicePixelRatioOf(context),
                ),
                gaplessPlayback: true,
                // The MiniPlayer is on screen for most of a session, so an
                // undecodable file here previously meant a persistent red error
                // box rather than a fallback.
                errorBuilder: (_, _, _) {
                  ArtworkFileCache.forget(path);
                  return _compactFallback(theme);
                },
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
}

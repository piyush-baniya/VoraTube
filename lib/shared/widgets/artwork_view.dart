import 'dart:io';

import 'package:flutter/material.dart';

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
  });

  final String? path;
  final double size;
  final double radius;
  final double? iconSize;
  final bool square;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveFile = _resolveFile();
    final effectiveRadius = square ? radius : size / 2;

    Widget artwork = ClipRRect(
      borderRadius: BorderRadius.circular(effectiveRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: effectiveFile != null
            ? Image.file(
                effectiveFile,
                fit: BoxFit.cover,
                cacheWidth: (size * 2).round(),
                gaplessPlayback: true,
                frameBuilder: (context, child, frame, wasLoaded) {
                  if (wasLoaded) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    child: child,
                  );
                },
                errorBuilder: (_, _, _) => _fallback(theme),
              )
            : _fallback(theme),
      ),
    );

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

  File? _resolveFile() {
    final p = path;
    if (p == null || p.isEmpty) return null;
    final f = File(p);
    return f.existsSync() ? f : null;
  }

  Widget _fallback(ThemeData theme) {
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        square ? Icons.album_rounded : Icons.person_rounded,
        size: iconSize ?? size * 0.45,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
    );
  }
}

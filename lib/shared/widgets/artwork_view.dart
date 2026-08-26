import 'dart:io';

import 'package:flutter/material.dart';

/// Shared artwork rendering with graceful fallback and fade-in.
///
/// Files come from the existing artwork pipeline (native thumbnails on
/// Android, tiered saves on iOS). Missing artwork never throws.
class ArtworkView extends StatelessWidget {
  const ArtworkView({
    super.key,
    required this.path,
    this.size = 48,
    this.radius = 8,
    this.iconSize,
    this.square = true,
  });

  final String? path;
  final double size;
  final double radius;
  final double? iconSize;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveFile = _resolveFile();

    return ClipRRect(
      borderRadius: BorderRadius.circular(square ? radius : size / 2),
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
                  if (wasLoaded) {
                    return child;
                  }
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
  }

  File? _resolveFile() {
    final p = path;
    if (p == null || p.isEmpty || p == '') {
      return null;
    }
    final f = File(p);
    return f.existsSync() ? f : null;
  }

  Widget _fallback(ThemeData theme) {
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        square ? Icons.album_rounded : Icons.person_rounded,
        size: iconSize ?? size * 0.5,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );
  }
}

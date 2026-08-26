import 'dart:io';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/player/player_controller.dart';
import '../providers/player_providers.dart';

/// Compact now-playing bar docked above the bottom navigation.
///
/// Deliberately functional-minimal this phase: full visual treatment
/// arrives with the dedicated player UI phase. Progress is NOT rendered
/// here to keep high-frequency rebuilds out of the shell entirely.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(playbackSnapshotProvider).value;
    final current = snapshot?.current;

    if (snapshot == null || !snapshot.hasTrack || current == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              const SizedBox(width: 8),
              _Artwork(path: current.artPath),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      current.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (current.artist != null)
                      Text(
                        current.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: snapshot.isPlaying ? 'Pause' : 'Play',
                onPressed: () => ref.read(playerProvider).togglePlay(),
                icon: Icon(
                  snapshot.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 32,
                ),
              ),
              IconButton(
                tooltip: 'Next',
                onPressed:
                    snapshot.currentIndex < snapshot.queueLength - 1 ||
                        snapshot.repeatMode == RepeatMode.all
                    ? () => ref.read(playerProvider).next()
                    : null,
                icon: const Icon(Icons.skip_next_rounded, size: 28),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = path == null || path!.isEmpty ? null : File(path!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 48,
        child: file != null && file.existsSync()
            ? Image.file(
                file,
                fit: BoxFit.cover,
                cacheWidth: 96,
                gaplessPlayback: true,
              )
            : ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.music_note_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/player/player_controller.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../presentation/screens/full_player_screen.dart';
import '../providers/player_providers.dart';

/// Compact now-playing bar docked above the bottom navigation.
///
/// Design: Clean, elevated surface with artwork, metadata, and
/// transport controls. Subtle top border adds depth.
/// Tapping opens the full-screen player with a Hero artwork transition.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  static const _heroTag = 'player_artwork_hero';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(playbackSnapshotProvider).value;
    final current = snapshot?.current;

    if (snapshot == null || !snapshot.hasTrack || current == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            transitionDuration: AppTokens.slow,
            reverseTransitionDuration: AppTokens.medium,
            pageBuilder: (_, __, ___) => const FullPlayerScreen(),
            transitionsBuilder: (_, animation, __, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: AppTokens.easeOut,
                reverseCurve: AppTokens.easeIn,
              );
              return FadeTransition(opacity: curved, child: child);
            },
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                const SizedBox(width: AppTokens.s2),
                _Artwork(path: current.artPath, heroTag: _heroTag),
                const SizedBox(width: AppTokens.s3),
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
                            color: colorScheme.onSurfaceVariant,
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
                    size: 30,
                  ),
                ),
                IconButton(
                  tooltip: 'Next',
                  onPressed:
                      snapshot.currentIndex < snapshot.queueLength - 1 ||
                          snapshot.repeatMode == RepeatMode.all
                      ? () => ref.read(playerProvider).next()
                      : null,
                  icon: const Icon(Icons.skip_next_rounded, size: 26),
                ),
                const SizedBox(width: AppTokens.s1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.path, required this.heroTag});

  final String? path;
  final Object heroTag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = path == null || path!.isEmpty ? null : File(path!);
    return Hero(
      tag: heroTag,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.rSm),
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
                    size: 22,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
      ),
    );
  }
}

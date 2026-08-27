import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/player/player_controller.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../shared/widgets/artwork_view.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../presentation/screens/full_player_screen.dart';
import '../providers/player_providers.dart';

/// Compact now-playing bar docked above the bottom navigation.
///
/// Design: Premium elevated surface with artwork, metadata, progress indicator,
/// and transport controls. Seamless Hero transition to full-screen player.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  static const _heroTag = 'player_artwork_hero';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(playbackStateProvider);
    final current = snapshot.current;

    if (current == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

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
                curve: AppTokens.easeOutExpo,
                reverseCurve: AppTokens.easeIn,
              );
              return FadeTransition(opacity: curved, child: child);
            },
          ),
        );
      },
      child: AnimatedContainer(
        duration: AppTokens.normal,
        curve: AppTokens.easeOut,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.2),
              width: AppTokens.borderHairline,
            ),
          ),
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                    spreadRadius: -4,
                  ),
                ]
              : null,
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                const SizedBox(width: AppTokens.s3),
                // Artwork with Hero. Uses the shared CompactArtwork rather than
                // a local copy: the private duplicate it replaced had no
                // `errorBuilder`, so an undecodable file left Flutter's red
                // error box in the MiniPlayer for the rest of the session.
                CompactArtwork(
                  path: current.artPath,
                  size: 52,
                  heroTag: _heroTag,
                  borderRadius: AppTokens.rSm,
                ),
                const SizedBox(width: AppTokens.s3),
                // Metadata + progress
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
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
                          // Play/pause
                          PressableScale(
                            onTap: () => ref.read(playerProvider).togglePlay(),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withValues(
                                  alpha: 0.12,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                snapshot.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 18,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      // Progress bar
                      _MiniProgress(
                        snapshot: snapshot,
                        onSeek: (pos) => ref.read(playerProvider).seek(pos),
                      ),
                    ],
                  ),
                ),
                // Next button
                PressableScale(
                  onTap:
                      snapshot.currentIndex < snapshot.queueLength - 1 ||
                          snapshot.repeatMode == RepeatMode.all
                      ? () => ref.read(playerProvider).next()
                      : null,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.3,
                        ),
                        width: AppTokens.borderHairline,
                      ),
                    ),
                    child: Icon(
                      Icons.skip_next_rounded,
                      size: 20,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppTokens.s2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniProgress extends ConsumerWidget {
  const _MiniProgress({required this.snapshot, required this.onSeek});

  final PlayerSnapshot snapshot;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return ref
        .watch(playbackPositionProvider)
        .when(
          data: (position) {
            final duration = snapshot.durationMs > 0
                ? Duration(milliseconds: snapshot.durationMs)
                : Duration.zero;
            final progress = duration.inMilliseconds > 0
                ? position.inMilliseconds / duration.inMilliseconds
                : 0.0;

            return Stack(
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(AppTokens.rFull),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(AppTokens.rFull),
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => Container(
            height: 3,
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(AppTokens.rFull),
            ),
          ),
          error: (_, __) => Container(
            height: 3,
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(AppTokens.rFull),
            ),
          ),
        );
  }
}

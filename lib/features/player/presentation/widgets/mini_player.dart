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

    final hasPrevious =
        snapshot.currentIndex > 0 || snapshot.repeatMode == RepeatMode.all;
    final hasNext =
        snapshot.currentIndex < snapshot.queueLength - 1 ||
        snapshot.repeatMode == RepeatMode.all;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _openFullPlayer(context),
      // Swipe up expands into the full player; a deliberate quick swipe down
      // stops playback and dismisses the bar. Speed thresholds are generous so
      // a small accidental vertical wiggle never triggers a destructive stop.
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -1200) {
          _openFullPlayer(context);
        } else if (velocity > 1500) {
          ref.read(playerProvider).stop();
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.s3,
          0,
          AppTokens.s3,
          AppTokens.s2,
        ),
        child: AnimatedContainer(
          duration: AppTokens.normal,
          curve: AppTokens.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.rXl),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      AppColors.surfaceRaisedDark.withValues(alpha: 0.95),
                      AppColors.surfaceDark.withValues(alpha: 0.92),
                    ]
                  : [
                      AppColors.surfaceRaisedLight.withValues(alpha: 0.98),
                      AppColors.surfaceLight.withValues(alpha: 0.96),
                    ],
            ),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.18),
              width: AppTokens.borderHairline,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.25),
                blurRadius: 24,
                offset: const Offset(0, 8),
                spreadRadius: -6,
              ),
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
                spreadRadius: -4,
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 68,
              child: Row(
                children: [
                  const SizedBox(width: AppTokens.s3),
                  // Artwork with Hero. Uses the shared CompactArtwork rather than
                  // a local copy: the private duplicate it replaced had no
                  // `errorBuilder`, so an undecodable file left Flutter's red
                  // error box in the MiniPlayer for the rest of the session.
                  CompactArtwork(
                    path: current.artPath,
                    size: 48,
                    heroTag: _heroTag,
                    borderRadius: AppTokens.rMd,
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
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                ],
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
                  // Transport cluster: previous | play/pause | next
                  const SizedBox(width: AppTokens.s1),
                  _TransportButton(
                    icon: Icons.skip_previous_rounded,
                    enabled: hasPrevious,
                    onTap: () => ref.read(playerProvider).previous(),
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(width: AppTokens.s2),
                  PressableScale(
                    onTap: () => ref.read(playerProvider).togglePlay(),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [colorScheme.primary, AppColors.accent],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        snapshot.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 22,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTokens.s2),
                  _TransportButton(
                    icon: Icons.skip_next_rounded,
                    enabled: hasNext,
                    onTap: () => ref.read(playerProvider).next(),
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(width: AppTokens.s2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openFullPlayer(BuildContext context) {
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
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

/// A compact circular transport button with a disabled state.
class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.colorScheme,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled
              ? colorScheme.surfaceContainerHighest
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          shape: BoxShape.circle,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(
              alpha: enabled ? 0.3 : 0.15,
            ),
            width: AppTokens.borderHairline,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: colorScheme.onSurfaceVariant.withValues(
            alpha: enabled ? 0.9 : 0.35,
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

            // Tappable progress: a taller invisible hit area so the thin 3px
            // bar is easy to seek without hurting the compact layout.
            return GestureDetector(
              key: const Key('mini_progress'),
              behavior: HitTestBehavior.translucent,
              onTapUp: duration.inMilliseconds <= 0
                  ? null
                  : (details) {
                      final width = context.size?.width ?? 0;
                      if (width <= 0) return;
                      final fraction = (details.localPosition.dx / width).clamp(
                        0.0,
                        1.0,
                      );
                      onSeek(
                        Duration(
                          milliseconds: (duration.inMilliseconds * fraction)
                              .round(),
                        ),
                      );
                    },
              child: SizedBox(
                height: 16,
                child: Align(
                  alignment: Alignment.center,
                  child: Stack(
                    children: [
                      Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.3,
                          ),
                          borderRadius: BorderRadius.circular(AppTokens.rFull),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: progress.clamp(0.0, 1.0),
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(
                              AppTokens.rFull,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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

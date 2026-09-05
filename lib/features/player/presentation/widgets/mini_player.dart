import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/player/player_controller.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../features/ads/interstitial_ads_provider.dart';
import '../../../../shared/widgets/artwork_view.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../presentation/screens/full_player_screen.dart';
import '../providers/player_providers.dart';

/// Compact now-playing bar docked above the bottom navigation.
///
/// Design: Premium elevated surface with artwork, metadata, progress indicator,
/// and transport controls. Seamless Hero transition to full-screen player.
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  static const _heroTag = 'player_artwork_hero';

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _swipeAnim;

  /// Drives [_dragDx] while an exit / settle animation is playing.
  Animation<double>? _swipeTween;

  /// Current horizontal pixel offset of the card. Follows the finger during a
  /// drag and is animated by [_swipeAnim] during settle / commit.
  double _dragDx = 0;
  bool _fingerDown = false;

  // Step availability, refreshed on every build so drag-end handlers don't
  // have to synchronously read providers.
  bool _hasPrevious = false;
  bool _hasNext = false;

  @override
  void initState() {
    super.initState();
    _swipeAnim = AnimationController(vsync: this, duration: AppTokens.normal)
      ..addListener(() {
        final anim = _swipeTween;
        if (anim != null && mounted) {
          setState(() => _dragDx = anim.value);
        }
      });
  }

  @override
  void dispose() {
    _swipeAnim.dispose();
    super.dispose();
  }

  /// Animates the card's horizontal offset from its current value to [target].
  void _animateDxTo(
    double target, {
    Duration? duration,
    Curve curve = AppTokens.easeOut,
    VoidCallback? onDone,
  }) {
    _swipeTween = Tween<double>(
      begin: _dragDx,
      end: target,
    ).animate(CurvedAnimation(parent: _swipeAnim, curve: curve));
    if (duration != null) {
      _swipeAnim.duration = duration;
    }
    _swipeAnim.forward(from: 0).whenComplete(() => onDone?.call());
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    // A new finger grab always takes over from any running animation.
    _swipeAnim.stop();
    _fingerDown = true;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_fingerDown) {
      return;
    }
    setState(() => _dragDx += details.delta.dx);
  }

  /// Swipe right → next song, swipe left → previous song — animated: the card
  /// follows the finger, flies out on commit and the new track slides in from
  /// the opposite edge. With shuffle on, Next follows the engine's shuffled
  /// order (random) while Previous always walks back to the song that just
  /// played (never random).
  void _onHorizontalDragEnd(DragEndDetails details) {
    _fingerDown = false;
    if (!mounted) {
      return;
    }
    final width = context.size?.width ?? 0;
    final velocity = details.velocity.pixelsPerSecond.dx;
    // A commit happens on a real drag (past 28% of the card width) or a
    // decisive fling in the same direction as the offset.
    final dir = _dragDx == 0 ? velocity.sign : _dragDx.sign;
    final commit =
        _dragDx.abs() > width * 0.28 ||
        (velocity.abs() > 600 && velocity.sign == dir);
    final canStep = dir > 0 ? _hasNext : _hasPrevious;
    if (!commit || dir == 0 || !canStep) {
      _animateDxTo(0);
      return;
    }

    // 1) Fly the current card out in the swipe direction.
    _animateDxTo(dir * width * 1.1, duration: AppTokens.fast, curve: AppTokens.easeIn, onDone: () {
      // 2) Skip. The ad hook matches the transport-button behaviour.
      ref.read(interstitialAdControllerProvider).onSkipClicked();
      if (dir > 0) {
        ref.read(playerProvider).next();
      } else {
        ref.read(playerProvider).previous();
      }
      if (!mounted) {
        return;
      }
      // 3) The next track slides in from the opposite side.
      setState(() => _dragDx = -dir * width * 0.45);
      _animateDxTo(0, duration: AppTokens.normal);
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(playbackStateProvider);
    final current = snapshot.current;

    if (current == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final canStep =
        snapshot.queueLength > 1 || snapshot.repeatMode == RepeatMode.all;
    _hasPrevious = canStep && snapshot.currentIndex >= 0;
    _hasNext = canStep && snapshot.currentIndex >= 0;

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
          ref.read(playerProvider).clearSession();
        }
      },
      // Animated horizontal card swipe (see [_onHorizontalDragEnd]). The
      // recognizers live on the whole card — artwork, title, progress bar and
      // transport controls included — so a swipe started anywhere skips.
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: Transform.translate(
        offset: Offset(_dragDx, 0),
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
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 68),
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
                    heroTag: MiniPlayer._heroTag,
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
                  Semantics(
                    button: true,
                    label: 'Previous',
                    child: _TransportButton(
                      icon: Icons.skip_previous_rounded,
                      enabled: _hasPrevious,
                      onTap: () {
                        ref
                            .read(interstitialAdControllerProvider)
                            .onSkipClicked();
                        ref.read(playerProvider).previous();
                      },
                      colorScheme: colorScheme,
                    ),
                  ),
                  const SizedBox(width: AppTokens.s2),
                  Semantics(
                    button: true,
                    label: snapshot.isPlaying ? 'Pause' : 'Play',
                    child: PressableScale(
                      onTap: () => ref.read(playerProvider).togglePlay(),
                      child: SizedBox(
                        width: AppTokens.touchTarget,
                        height: AppTokens.touchTarget,
                        child: Center(
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
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.35,
                                  ),
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
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTokens.s2),
                  Semantics(
                    button: true,
                    label: 'Next',
                    child: _TransportButton(
                      icon: Icons.skip_next_rounded,
                      enabled: _hasNext,
                      onTap: () {
                        ref
                            .read(interstitialAdControllerProvider)
                            .onSkipClicked();
                        ref.read(playerProvider).next();
                      },
                      colorScheme: colorScheme,
                    ),
                  ),
                  const SizedBox(width: AppTokens.s2),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }

  void _openFullPlayer(BuildContext context) {
    // Immersive full player: push on the root navigator so it covers the whole
    // shell, including this MiniPlayer and the bottom bar.
    Navigator.of(context, rootNavigator: true).push(
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
      child: SizedBox(
        // A 48dp hit area for accessibility, with the smaller visual circle
        // centered inside so the compact bar keeps its visual proportions.
        width: AppTokens.touchTarget,
        height: AppTokens.touchTarget,
        child: Center(
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
        ),
      ),
    );
  }
}

class _MiniProgress extends ConsumerWidget {
  const _MiniProgress({required this.snapshot, required this.onSeek});

  final PlayerSnapshot snapshot;
  final ValueChanged<Duration> onSeek;

  void _seekAt(BuildContext context, double dx, Duration duration) {
    final width = context.size?.width ?? 0;
    if (width <= 0) {
      return;
    }
    final fraction = (dx / width).clamp(0.0, 1.0);
    onSeek(
      Duration(milliseconds: (duration.inMilliseconds * fraction).round()),
    );
  }

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
            // bar is easy to seek without hurting the compact layout. A tap
            // seeks to the tapped fraction. Horizontal drags deliberately do
            // NOT belong to this region: they belong to the whole-card swipe
            // (next/previous), so a swipe started over the progress bar works
            // exactly like one started anywhere else on the card.
            return GestureDetector(
              key: const Key('mini_progress'),
              behavior: HitTestBehavior.translucent,
              onTapUp: duration.inMilliseconds <= 0
                  ? null
                  : (details) =>
                        _seekAt(context, details.localPosition.dx, duration),
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

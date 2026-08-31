import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/ingest/artwork/artwork_file_cache.dart';
import '../../../player/presentation/providers/player_providers.dart';

/// Can be disabled in tests to prevent infinite animation.
bool rotatingArtworkEnabled = true;

/// Public function to disable rotating artwork animations for testing.
void disableRotatingArtworkForTesting() {
  rotatingArtworkEnabled = false;
}

/// Circular rotating artwork for the full-screen player.
///
/// The artwork continuously rotates when the song is playing and pauses
/// when the song is paused. This is the visual centrepiece of the player.
class RotatingArtwork extends ConsumerStatefulWidget {
  const RotatingArtwork({
    super.key,
    required this.path,
    required this.size,
    this.heroTag,
    this.borderRadius = AppTokens.rFull,
  });

  final String? path;
  final double size;
  final Object? heroTag;
  final double borderRadius;

  @override
  ConsumerState<RotatingArtwork> createState() => RotatingArtworkState();
}

/// Test-only observation of the rotation controller, so widget tests can
/// assert the disc keeps spinning across a song change without reaching into
/// private state.
abstract final class RotatingArtworkDebug {
  static bool isRotating(GlobalKey<RotatingArtworkState> key) =>
      key.currentState != null &&
      key.currentState!._rotationController.isAnimating;
}

class RotatingArtworkState extends ConsumerState<RotatingArtwork>
    with TickerProviderStateMixin {
  late final AnimationController _rotationController;
  late final AnimationController _glowController;
  bool _wasPlaying = false;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(seconds: 12),
      vsync: this,
    );
    _glowController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    // Both animations start/stop via _syncRotationState, keyed off play state,
    // so neither ticks while the track is paused (sparing CPU/battery during
    // background playback).
    _syncRotationState();
  }

  @override
  void didUpdateWidget(RotatingArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      // reset() sets the value back to the lower bound, which internally
      // STOPS a repeating controller. Restarting only on a play/pause flip
      // (the old behaviour) meant a track change while playing froze the
      // disc until the user paused and resumed. Restart here whenever the
      // disc was spinning before the song changed.
      final wasSpinning = _rotationController.isAnimating;
      _rotationController.reset();
      if (wasSpinning && rotatingArtworkEnabled) {
        _rotationController.repeat();
        _glowController.repeat(reverse: true);
      }
    }
    _syncRotationState();
  }

  void _syncRotationState() {
    final isPlaying = ref.read(playbackStateProvider).isPlaying;
    if (isPlaying != _wasPlaying) {
      _wasPlaying = isPlaying;
      if (isPlaying && rotatingArtworkEnabled) {
        _rotationController.repeat();
        _glowController.repeat(reverse: true);
      } else {
        _rotationController.stop();
        _glowController.stop();
      }
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watching isPlaying also lets _syncRotationState react to
    // play/pause transitions (initState/didUpdateWidget do not fire on a
    // provider change, so without this the artwork would keep rotating and
    // glowing while paused). Watching only the narrow boolean (instead of the
    // whole snapshot) means a buffering/duration/seek emission — which changes
    // nothing the disc cares about — does not rebuild this widget.
    final isPlaying = ref.watch(playbackStateProvider.select((s) => s.isPlaying));
    _syncRotationState();
    final file = ArtworkFileCache.resolve(widget.path);

    Widget artwork = AnimatedSwitcher(
      duration: AppTokens.slow,
      switchInCurve: AppTokens.easeOut,
      switchOutCurve: AppTokens.easeIn,
      child: file != null
          ? _RotatingArtworkImage(
              key: ValueKey(widget.path),
              file: file,
              size: widget.size,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              rotationController: _rotationController,
              showShadow: true,
            )
          : _ArtworkFallback(
              key: const ValueKey('fallback'),
              size: widget.size,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              showShadow: true,
            ),
    );

    if (widget.heroTag != null) {
      artwork = Hero(tag: widget.heroTag!, child: artwork);
    }

    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, _) {
        return Stack(
          alignment: Alignment.center,
          children: [
            if (isPlaying)
              Container(
                width: widget.size + 8,
                height: widget.size + 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.accent.withValues(
                        alpha: 0.06 + 0.02 * _glowController.value,
                      ),
                      AppColors.accent.withValues(alpha: 0.01),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              )
            else
              const SizedBox.shrink(),
            artwork,
          ],
        );
      },
    );
  }
}

class _RotatingArtworkImage extends StatefulWidget {
  const _RotatingArtworkImage({
    super.key,
    required this.file,
    required this.size,
    required this.borderRadius,
    required this.rotationController,
    this.showShadow = true,
  });

  final File file;
  final double size;
  final BorderRadius borderRadius;
  final AnimationController rotationController;
  final bool showShadow;

  @override
  State<_RotatingArtworkImage> createState() => _RotatingArtworkImageState();
}

class _RotatingArtworkImageState extends State<_RotatingArtworkImage>
    with SingleTickerProviderStateMixin {
  late final Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _rotationAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: widget.rotationController, curve: Curves.linear),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget child = AnimatedBuilder(
      animation: _rotationAnimation,
      builder: (context, child) {
        return Transform.rotate(
          angle: _rotationAnimation.value * 2 * 3.14159,
          child: child,
        );
      },
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Image.file(
            widget.file,
            fit: BoxFit.cover,
            cacheWidth: ArtworkFileCache.decodeWidth(
              widget.size,
              MediaQuery.devicePixelRatioOf(context),
            ),
            gaplessPlayback: false,
            frameBuilder: (context, child, frame, wasLoaded) {
              if (wasLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: child,
              );
            },
            errorBuilder: (_, _, _) {
              ArtworkFileCache.forget(widget.file.path);
              return _ArtworkFallback(
                size: widget.size,
                borderRadius: widget.borderRadius,
                showShadow: widget.showShadow,
              );
            },
          ),
        ),
      ),
    );

    if (widget.showShadow) {
      child = Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: _artworkShadow(theme, isDark),
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
    this.showShadow = true,
  });

  final double size;
  final BorderRadius borderRadius;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
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
        boxShadow: showShadow ? _artworkShadow(theme, isDark) : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Concentric rings
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
          Icon(
            Icons.music_note_rounded,
            size: size * 0.28,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
          ),
        ],
      ),
    );
  }
}

List<BoxShadow> _artworkShadow(ThemeData theme, bool isDark) => [
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
];

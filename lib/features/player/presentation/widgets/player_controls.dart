import 'package:flutter/material.dart' hide RepeatMode;

import '../../../../core/player/player_controller.dart';
import '../../../../app/theme/app_tokens.dart';

/// Central playback controls for the full-screen player.
///
/// Layout:  [shuffle]  [previous]  [rewind-10]  [play/pause]  [forward-10]  [next]  [repeat]
///
/// Play/pause is the largest element with a prominent shadow.
/// Rewind/forward-10 are compact glass buttons flanking play/pause.
/// Shuffle/repeat are smaller toggle buttons with active-state coloring.
class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.snapshot,
    required this.onTogglePlay,
    required this.onPrevious,
    required this.onNext,
    required this.onRewind10,
    required this.onForward10,
    required this.onToggleShuffle,
    required this.onToggleRepeat,
  });

  final PlayerSnapshot snapshot;
  final VoidCallback onTogglePlay;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onRewind10;
  final VoidCallback onForward10;
  final VoidCallback onToggleShuffle;
  final VoidCallback onToggleRepeat;

  bool get _canStep =>
      snapshot.queueLength > 1 || snapshot.repeatMode == RepeatMode.all;

  bool get _canPrevious => _canStep && snapshot.currentIndex >= 0;

  bool get _canNext => _canStep && snapshot.currentIndex >= 0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final playFootprint = 68.0;
    final unit = AppTokens.touchTarget; // 48

    return LayoutBuilder(
      builder: (context, constraints) {
        final needed = playFootprint + unit * 6;
        final scale = constraints.maxWidth < needed
            ? constraints.maxWidth / needed
            : 1.0;
        final baseUnit = unit * scale;
        final basePlay = playFootprint * scale;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _ControlButton(
              width: baseUnit,
              icon: snapshot.shuffleEnabled
                  ? Icons.shuffle_on_rounded
                  : Icons.shuffle_rounded,
              size: 22,
              isActive: snapshot.shuffleEnabled,
              activeColor: colorScheme.primary,
              inactiveColor: colorScheme.onSurfaceVariant,
              onTap: onToggleShuffle,
            ),
            _ControlButton(
              width: baseUnit,
              icon: Icons.skip_previous_rounded,
              size: 30,
              isActive: false,
              activeColor: colorScheme.onSurface,
              inactiveColor: _canPrevious
                  ? colorScheme.onSurface
                  : colorScheme.onSurface.withValues(alpha: 0.2),
              onTap: _canPrevious ? onPrevious : null,
            ),
            _TenSecButton(
              width: baseUnit,
              icon: Icons.replay_10_rounded,
              onTap: onRewind10,
              color: colorScheme.onSurface,
            ),
            _PlayButton(
              diameter: basePlay,
              isPlaying: snapshot.isPlaying,
              onTap: onTogglePlay,
            ),
            _TenSecButton(
              width: baseUnit,
              icon: Icons.forward_10_rounded,
              onTap: onForward10,
              color: colorScheme.onSurface,
            ),
            _ControlButton(
              width: baseUnit,
              icon: Icons.skip_next_rounded,
              size: 30,
              isActive: false,
              activeColor: colorScheme.onSurface,
              inactiveColor: _canNext
                  ? colorScheme.onSurface
                  : colorScheme.onSurface.withValues(alpha: 0.2),
              onTap: _canNext ? onNext : null,
            ),
            _ControlButton(
              width: baseUnit,
              icon: snapshot.repeatMode == RepeatMode.one
                  ? Icons.repeat_one_on_rounded
                  : snapshot.repeatMode == RepeatMode.all
                  ? Icons.repeat_on_rounded
                  : Icons.repeat_rounded,
              size: 22,
              isActive: snapshot.repeatMode != RepeatMode.off,
              activeColor: colorScheme.primary,
              inactiveColor: colorScheme.onSurfaceVariant,
              onTap: onToggleRepeat,
            ),
          ],
        );
      },
    );
  }
}

class _PlayButton extends StatefulWidget {
  const _PlayButton({
    required this.diameter,
    required this.isPlaying,
    required this.onTap,
  });

  final double diameter;
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppTokens.fast);
    _scaleAnim = Tween<double>(
      begin: 1,
      end: 0.92,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnim.value, child: child);
        },
        child: Container(
          width: widget.diameter,
          height: widget.diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.onSurface,
            boxShadow: [
              BoxShadow(
                color: colorScheme.onSurface.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 34 * (widget.diameter / 68),
            color: colorScheme.surface,
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.width,
    required this.icon,
    required this.size,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    this.onTap,
  });

  final double width;
  final IconData icon;
  final double size;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: AppTokens.touchTarget,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: size),
        color: isActive ? activeColor : inactiveColor,
        splashRadius: 24,
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// Compact circular glass button used for rewind/forward-10 controls.
class _TenSecButton extends StatelessWidget {
  const _TenSecButton({
    required this.width,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  final double width;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: width,
      height: AppTokens.touchTarget,
      child: IconButton(
        onPressed: onTap,
        tooltip: 'Seek 10 seconds',
        icon: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.55),
            border: Border.all(
              color: colorScheme.onSurface.withValues(alpha: 0.08),
              width: AppTokens.borderHairline,
            ),
          ),
          child: Icon(icon, size: 24, color: color),
        ),
        padding: EdgeInsets.zero,
        splashRadius: 24,
      ),
    );
  }
}

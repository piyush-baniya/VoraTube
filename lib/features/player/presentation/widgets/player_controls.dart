import 'package:flutter/material.dart' hide RepeatMode;

import '../../../../core/player/player_controller.dart';
import '../../../../app/theme/app_tokens.dart';

/// Central playback controls for the full-screen player.
///
/// Layout:  [shuffle]  [previous]  [play/pause]  [next]  [repeat]
///
/// Play/pause is the largest element with a prominent shadow.
/// Shuffle/repeat are smaller toggle buttons with active-state coloring.
class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.snapshot,
    required this.onTogglePlay,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleShuffle,
    required this.onToggleRepeat,
  });

  final PlayerSnapshot snapshot;
  final VoidCallback onTogglePlay;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleShuffle;
  final VoidCallback onToggleRepeat;

  bool get _canPrevious =>
      snapshot.currentIndex > 0 || snapshot.repeatMode == RepeatMode.all;

  bool get _canNext =>
      snapshot.currentIndex < snapshot.queueLength - 1 ||
      snapshot.repeatMode == RepeatMode.all;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _ControlButton(
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
          icon: Icons.skip_previous_rounded,
          size: 30,
          isActive: false,
          activeColor: colorScheme.onSurface,
          inactiveColor: _canPrevious
              ? colorScheme.onSurface
              : colorScheme.onSurface.withValues(alpha: 0.2),
          onTap: _canPrevious ? onPrevious : null,
        ),
        _PlayButton(isPlaying: snapshot.isPlaying, onTap: onTogglePlay),
        _ControlButton(
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
  }
}

class _PlayButton extends StatefulWidget {
  const _PlayButton({required this.isPlaying, required this.onTap});

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
          width: 68,
          height: 68,
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
            size: 34,
            color: colorScheme.surface,
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.size,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    this.onTap,
  });

  final IconData icon;
  final double size;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppTokens.touchTarget,
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

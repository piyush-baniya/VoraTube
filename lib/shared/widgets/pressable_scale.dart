import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

/// Lightweight press-feedback wrapper using GPU-friendly Transform.scale.
///
/// Wraps any child with a subtle scale-down on tap, providing tactile
/// feedback without expensive rebuilds. No AnimationController needed —
/// uses implicit animations for zero-overhead idle state.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.duration = AppTokens.fast,
    this.curve = AppTokens.easeOut,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final Duration duration;
  final Curve curve;
  final bool enabled;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _anim = Tween<double>(
      begin: 1,
      end: widget.scale,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));
  }

  @override
  void didUpdateWidget(PressableScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scale != widget.scale) {
      _anim = Tween<double>(
        begin: 1,
        end: widget.scale,
      ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      onLongPressStart: (_) => _controller.forward(),
      onLongPressEnd: (_) {
        _controller.reverse();
        widget.onLongPress?.call();
      },
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          return Transform.scale(scale: _anim.value, child: child);
        },
        child: widget.child,
      ),
    );
  }
}

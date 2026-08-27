import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

/// GPU-friendly press animation using Transform.scale.
///
/// Provides immediate, lightweight feedback without rebuilding
/// the entire widget tree. Uses a dedicated AnimationController
/// for 60fps performance.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.duration = AppTokens.fast,
    this.curve = AppTokens.press,
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
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.scale,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
      reverseCurve: Curves.easeOutCubic,
    ));
  }

  @override
  void didUpdateWidget(PressableScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scale != widget.scale ||
        oldWidget.duration != widget.duration ||
        oldWidget.curve != widget.curve) {
      _scaleAnimation = Tween<double>(
        begin: 1.0,
        end: widget.scale,
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: widget.curve,
        reverseCurve: Curves.easeOutCubic,
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onTap != null || widget.onLongPress != null) {
      _controller.forward();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap?.call();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    if (widget.onTap != null || widget.onLongPress != null) {
      _controller.forward();
    }
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    _controller.reverse();
    widget.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onLongPressStart: _handleLongPressStart,
      onLongPressEnd: _handleLongPressEnd,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: widget.child,
      ),
    );
  }
}

/// Pressable card with elevation and surface color changes.
///
/// Provides a more premium card interaction with subtle elevation
/// and surface color transition on press.
class PressableCard extends StatefulWidget {
  const PressableCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding,
    this.margin,
    this.borderRadius,
    this.elevation = 0,
    this.pressedElevation = 4,
    this.color,
    this.pressedColor,
    this.border,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final double elevation;
  final double pressedElevation;
  final Color? color;
  final Color? pressedColor;
  final BoxBorder? border;
  final Clip clipBehavior;

  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _elevationAnimation;
  late final Animation<Color?> _colorAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppTokens.fast,
      vsync: this,
    );
    _elevationAnimation = Tween<double>(
      begin: widget.elevation,
      end: widget.pressedElevation,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: AppTokens.press,
      reverseCurve: Curves.easeOutCubic,
    ));

    final theme = Theme.of(context);
    final defaultColor = widget.color ?? theme.colorScheme.surfaceContainerLow;
    final defaultPressedColor = widget.pressedColor ??
        theme.colorScheme.surfaceContainerHigh;

    _colorAnimation = ColorTween(
      begin: defaultColor,
      end: defaultPressedColor,
    ).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onTap != null || widget.onLongPress != null) {
      _isPressed = true;
      _controller.forward();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (_isPressed) {
      _isPressed = false;
      _controller.reverse();
    }
  }

  void _handleTapCancel() {
    if (_isPressed) {
      _isPressed = false;
      _controller.reverse();
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_isPressed) {
      _isPressed = false;
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveBorderRadius = widget.borderRadius ?? BorderRadius.circular(AppTokens.rLg);

    return Listener(
      onPointerDown: (_) => _handleTapDown(TapDownDetails(kind: PointerDeviceKind.touch)),
      onPointerUp: (_) => _handleTapUp(TapUpDetails(kind: PointerDeviceKind.touch)),
      onPointerCancel: _handlePointerCancel,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Container(
              margin: widget.margin,
              padding: widget.padding,
              decoration: BoxDecoration(
                color: _colorAnimation.value,
                borderRadius: effectiveBorderRadius,
                border: widget.border,
                boxShadow: _elevationAnimation.value > 0
                    ? [
                        BoxShadow(
                          color: theme.colorScheme.shadow
                              .withValues(alpha: 0.15),
                          blurRadius: _elevationAnimation.value * 4,
                          offset: Offset(0, _elevationAnimation.value),
                        ),
                      ]
                    : null,
              ),
              clipBehavior: widget.clipBehavior,
              child: child,
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// Pressable ink well with customizable splash color.
///
/// Uses Material's ink splash for a more traditional ripple effect
/// when GPU-friendly scale isn't desired.
class PressableInkWell extends StatelessWidget {
  const PressableInkWell({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.splashColor,
    this.highlightColor,
    this.radius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final Color? splashColor;
  final Color? highlightColor;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: borderRadius ?? BorderRadius.circular(AppTokens.rMd),
        splashColor: splashColor ?? theme.colorScheme.primary.withValues(alpha: 0.12),
        highlightColor: highlightColor ?? theme.colorScheme.primary.withValues(alpha: 0.06),
        radius: radius,
        child: child,
      ),
    );
  }
}
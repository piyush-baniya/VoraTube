import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

/// One-shot entrance reveal for list items scrolling into view.
///
/// Plays a single fade + subtle vertical slide the first time the item builds,
/// then never animates again. Because the work is a one-shot
/// [AnimationController] per visible item (not a per-frame callback), it adds
/// no cost while scrolling and cannot cause jank — items simply appear as the
/// list builder recycles them into the viewport.
class ScrollReveal extends StatefulWidget {
  const ScrollReveal({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<ScrollReveal> createState() => _ScrollRevealState();
}

class _ScrollRevealState extends State<ScrollReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppTokens.normal);
    _opacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: AppTokens.easeOut));
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: AppTokens.easeOut));
    if (widget.enabled) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(ScrollReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

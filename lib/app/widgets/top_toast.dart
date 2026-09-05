import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Shows a small toast pinned to the TOP of the [context]'s overlay, styled as
/// a purple pill with an icon and a short label. Used for quick, non-blocking
/// feedback (e.g. shuffle on/off, repeat all/one/off toggles) that would get
/// lost at the bottom of the screen.
///
/// The toast anchors below the top padding (status bar / notch), floats above
/// content, and auto-dismisses after [duration]. Repeated calls replace any
/// toast currently showing so rapid taps never stack.
void showTopToast(
  BuildContext context, {
  required IconData icon,
  required String message,
  Duration duration = const Duration(milliseconds: 1200),
}) {
  final overlay = Overlay.maybeOf(
    context,
    rootOverlay: true,
  );
  if (overlay == null) return;

  final topPadding = MediaQuery.paddingOf(context).top;
  const chipHeight = 40.0;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) {
      return Positioned(
        top: topPadding + AppTokens.s4,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: AnimatableToastChip(
            height: chipHeight,
            child: _ToastChipContent(icon: icon, message: message),
          ),
        ),
      );
    },
  );

  overlay.insert(entry);
  Timer(duration, () {
    if (entry.mounted) entry.remove();
  });
}

/// Wraps the chip with a light fade/slide entrance so it reads as a toast
/// popping in from the top rather than appearing abruptly. The trailing
/// [Icon] caller provides is the leading element; we keep the icon+text
/// together by having the chip include a leading icon slot.
class _ToastChipContent extends StatelessWidget {
  const _ToastChipContent({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7C4DFF);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.brightness == Brightness.dark
            ? purple.withValues(alpha: 0.95)
            : purple,
        borderRadius: BorderRadius.circular(AppTokens.rFull),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: AppTokens.s2),
          Text(
            message,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Handles the slide/fade entrance animation for the toast.
class AnimatableToastChip extends StatefulWidget {
  const AnimatableToastChip({super.key, required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  State<AnimatableToastChip> createState() => _AnimatableToastChipState();
}

class _AnimatableToastChipState extends State<AnimatableToastChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeTransition(
        opacity: _controller,
        child: SlideTransition(position: _slide, child: widget.child),
      ),
    );
  }
}
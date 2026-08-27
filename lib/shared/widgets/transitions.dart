import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_tokens.dart';

/// Fade-through transition for equal-hierarchy content swaps (library
/// sections, tab bodies). Intentionally subtle — just a soft opacity
/// shift with minimal vertical movement.
class FadeThroughSwitcher extends StatelessWidget {
  const FadeThroughSwitcher({
    super.key,
    required this.child,
    this.duration = AppTokens.normal,
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: AppTokens.easeOut,
      switchOutCurve: AppTokens.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.008),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey(child.hashCode), child: child),
    );
  }
}

/// Consistent shared-axis-X page push used for drill-downs.
/// Uses the standard VoraTube transition duration and curve.
PageRouteBuilder<T> pushSharedAxis<T extends Object?>(
  BuildContext context,
  Widget screen, {
  Duration? transitionDuration,
  Duration? reverseTransitionDuration,
}) {
  return PageRouteBuilder<T>(
    transitionDuration: transitionDuration ?? AppTokens.medium,
    reverseTransitionDuration: reverseTransitionDuration ?? AppTokens.normal,
    pageBuilder: (_, _, _) => screen,
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppTokens.easeOut,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.04, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

/// Shared-axis-Y page push for bottom-up transitions (modals, players).
PageRouteBuilder<T> pushSharedAxisVertical<T extends Object?>(
  BuildContext context,
  Widget screen, {
  Duration? transitionDuration,
  Duration? reverseTransitionDuration,
}) {
  return PageRouteBuilder<T>(
    transitionDuration: transitionDuration ?? AppTokens.medium,
    reverseTransitionDuration: reverseTransitionDuration ?? AppTokens.normal,
    pageBuilder: (_, _, _) => screen,
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppTokens.easeOut,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

/// Fade + scale page transition for immersive transitions (full player).
PageRouteBuilder<T> pushFadeScale<T extends Object?>(
  BuildContext context,
  Widget screen, {
  Duration? transitionDuration,
  Duration? reverseTransitionDuration,
}) {
  return PageRouteBuilder<T>(
    transitionDuration: transitionDuration ?? AppTokens.slow,
    reverseTransitionDuration: reverseTransitionDuration ?? AppTokens.medium,
    pageBuilder: (_, _, _) => screen,
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppTokens.easeOut,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Premium Hero transition for full player with custom curve.
PageRouteBuilder<T> pushHero<T extends Object?>(
  BuildContext context,
  Widget screen, {
  Duration? transitionDuration,
  Duration? reverseTransitionDuration,
}) {
  return PageRouteBuilder<T>(
    transitionDuration: transitionDuration ?? AppTokens.slow,
    reverseTransitionDuration: reverseTransitionDuration ?? AppTokens.medium,
    pageBuilder: (_, _, _) => screen,
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppTokens.easeOutExpo,
      );
      return FadeTransition(
        opacity: curved,
        child: child,
      );
    },
  );
}

/// Compact section header used above horizontal collections.
/// Uses accent color for the small leading indicator bar.
class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s5,
        AppTokens.s5,
        AppTokens.s5,
        AppTokens.s2,
      ),
      child: Row(
        children: [
          // Accent bar indicator.
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: AppTokens.s2),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Renders [AsyncValue] states while keeping previous data visible during
/// refetches, avoiding jarring full-screen spinners on refresh.
class AsyncValueSwitcher<T> extends StatelessWidget {
  const AsyncValueSwitcher({
    super.key,
    required this.value,
    required this.data,
    this.loading,
    this.errorBuilder,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final Widget? loading;
  final Widget Function(Object error, StackTrace? stack)? errorBuilder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: false,
      data: data,
      loading: () =>
          value.hasValue ? data(value.value as T) : (loading ?? _spinner),
      error: (e, st) {
        if (value.hasValue) {
          return data(value.value as T);
        }
        return errorBuilder?.call(e, st) ?? _spinner;
      },
    );
  }

  Widget get _spinner =>
      const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
}

/// Animated list item insertion/removal for queue and playlists.
class AnimatedListItem extends StatefulWidget {
  const AnimatedListItem({
    super.key,
    required this.child,
    this.duration = AppTokens.medium,
    this.curve = AppTokens.easeOut,
    this.axis = Axis.vertical,
  });

  final Widget child;
  final Duration duration;
  final Curve curve;
  final Axis axis;

  @override
  State<AnimatedListItem> createState() => _AnimatedListItemState();
}

class _AnimatedListItemState extends State<AnimatedListItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );
    _slide = Tween<Offset>(
      begin: widget.axis == Axis.vertical
          ? const Offset(0, 0.1)
          : const Offset(0.1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> remove() async {
    await _controller.reverse();
    if (mounted) {
      // Parent should remove from list after animation
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}

/// Staggered list animation for multiple items appearing sequentially.
class StaggeredList extends StatelessWidget {
  const StaggeredList({
    super.key,
    required this.children,
    this.duration = AppTokens.medium,
    this.staggerDelay = AppTokens.fast,
    this.curve = AppTokens.easeOut,
    this.axis = Axis.vertical,
    this.mainAxisSize = MainAxisSize.min,
  });

  final List<Widget> children;
  final Duration duration;
  final Duration staggerDelay;
  final Curve curve;
  final Axis axis;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: mainAxisSize,
      children: [
        for (int i = 0; i < children.length; i++)
          _StaggeredItem(
            index: i,
            delay: staggerDelay * i,
            duration: duration,
            curve: curve,
            child: children[i],
          ),
      ],
    );
  }
}

class _StaggeredItem extends StatefulWidget {
  const _StaggeredItem({
    required this.index,
    required this.delay,
    required this.duration,
    required this.curve,
    required this.child,
  });

  final int index;
  final Duration delay;
  final Duration duration;
  final Curve curve;
  final Widget child;

  @override
  State<_StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<_StaggeredItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}
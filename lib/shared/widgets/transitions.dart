import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fade-through transition for equal-hierarchy content swaps (library
/// sections, tab bodies). Intentionally subtle.
class FadeThroughSwitcher extends StatelessWidget {
  const FadeThroughSwitcher({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 220),
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.012),
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

/// Shared-axis-X page push used for drill-downs (album Ã¢â€ â€™ songs).
PageRouteBuilder<T> pushSharedAxis<T extends Object?>(
  BuildContext context,
  Widget screen,
) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => screen,
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.06, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

/// Compact section header used above horizontal collections.
class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            letterSpacing: 1.2,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
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

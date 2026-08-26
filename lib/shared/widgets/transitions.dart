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
  Widget screen,
) {
  return PageRouteBuilder<T>(
    transitionDuration: AppTokens.medium,
    reverseTransitionDuration: AppTokens.normal,
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

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A single destination shown in [GlassNavBar].
class GlNavDestination {
  const GlNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Premium floating glass bottom navigation.
///
/// The bar is a rounded translucent surface with a subtle border and soft
/// shadow. The active destination is emphasized with a sliding purple glass
/// pill behind its icon, animating smoothly to each selection. Everything else
/// stays muted so the active tab reads instantly without visual noise.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<GlNavDestination> destinations;

  static const double _barHeight = 72;
  static const double _pillHeight = 56;
  static const double _innerPadX = AppTokens.s2;
  static const double _barMarginH = AppTokens.s3;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final barBg = isDark
        ? colorScheme.surfaceContainerHigh.withValues(alpha: 0.55)
        : colorScheme.surfaceContainerHigh.withValues(alpha: 0.65);

    final barBorder = colorScheme.outlineVariant.withValues(
      alpha: isDark ? 0.35 : 0.4,
    );
    final barShadow = Colors.black.withValues(alpha: isDark ? 0.45 : 0.12);

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          _barMarginH,
          AppTokens.s1,
          _barMarginH,
          AppTokens.s2,
        ),
        height: _barHeight,
        decoration: BoxDecoration(
          color: barBg,
          borderRadius: BorderRadius.circular(AppTokens.rXxl),
          border: Border.all(color: barBorder, width: AppTokens.borderThin),
          boxShadow: [
            BoxShadow(
              color: barShadow,
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final available = width - (_innerPadX * 2);
            final itemW = available / destinations.length;
            final centerX = _innerPadX + itemW * (currentIndex + 0.5);
            final alignX = -1 + (2 * centerX / width);

            return Stack(
              children: [
                AnimatedAlign(
                  alignment: Alignment(alignX, 0),
                  duration: AppTokens.medium,
                  curve: Curves.easeOutCubic,
                  child: Container(
                    width: itemW,
                    height: _pillHeight,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(AppTokens.rLg),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.35),
                        width: AppTokens.borderThin,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.18),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      Expanded(
                        child: _NavItem(
                          label: destinations[i].label,
                          icon: destinations[i].icon,
                          selectedIcon: destinations[i].selectedIcon,
                          isSelected: i == currentIndex,
                          onTap: () => onDestinationSelected(i),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final fg = isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return Semantics(
      selected: isSelected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rLg),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: AppTokens.fast,
              child: Icon(
                isSelected ? selectedIcon : icon,
                key: ValueKey(isSelected),
                size: 24,
                color: fg,
              ),
            ),
            const SizedBox(height: AppTokens.s1),
            AnimatedDefaultTextStyle(
              duration: AppTokens.fast,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: fg,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

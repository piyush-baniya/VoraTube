import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

/// Pulsing placeholder rows shown while paged queries load.
///
/// Matches the SongTile layout: 64px row with 48px artwork placeholder,
/// title bar, and subtitle bar. Uses a smooth pulse animation.
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.rows = 8});

  final int rows;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween(
    begin: 0.3,
    end: 0.6,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barColor = theme.colorScheme.surfaceContainerHighest;

    return FadeTransition(
      opacity: _opacity,
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s2,
        ),
        itemCount: widget.rows,
        separatorBuilder: (_, _) => const SizedBox(height: AppTokens.s1),
        itemBuilder: (context, index) {
          return SizedBox(
            height: 64,
            child: Row(
              children: [
                Container(
                  width: AppTokens.artworkLg,
                  height: AppTokens.artworkLg,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(AppTokens.rSm),
                  ),
                ),
                const SizedBox(width: AppTokens.s3),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: index.isEven ? 0.55 : 0.4,
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTokens.s2),
                      FractionallySizedBox(
                        widthFactor: 0.3,
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

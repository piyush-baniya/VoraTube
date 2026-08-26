import 'package:flutter/material.dart';

/// Pulsing placeholder rows shown while paged queries load.
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
    begin: 0.35,
    end: 0.75,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: widget.rows,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          return Row(
            children: [
              ColoredBox(
                color: barColor,
                child: const SizedBox(width: 48, height: 48),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FractionallySizedBox(
                      widthFactor: index.isEven ? 0.6 : 0.45,
                      child: Container(height: 13, color: barColor),
                    ),
                    const SizedBox(height: 8),
                    FractionallySizedBox(
                      widthFactor: 0.3,
                      child: Container(height: 11, color: barColor),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

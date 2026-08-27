import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

/// Pulsing placeholder rows shown while paged queries load.
///
/// Matches the SongTile layout: 64px row with 48px artwork placeholder,
/// title bar, and subtitle bar. Uses a smooth pulse animation.
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.rows = 8, this.type = SkeletonType.song});

  final int rows;
  final SkeletonType type;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

enum SkeletonType { song, album, artist, playlist, search }

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween(
    begin: 0.35,
    end: 0.65,
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
          switch (widget.type) {
            case SkeletonType.song:
              return _buildSongSkeleton(index, barColor);
            case SkeletonType.album:
              return _buildAlbumSkeleton(index, barColor);
            case SkeletonType.artist:
              return _buildArtistSkeleton(index, barColor);
            case SkeletonType.playlist:
              return _buildPlaylistSkeleton(index, barColor);
            case SkeletonType.search:
              return _buildSearchSkeleton(index, barColor);
          }
        },
      ),
    );
  }

  Widget _buildSongSkeleton(int index, Color barColor) {
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
                  widthFactor: index.isEven ? 0.55 : 0.45,
                  child: Container(
                    height: 13,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.s1),
                FractionallySizedBox(
                  widthFactor: 0.35,
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
  }

  Widget _buildAlbumSkeleton(int index, Color barColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(AppTokens.rLg),
          ),
        ),
        const SizedBox(height: AppTokens.s2),
        FractionallySizedBox(
          widthFactor: 0.8,
          child: Container(
            height: 14,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        const SizedBox(height: AppTokens.s1),
        FractionallySizedBox(
          widthFactor: 0.5,
          child: Container(
            height: 11,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildArtistSkeleton(int index, Color barColor) {
    return SizedBox(
      height: 72,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: barColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppTokens.s3),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: index.isEven ? 0.5 : 0.4,
                  child: Container(
                    height: 14,
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
  }

  Widget _buildPlaylistSkeleton(int index, Color barColor) {
    return SizedBox(
      height: 68,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
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
                  widthFactor: index.isEven ? 0.5 : 0.4,
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.s1),
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
  }

  Widget _buildSearchSkeleton(int index, Color barColor) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
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
                  widthFactor: index.isEven ? 0.6 : 0.5,
                  child: Container(
                    height: 13,
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
  }
}

/// Shimmer skeleton for grid layouts (albums, playlists).
class SkeletonGrid extends StatefulWidget {
  const SkeletonGrid({
    super.key,
    this.columns = 2,
    this.rows = 4,
    this.aspectRatio = 0.85,
    this.showLabel = true,
  });

  final int columns;
  final int rows;
  final double aspectRatio;
  final bool showLabel;

  @override
  State<SkeletonGrid> createState() => _SkeletonGridState();
}

class _SkeletonGridState extends State<SkeletonGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween(
    begin: 0.35,
    end: 0.65,
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
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppTokens.s3),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: widget.columns,
          mainAxisSpacing: AppTokens.s2,
          crossAxisSpacing: AppTokens.s2,
          childAspectRatio: widget.aspectRatio,
        ),
        itemCount: widget.columns * widget.rows,
        itemBuilder: (context, index) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(AppTokens.rLg),
                ),
              ),
              if (widget.showLabel) ...[
                const SizedBox(height: AppTokens.s2),
                FractionallySizedBox(
                  widthFactor: 0.9,
                  child: Container(
                    height: 13,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.s1),
                FractionallySizedBox(
                  widthFactor: 0.5,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

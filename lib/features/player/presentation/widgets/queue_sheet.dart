import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/player/player_controller.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../providers/player_providers.dart';

/// Premium bottom sheet displaying the current playback queue.
///
/// Shows the current song highlighted with artwork, with tap-to-jump,
/// swipe-to-remove, drag-to-reorder, and queue actions.
class QueueSheet extends ConsumerWidget {
  const QueueSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QueueSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(playbackStateProvider);
    if (!snapshot.hasTrack) {
      return const SizedBox.shrink();
    }

    final queue = ref.read(playerProvider).currentQueue;
    final currentIndex = snapshot.currentIndex;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTokens.rXxl),
            ),
            boxShadow: isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 24,
                      offset: const Offset(0, -8),
                      spreadRadius: -4,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 24,
                      offset: const Offset(0, -8),
                      spreadRadius: -4,
                    ),
                  ],
          ),
          child: Column(
            children: [
              // Drag handle with premium styling
              Container(
                margin: const EdgeInsets.only(
                  top: AppTokens.s3,
                  bottom: AppTokens.s2,
                ),
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),

              // Header with queue actions
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.s5,
                  AppTokens.s2,
                  AppTokens.s5,
                  AppTokens.s2,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Up Next',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: AppTokens.s1),
                          Text(
                            '${queue.length} ${queue.length == 1 ? 'song' : 'songs'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Clear queue button
                    if (queue.length > 1)
                      PressableScale(
                        onTap: () => _showClearConfirmation(context, ref),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.s3,
                            vertical: AppTokens.s1,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(
                              AppTokens.rFull,
                            ),
                            border: Border.all(
                              color: colorScheme.error.withValues(alpha: 0.3),
                              width: AppTokens.borderHairline,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.clear_all_rounded,
                                size: 16,
                                color: colorScheme.error,
                              ),
                              const SizedBox(width: AppTokens.s1),
                              Text(
                                'Clear',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              Divider(
                height: AppTokens.borderHairline,
                thickness: AppTokens.borderHairline,
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                indent: AppTokens.s5,
                endIndent: AppTokens.s5,
              ),

              // Queue list with reorder support
              Expanded(
                child: ReorderableListView.builder(
                  scrollController: scrollController,
                  padding: const EdgeInsets.only(
                    top: AppTokens.s2,
                    bottom: AppTokens.s8,
                  ),
                  itemCount: queue.length,
                  onReorderItem: (oldIndex, newIndex) {
                    // onReorderItem already reports the post-removal index,
                    // which is exactly the index just_audio's move() expects.
                    final player = ref.read(playerProvider);
                    player.moveQueueItem(oldIndex, newIndex);
                  },
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, index) {
                    final song = queue[index];
                    final isCurrent = index == currentIndex;

                    return _QueueTile(
                      key: ValueKey('queue_${song.identityKey}_$index'),
                      song: song,
                      index: index,
                      isCurrent: isCurrent,
                      onTap: () {
                        ref.read(playerProvider).jumpTo(index);
                      },
                      onRemove: () {
                        ref.read(playerProvider).removeAt(index);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showClearConfirmation(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Queue?'),
        content: const Text(
          'This will remove all songs from the queue except the currently playing one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            onPressed: () {
              Navigator.pop(context);
              ref.read(playerProvider).clearQueue();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _QueueTile extends ConsumerWidget {
  const _QueueTile({
    super.key,
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.onTap,
    required this.onRemove,
  });

  final SongRef song;
  final int index;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dismissible(
      key: ValueKey('queue_${song.identityKey}_$index'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: colorScheme.error,
          borderRadius: BorderRadius.circular(AppTokens.rMd),
        ),
        margin: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s1,
        ),
        child: Icon(
          Icons.remove_circle_outline_rounded,
          color: colorScheme.onError,
          size: 28,
        ),
      ),
      confirmDismiss: (direction) async {
        return true; // Could add confirmation dialog here
      },
      onDismissed: (_) => onRemove(),
      // Wrap the entire tile so long-press-and-drag reordering works anywhere
      // on the song, not just on the small drag-handle icon. A plain tap still
      // jumps to the track, and a quick horizontal swipe still removes the
      // song (Dismissible wins the gesture arena on immediate horizontal
      // drags, before the delayed long-press starts).
      child: ReorderableDelayedDragStartListener(
        index: index,
        child: PressableScale(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(
              horizontal: AppTokens.s4,
              vertical: AppTokens.s1,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s3,
              vertical: AppTokens.s2,
            ),
            decoration: BoxDecoration(
              color: isCurrent
                  ? colorScheme.primary.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTokens.rMd),
              border: isCurrent
                  ? Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.2),
                      width: AppTokens.borderHairline,
                    )
                  : null,
            ),
            child: Row(
              children: [
                // Drag handle — visual affordance only. The surrounding
                // ReorderableDelayedDragStartListener already makes the whole
                // row draggable, so the user can grab any part of the song.
                Semantics(
                  label: 'Reorder ${song.title}',
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(width: AppTokens.s2),
                // Position / equalizer
                Container(
                  width: 32,
                  height: 32,
                  decoration: isCurrent
                      ? BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        )
                      : null,
                  child: Center(
                    child: isCurrent
                        ? _EqualizerBars(color: colorScheme.primary)
                        : Text(
                            '${index + 1}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: AppTokens.s3),
                // Artwork
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.rSm),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: song.artPath != null && song.artPath!.isNotEmpty
                        ? Image.file(
                            File(song.artPath!),
                            fit: BoxFit.cover,
                            cacheWidth: 88,
                            gaplessPlayback: false,
                            errorBuilder: (_, _, _) => _fallback(theme),
                          )
                        : _fallback(theme),
                  ),
                ),
                const SizedBox(width: AppTokens.s3),
                // Metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: isCurrent
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isCurrent
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                      ),
                      if (song.artist != null)
                        Text(
                          song.artist!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                // Remove button
                PressableScale(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(AppTokens.s1),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallback(ThemeData theme) {
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note_rounded,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
      ),
    );
  }
}

class _EqualizerBars extends StatefulWidget {
  const _EqualizerBars({required this.color});

  final Color color;

  @override
  State<_EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<_EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final value = (_controller.value + delay) % 1.0;
            final height = 4.0 + (value * 14.0);

            return Padding(
              padding: const EdgeInsets.only(left: 1.5),
              child: Container(
                width: 2,
                height: height,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

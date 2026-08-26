import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/player/player_controller.dart';
import '../../../../app/theme/app_tokens.dart';
import '../providers/player_providers.dart';

/// Premium bottom sheet displaying the current playback queue.
///
/// Shows the current song highlighted, with tap-to-jump and
/// swipe-to-remove. Uses a drag-handle and consistent styling.
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
    final snapshot = ref.watch(playbackSnapshotProvider).value;
    if (snapshot == null || !snapshot.hasTrack) {
      return const SizedBox.shrink();
    }

    final queue = ref.read(playerProvider).currentQueue;
    final currentIndex = snapshot.currentIndex;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTokens.rXl),
            ),
          ),
          child: Column(
            children: [
              // Drag handle.
              Container(
                margin: const EdgeInsets.only(
                  top: AppTokens.s3,
                  bottom: AppTokens.s1,
                ),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.s6,
                  AppTokens.s3,
                  AppTokens.s6,
                  AppTokens.s2,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Queue',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${queue.length} songs',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),

              // Queue list.
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.only(
                    top: AppTokens.s2,
                    bottom: AppTokens.s8,
                  ),
                  itemCount: queue.length,
                  itemBuilder: (context, index) {
                    final song = queue[index];
                    final isCurrent = index == currentIndex;

                    return _QueueTile(
                      song: song,
                      index: index,
                      isCurrent: isCurrent,
                      onTap: () {
                        ref.read(playerProvider).jumpTo(index);
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
}

class _QueueTile extends ConsumerWidget {
  const _QueueTile({
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.onTap,
  });

  final SongRef song;
  final int index;
  final bool isCurrent;
  final VoidCallback onTap;

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
        color: colorScheme.error,
        child: Icon(
          Icons.remove_circle_outline_rounded,
          color: colorScheme.onError,
        ),
      ),
      onDismissed: (_) {
        ref.read(playerProvider).removeAt(index);
      },
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 36,
          height: 36,
          decoration: isCurrent
              ? BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.rXs),
                )
              : null,
          child: Center(
            child: isCurrent
                ? Icon(
                    Icons.equalizer_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  )
                : Text(
                    '${index + 1}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ),
        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
            color: isCurrent ? colorScheme.primary : colorScheme.onSurface,
            fontSize: 14,
          ),
        ),
        subtitle: song.artist != null
            ? Text(
                song.artist!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: 0,
        ),
      ),
    );
  }
}

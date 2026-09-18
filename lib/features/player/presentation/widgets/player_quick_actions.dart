import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/ui_customization/ui_layout.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../library/presentation/providers/library_view_providers.dart';
import '../providers/player_providers.dart';

/// The favorite (heart) toggle used by the player's `quickActions` block.
class PlayerFavoriteButton extends ConsumerWidget {
  const PlayerFavoriteButton({
    super.key,
    required this.identityKey,
    this.size = ComponentSize.medium,
  });

  final String identityKey;
  final ComponentSize size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFavorite = ref.watch(currentSongIsFavoriteProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final iconSize = switch (size) {
      ComponentSize.small => 20.0,
      ComponentSize.medium => 22.0,
      ComponentSize.large => 24.0,
    };

    return PressableScale(
      onTap: () {
        final rowIdAsync = ref.read(songRowIdProvider(identityKey));
        rowIdAsync.whenOrNull(
          data: (rowId) {
            if (rowId != null) {
              ref.read(favoriteIdsProvider.notifier).toggle(rowId);
            }
          },
        );
      },
      child: AnimatedContainer(
        duration: AppTokens.fast,
        curve: AppTokens.press,
        padding: const EdgeInsets.all(AppTokens.s2),
        decoration: BoxDecoration(
          color: isFavorite
              ? colorScheme.primary.withValues(alpha: 0.12)
              : colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
          shape: BoxShape.circle,
          border: Border.all(
            color: isFavorite
                ? colorScheme.primary.withValues(alpha: 0.3)
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: AppTokens.borderHairline,
          ),
        ),
        child: AnimatedSwitcher(
          duration: AppTokens.fast,
          transitionBuilder: (child, animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          child: Icon(
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            key: ValueKey(isFavorite),
            size: iconSize,
            color: isFavorite
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

/// The player's `quickActions` block: favorite and open the queue.
class PlayerQuickActionsRow extends ConsumerWidget {
  const PlayerQuickActionsRow({
    super.key,
    required this.identityKey,
    required this.onQueueTap,
    this.size = ComponentSize.medium,
  });

  final String identityKey;
  final VoidCallback onQueueTap;
  final ComponentSize size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final gap = switch (size) {
      ComponentSize.small => AppTokens.s3,
      ComponentSize.medium => AppTokens.s4,
      ComponentSize.large => AppTokens.s5,
    };
    final iconSize = switch (size) {
      ComponentSize.small => 20.0,
      ComponentSize.medium => 22.0,
      ComponentSize.large => 24.0,
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerFavoriteButton(identityKey: identityKey, size: size),
        SizedBox(width: gap),
        PressableScale(
          onTap: onQueueTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
              shape: BoxShape.circle,
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: AppTokens.borderHairline,
              ),
            ),
            child: Icon(
              Icons.queue_music_rounded,
              size: iconSize,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

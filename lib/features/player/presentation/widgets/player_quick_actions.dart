import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/ui_customization/ui_layout.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../library/presentation/providers/library_view_providers.dart';
import '../providers/player_providers.dart';

/// The favorite (heart) toggle used by the player's top action bar.
class PlayerFavoriteButton extends ConsumerWidget {
  const PlayerFavoriteButton({
    super.key,
    required this.identityKey,
    this.size = ComponentSize.medium,
    this.compact = false,
  });

  final String identityKey;
  final ComponentSize size;

  /// A tighter 44dp footprint for the top action bar.
  final bool compact;

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
      child: Container(
        width: compact ? 44 : null,
        height: 44,
        padding: EdgeInsets.all(compact ? AppTokens.s1 : AppTokens.s2),
        decoration: BoxDecoration(
          color: isFavorite
              ? colorScheme.primary.withValues(alpha: 0.12)
              : colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
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

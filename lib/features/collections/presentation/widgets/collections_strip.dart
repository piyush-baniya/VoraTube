import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/collections_providers.dart';
import '../../../library/data/library_repository.dart' show CollectionKind;
import '../../../library/presentation/screens/filtered_songs_screen.dart';
import '../../../../shared/widgets/transitions.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../app/theme/app_tokens.dart';

/// Horizontal strip of collection summary cards (Favorites, Recently Added,
/// Most Played, Recently Played). Cards use gradient overlays and the
/// accent color strategically for visual impact.
class CollectionsStrip extends ConsumerWidget {
  const CollectionsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(collectionSummariesProvider);

    return async.when(
      skipLoadingOnRefresh: true,
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (summaries) {
        final visible = summaries.where((s) => s.count > 0).toList();
        if (visible.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s4,
              vertical: AppTokens.s1,
            ),
            itemCount: visible.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppTokens.s2),
            itemBuilder: (context, index) {
              final summary = visible[index];
              return _CollectionCard(summary: summary);
            },
          ),
        );
      },
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.summary});

  final CollectionSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (icon, gradientColors) = switch (summary.kind) {
      CollectionKind.favorites => (
        Icons.favorite_rounded,
        [
          colorScheme.primary.withValues(alpha: 0.25),
          colorScheme.primary.withValues(alpha: 0.08),
        ],
      ),
      CollectionKind.recentlyAdded => (
        Icons.schedule_rounded,
        [
          colorScheme.secondary.withValues(alpha: 0.2),
          colorScheme.secondary.withValues(alpha: 0.06),
        ],
      ),
      CollectionKind.mostPlayed => (
        Icons.trending_up_rounded,
        [
          colorScheme.tertiary.withValues(alpha: 0.2),
          colorScheme.tertiary.withValues(alpha: 0.06),
        ],
      ),
      CollectionKind.recentlyPlayed => (
        Icons.history_rounded,
        [
          colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
          colorScheme.onSurfaceVariant.withValues(alpha: 0.04),
        ],
      ),
    };

    return PressableScale(
      onTap: () => Navigator.of(context).push(
        pushSharedAxis<void>(
          context,
          FilteredSongsScreen.collection(summary.kind, summary.label),
        ),
      ),
      child: Container(
        width: 152,
        padding: const EdgeInsets.all(AppTokens.s3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.rMd),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: colorScheme.onSurfaceVariant),
            const Spacer(),
            Text(
              summary.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${summary.count} ${summary.count == 1 ? 'song' : 'songs'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

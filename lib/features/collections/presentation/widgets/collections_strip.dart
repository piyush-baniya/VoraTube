import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/collections_providers.dart';
import '../../../library/data/library_models.dart';
import '../../../library/data/library_repository.dart' show CollectionKind;
import '../../../library/presentation/screens/filtered_songs_screen.dart';
import '../../../../shared/widgets/transitions.dart';

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
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: visible.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
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
    final (icon, color) = switch (summary.kind) {
      CollectionKind.favorites => (
        Icons.favorite_rounded,
        theme.colorScheme.primary,
      ),
      CollectionKind.recentlyAdded => (
        Icons.schedule_rounded,
        theme.colorScheme.secondary,
      ),
      CollectionKind.mostPlayed => (
        Icons.trending_up_rounded,
        theme.colorScheme.tertiary,
      ),
      CollectionKind.recentlyPlayed => (
        Icons.history_rounded,
        theme.colorScheme.onSurfaceVariant,
      ),
    };

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        pushSharedAxis<void>(
          context,
          FilteredSongsScreen.collection(summary.kind, summary.label),
        ),
      ),
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 24, color: color),
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
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

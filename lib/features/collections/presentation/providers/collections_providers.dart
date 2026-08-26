import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../library/data/library_models.dart';
import '../../../library/data/library_repository.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../../../library/presentation/providers/library_view_providers.dart';

final collectionsProvider = Provider<Collections>((ref) {
  return Collections(ref.watch(libraryRepositoryProvider));
});

/// Coarse summary for one collection category — used by the horizontal strip.
final class CollectionSummary {
  const CollectionSummary({
    required this.kind,
    required this.label,
    this.count = 0,
  });

  final CollectionKind kind;
  final String label;
  final int count;
}

/// Synchronous snapshot of collection summaries, rebuilt only when
/// the library refreshes.
final collectionSummariesProvider =
    FutureProvider.autoDispose<List<CollectionSummary>>((ref) async {
      ref.watch(libraryRefreshTickProvider);
      final collections = ref.watch(collectionsProvider);
      return collections.summaries();
    });

/// Songs of one collection category (lazy, paginated later if needed).
final collectionSongsProvider = FutureProvider.autoDispose
    .family<List<SongTileData>, CollectionKind>((ref, kind) async {
      ref.watch(libraryRefreshTickProvider);
      final collections = ref.read(collectionsProvider);
      return collections.songsOf(kind);
    });

class Collections {
  const Collections(this._repository);

  final LibraryRepository _repository;

  Future<List<CollectionSummary>> summaries() async {
    final results = await Future.wait([
      _repository.collectionSongs(CollectionKind.favorites, limit: 1),
      _repository.collectionSongs(CollectionKind.recentlyAdded, limit: 1),
      _repository.collectionSongs(CollectionKind.mostPlayed, limit: 1),
      _repository.collectionSongs(CollectionKind.recentlyPlayed, limit: 1),
    ]);

    // We need actual counts, not just limit-1. Use count queries instead.
    final favCount = await _repository.countCollection(
      CollectionKind.favorites,
    );
    final addedCount = await _repository.countCollection(
      CollectionKind.recentlyAdded,
    );
    final playedCount = await _repository.countCollection(
      CollectionKind.mostPlayed,
    );
    final recentCount = await _repository.countCollection(
      CollectionKind.recentlyPlayed,
    );

    return [
      CollectionSummary(
        kind: CollectionKind.favorites,
        label: 'Favorites',
        count: favCount,
      ),
      CollectionSummary(
        kind: CollectionKind.recentlyAdded,
        label: 'Recently added',
        count: addedCount,
      ),
      CollectionSummary(
        kind: CollectionKind.mostPlayed,
        label: 'Most played',
        count: playedCount,
      ),
      CollectionSummary(
        kind: CollectionKind.recentlyPlayed,
        label: 'Recently played',
        count: recentCount,
      ),
    ];
  }

  Future<List<SongTileData>> songsOf(CollectionKind kind) async {
    return _repository.collectionSongs(kind, limit: 100);
  }
}

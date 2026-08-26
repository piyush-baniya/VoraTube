import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_models.dart';
import '../../data/library_repository.dart';
import 'library_providers.dart';

/// Bumped after scans/imports so paged queries refetch without ever
/// watching entire tables.
final libraryRefreshTickProvider = StateProvider<int>((ref) => 0);

final librarySectionProvider = StateProvider<LibrarySection>(
  (ref) => LibrarySection.songs,
);

final songSortProvider = StateProvider<SongSort>(
  (ref) => SongSort.recentlyAdded,
);

final favoritesOnlyProvider = StateProvider<bool>((ref) => false);

const int pageSize = 200;

/// Accumulating paginated song list. Restarts when sort, favorites filter
/// or refresh tick change; grows via [PagedSongsController.loadMore].
class PagedSongsController
    extends AutoDisposeAsyncNotifier<List<SongTileData>> {
  bool _hasMore = true;
  int _loadedPages = 0;

  bool get hasMore => _hasMore;

  @override
  Future<List<SongTileData>> build() async {
    _hasMore = true;
    _loadedPages = 0;
    final sort = ref.watch(songSortProvider);
    final favoritesOnly = ref.watch(favoritesOnlyProvider);
    ref.watch(libraryRefreshTickProvider);
    final repository = ref.watch(libraryRepositoryProvider);
    final page = await repository.songsPage(
      limit: pageSize,
      offset: 0,
      sort: sort,
      favoritesOnly: favoritesOnly,
    );
    _hasMore = page.hasMore;
    _loadedPages = 1;
    return page.songs;
  }

  Future<void> loadMore() async {
    if (!_hasMore || state.isLoading || !state.hasValue) {
      return;
    }
    final previous = state.value!;
    state = const AsyncLoading<List<SongTileData>>().copyWithPrevious(state);
    try {
      final sort = ref.read(songSortProvider);
      final favoritesOnly = ref.read(favoritesOnlyProvider);
      final repository = ref.read(libraryRepositoryProvider);
      final page = await repository.songsPage(
        limit: pageSize,
        offset: _loadedPages * pageSize,
        sort: sort,
        favoritesOnly: favoritesOnly,
      );
      _hasMore = page.hasMore;
      _loadedPages++;
      state = AsyncData([...previous, ...page.songs]);
    } catch (e, st) {
      state = AsyncError<List<SongTileData>>(
        e,
        st,
      ).copyWithPrevious(AsyncData(previous));
    }
  }
}

final pagedSongsProvider =
    AutoDisposeAsyncNotifierProvider<PagedSongsController, List<SongTileData>>(
      PagedSongsController.new,
    );

final albumsOverviewProvider = FutureProvider.autoDispose<List<AlbumSummary>>((
  ref,
) async {
  ref.watch(libraryRefreshTickProvider);
  final repository = ref.watch(libraryRepositoryProvider);
  return repository.albumOverview();
});

final artistsOverviewProvider = FutureProvider.autoDispose<List<ArtistSummary>>(
  (ref) async {
    ref.watch(libraryRefreshTickProvider);
    final repository = ref.watch(libraryRepositoryProvider);
    return repository.artistOverview();
  },
);

final genresOverviewProvider = FutureProvider.autoDispose<List<GenreSummary>>((
  ref,
) async {
  ref.watch(libraryRefreshTickProvider);
  final repository = ref.watch(libraryRepositoryProvider);
  return repository.genreOverview();
});

/// Favorite ids kept in fine-grained state so a heart tap repaints exactly
/// one tile, never the whole list.
class FavoriteIdsController extends StateNotifier<Set<int>> {
  FavoriteIdsController(this._repository) : super(const <int>{});

  final LibraryRepository _repository;

  bool isFavorite(int songRowId) => state.contains(songRowId);

  Future<void> toggle(int songRowId) async {
    final currentlyFavorite = state.contains(songRowId);
    final rollback = state;
    state = currentlyFavorite
        ? state.difference({songRowId})
        : {...state, songRowId};
    try {
      await _repository.toggleFavorite(songRowId);
    } catch (_) {
      state = rollback;
    }
  }
}

final favoriteIdsProvider =
    StateNotifierProvider<FavoriteIdsController, Set<int>>(
      (ref) => FavoriteIdsController(ref.watch(libraryRepositoryProvider)),
    );

void notifyLibraryChanged(Ref ref) {
  ref.read(libraryRefreshTickProvider.notifier).state++;
}

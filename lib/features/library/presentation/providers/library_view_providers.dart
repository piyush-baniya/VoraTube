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

/// Cheap truth test for "does the library contain any songs?".
///
/// Smart-mood UIs use this to decide the *accurate* empty message: when the
/// library is truly empty ask the user to add songs, but when songs exist and
/// simply cannot be classified for a given mood, say recommendations are not
/// available yet instead of pretending the library is empty.
final libraryHasSongsProvider = FutureProvider.autoDispose<bool>((ref) async {
  ref.watch(libraryRefreshTickProvider);
  final repository = ref.watch(libraryRepositoryProvider);
  final counts = await repository.currentCounts();
  return counts.songs > 0;
});

/// Favorite ids kept in fine-grained state so a heart tap repaints exactly
/// one tile, never the whole list.
///
/// Hydrated from the database on creation. Without that the set started empty
/// and stayed empty until the user tapped something, so a song favourited in an
/// earlier session rendered as un-favourited — the flag was stored correctly and
/// simply never read back.
class FavoriteIdsController extends StateNotifier<Set<int>> {
  FavoriteIdsController(this._repository) : super(const <int>{}) {
    _hydrate();
  }

  final LibraryRepository _repository;

  /// Bumped by every user action, so a hydration read that is still in flight
  /// cannot land on top of a tap the user made in the meantime.
  int _revision = 0;

  bool isFavorite(int songRowId) => state.contains(songRowId);

  Future<void> _hydrate() async {
    final revision = _revision;
    try {
      final ids = await _repository.favoritesSongRowIds();
      if (!mounted || revision != _revision) {
        return;
      }
      state = ids;
    } catch (_) {
      // A failed read leaves the set empty, so hearts render as un-set rather
      // than the whole list erroring over a decoration. The next library
      // refresh recreates this controller and retries.
    }
  }

  Future<void> toggle(int songRowId) async {
    _revision++;
    final currentlyFavorite = state.contains(songRowId);
    final rollback = state;
    state = currentlyFavorite
        ? state.difference({songRowId})
        : {...state, songRowId};
    try {
      await _repository.toggleFavorite(songRowId);
    } catch (_) {
      if (mounted) {
        state = rollback;
      }
    }
  }
}

final favoriteIdsProvider =
    StateNotifierProvider<FavoriteIdsController, Set<int>>((ref) {
      // Rebuilt on library change so the set drops ids for songs a scan, import
      // or deletion removed, and picks up rows written outside this controller.
      ref.watch(libraryRefreshTickProvider);
      return FavoriteIdsController(ref.watch(libraryRepositoryProvider));
    });

/// Signals that committed library writes are ready to be read back.
///
/// Every paged and overview query in the library, collections and playlists
/// features watches [libraryRefreshTickProvider]; this is the only thing that
/// moves it.
void notifyLibraryChanged(Ref ref) {
  ref.read(libraryRefreshTickProvider.notifier).state++;
}

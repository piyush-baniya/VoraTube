import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/settings/data/settings_models.dart';
import '../../data/library_models.dart';
import '../../data/library_repository.dart';
import 'library_providers.dart';

/// Bumped after scans/imports so paged queries refetch without ever
/// watching entire tables.
final libraryRefreshTickProvider = StateProvider<int>((ref) => 0);

/// Bumped after listening statistics are written (play counts, heard ms,
/// history rows).
///
/// Stats-facing providers (listening strip, statistics screen, collection
/// counts/lists) watch this so newly played songs surface live. It is a
/// dedicated tick rather than a reuse of [libraryRefreshTickProvider], because
/// that one resets the paged browsing list to page zero on every bump — a cost
/// only rare scans/imports should pay, not a stats flush that can fire every
/// few seconds during playback.
final statsRefreshTickProvider = StateProvider<int>((ref) => 0);

/// Bumped after a favorite is committed, so favorites-derived UIs (the
/// Collection "Favorites" count and list) recompute without forcing playback
/// statistics to refetch.
///
/// This is a dedicated tick rather than a reuse of [statsRefreshTickProvider]:
/// favorites do not change listening time, play counts or history, so a
/// favorite tap must not make the Home "Your Listening" strip or the
/// Statistics listening sections refetch and repaint — that is the tick a
/// favorite was historically (incorrectly) wired to, and the source of the
/// Home screen flicker on a heart tap.
final favoritesRefreshTickProvider = StateProvider<int>((ref) => 0);

/// The active Library browse section (Songs, Albums, Artists, Genres).
///
/// Persisted to KV storage so the Library reopens on the section the user was
/// last on — even after the app process is restarted (which would otherwise
/// silently reset the tab to Songs). In-memory state still updates instantly;
/// the write is a fire-and-forget KV save.
class LibrarySectionController extends StateNotifier<LibrarySection> {
  LibrarySectionController(this._repository) : super(LibrarySection.songs) {
    _load();
  }

  final LibraryRepository _repository;

  Future<void> _load() async {
    try {
      final raw = await _repository.kvGet(SettingsKeys.librarySection);
      if (raw == null) return;
      final restored = LibrarySection.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => LibrarySection.songs,
      );
      if (restored != LibrarySection.songs) {
        state = restored;
      }
    } catch (_) {
      // A failed read simply keeps the default Songs section.
    }
  }

  @override
  set state(LibrarySection value) {
    if (value == state) return;
    super.state = value;
    // Best-effort persistence; never block the UI on the KV write.
    _repository.kvSet(SettingsKeys.librarySection, value.name);
  }
}

final librarySectionProvider =
    StateNotifierProvider<LibrarySectionController, LibrarySection>((ref) {
  return LibrarySectionController(ref.watch(libraryRepositoryProvider));
});

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

/// The Home "All Songs" section — deliberately bounded to a small number so the
/// Home never queries the whole library just to render its preview rows.
const int homeSongsLimit = 10;

final homeSongsProvider = FutureProvider.autoDispose<List<SongTileData>>((
  ref,
) async {
  // The Home preview deliberately ignores the Library toolbar's sort and
  // Favorites filter: it is a stable, curated "recently added" peek so the
  // dashboard never silently becomes a filtered copy of the Library browser.
  // Bounded to [homeSongsLimit] so this never queries the whole collection.
  ref.watch(libraryRefreshTickProvider);
  final repository = ref.watch(libraryRepositoryProvider);
  final page = await repository.songsPage(
    limit: homeSongsLimit,
    offset: 0,
    sort: SongSort.recentlyAdded,
    favoritesOnly: false,
  );
  return page.songs;
});

/// Songs the user hid via the song overflow menu ("Hide song").
///
/// The Settings → "Show Hidden Songs" screen renders from this so users can
/// surface and restore tracks that the normal browsing queries deliberately
/// exclude. Watches [libraryRefreshTickProvider] so unhiding a song refreshes
/// the list immediately without a manual reload.
final hiddenSongsProvider = FutureProvider.autoDispose<List<SongTileData>>((
  ref,
) async {
  ref.watch(libraryRefreshTickProvider);
  final repository = ref.watch(libraryRepositoryProvider);
  return repository.hiddenSongs();
});

/// Favorite ids kept in fine-grained state so a heart tap repaints exactly
/// one tile, never the whole list.
///
/// Hydrated from the database on creation. Without that the set started empty
/// and stayed empty until the user tapped something, so a song favourited in an
/// earlier session rendered as un-favourited — the flag was stored correctly and
/// simply never read back.
class FavoriteIdsController extends StateNotifier<Set<int>> {
  FavoriteIdsController(this._repository, {this.onToggleCommitted})
    : super(const <int>{}) {
    _hydrate();
  }

  final LibraryRepository _repository;

  /// Invoked after a favorite toggle is committed to the database, so
  /// consumers that aggregate favorites from disk (statistics counts, mixes)
  /// can refresh. Fired only on success — a rolled-back write must not
  /// trigger a recomputation of derived data.
  final void Function()? onToggleCommitted;

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
      // The DB row is committed: tell consumers that derive favorites from
      // the database (statistics favorites count, mixes) to re-read it. This
      // runs after the write, so a recomputation can never race the commit.
      onToggleCommitted?.call();
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
      return FavoriteIdsController(
        ref.watch(libraryRepositoryProvider),
        // A committed favorite toggle moves favorites-derived aggregates (the
        // Collection "Favorites" count/list), so the dedicated favorites tick
        // must move with it. It deliberately does NOT bump the stats tick:
        // favorites do not change listening time or play counts, and doing so
        // made the Home "Your Listening" strip (which watches the stats tick)
        // refetch and repaint on a heart tap.
        onToggleCommitted: () =>
            ref.read(favoritesRefreshTickProvider.notifier).state++,
      );
    });

/// Signals that committed library writes are ready to be read back.
///
/// Every paged and overview query in the library, collections and playlists
/// features watches [libraryRefreshTickProvider]; this is the only thing that
/// moves it.
void notifyLibraryChanged(Ref ref) {
  ref.read(libraryRefreshTickProvider.notifier).state++;
}

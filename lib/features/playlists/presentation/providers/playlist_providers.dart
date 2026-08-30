import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../library/data/library_models.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../../../library/presentation/providers/library_view_providers.dart'
    show pageSize, libraryRefreshTickProvider;
import '../../data/playlist_models.dart';
import '../../data/playlist_repository.dart';

final playlistRepositoryProvider = Provider<PlaylistRepository>(
  (ref) => PlaylistRepository(ref.watch(appDatabaseProvider)),
);

/// Bumped by every playlist mutation so overview + detail refetch.
final playlistRefreshTickProvider = StateProvider<int>((ref) => 0);

final playlistsOverviewProvider =
    FutureProvider.autoDispose<List<PlaylistSummary>>((ref) async {
      ref.watch(playlistRefreshTickProvider);
      ref.watch(libraryRefreshTickProvider);
      final repository = ref.watch(playlistRepositoryProvider);
      return repository.listPlaylists();
    });

/// Accumulating, paginated songs of one playlist with optimistic local
/// reorder/remove support.
class PlaylistDetailController
    extends AutoDisposeFamilyAsyncNotifier<List<SongTileData>, int> {
  bool _hasMore = true;
  int _loadedPages = 0;
  bool get hasMore => _hasMore;

  @override
  Future<List<SongTileData>> build(int playlistId) async {
    _hasMore = true;
    _loadedPages = 0;
    ref.watch(playlistRefreshTickProvider);
    ref.watch(libraryRefreshTickProvider);
    final repository = ref.watch(playlistRepositoryProvider);
    final page = await repository.songsOf(playlistId, limit: pageSize);
    _hasMore = page.length >= pageSize;
    _loadedPages = 1;
    return page;
  }

  Future<void> loadMore() async {
    if (!_hasMore || state.isLoading || !state.hasValue) {
      return;
    }
    final previous = state.value!;
    state = const AsyncLoading<List<SongTileData>>().copyWithPrevious(state);
    try {
      final repository = ref.read(playlistRepositoryProvider);
      final page = await repository.songsOf(
        arg,
        limit: pageSize,
        offset: _loadedPages * pageSize,
      );
      _hasMore = page.length >= pageSize;
      _loadedPages++;
      state = AsyncData([...previous, ...page]);
    } catch (e, st) {
      state = AsyncError<List<SongTileData>>(
        e,
        st,
      ).copyWithPrevious(AsyncData(previous));
    }
  }

  Future<void> removeAt(int index) async {
    if (!state.hasValue) {
      return;
    }
    final rollback = state.value!;
    state = AsyncData([...rollback]..removeAt(index));
    try {
      await ref.read(playlistRepositoryProvider).removeSongAt(arg, index);
    } catch (_) {
      state = AsyncData(rollback);
    }
  }

  /// Optimistic local move; repository performs the authoritative
  /// renumber. On failure the list snaps back.
  Future<void> move(int from, int to) async {
    if (!state.hasValue) {
      return;
    }
    final rollback = state.value!;
    final updated = [...rollback];
    final moved = updated.removeAt(from);
    updated.insert(to, moved);
    state = AsyncData(updated);
    try {
      await ref.read(playlistRepositoryProvider).moveSong(arg, from, to);
    } catch (_) {
      state = AsyncData(rollback);
    }
  }

  Future<void> appendSongs(List<SongTileData> tiles) async {
    if (tiles.isEmpty) {
      return;
    }
    await ref
        .read(playlistRepositoryProvider)
        .addSongs(arg, tiles.map((t) => t.song.id).toList());
    // Full authoritative reload keeps positions/pages coherent after bulk adds.
    ref.invalidateSelf();
  }
}

final playlistDetailProvider = AsyncNotifierProvider.autoDispose
    .family<PlaylistDetailController, List<SongTileData>, int>(
      PlaylistDetailController.new,
    );

/// Membership sets per playlist for add-to-playlist checkmarks.
final playlistMembershipProvider = FutureProvider.autoDispose
    .family<Set<int>, int>((ref, playlistId) {
      ref.watch(playlistRefreshTickProvider);
      final repository = ref.watch(playlistRepositoryProvider);
      return repository.memberSongRowIds(playlistId);
    });

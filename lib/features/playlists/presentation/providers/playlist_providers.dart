import 'package:flutter/material.dart';
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

/// Shared "New playlist" flow used by Home and the Playlists tab so there is a
/// single playlist-creation entry point. Shows the name dialog, persists the
/// playlist, bumps [playlistRefreshTickProvider] (refreshing every surface)
/// and returns the new playlist id + name, or null when cancelled/rejected.
Future<({int id, String name})?> promptCreatePlaylist(
  BuildContext context,
  WidgetRef ref,
) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New playlist'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('Create'),
        ),
      ],
    ),
  );
  if (result == null || result.isEmpty || !context.mounted) {
    return null;
  }
  try {
    final repository = ref.read(playlistRepositoryProvider);
    final id = await repository.createPlaylist(result);
    ref.read(playlistRefreshTickProvider.notifier).state++;
    return (id: id, name: result);
  } on DuplicatePlaylistNameException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
    return null;
  }
}

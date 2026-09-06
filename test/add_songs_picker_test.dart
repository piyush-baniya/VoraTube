import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/playlists/data/playlist_repository.dart';
import 'package:vora_tube/features/playlists/presentation/providers/playlist_providers.dart';
import 'package:vora_tube/features/playlists/presentation/widgets/add_songs_sheet.dart';

IngestTrack _msTrack(int id) {
  return IngestTrack(
    source: IngestSource.mediastore,
    mediaStoreId: id,
    albumMediaStoreId: 100 + id,
    artistMediaStoreId: 200 + id,
    albumKey: 'ms:${100 + id}',
    artistKey: 'ms:${200 + id}',
    contentUri: 'content://media/external/audio/media/$id',
    path: '/storage/emulated/0/Music/song_$id.mp3',
    title: 'Song $id',
    artist: 'Artist ${id % 3}',
    album: 'Album ${id % 2}',
    durationMs: 180000 + id,
    dateModifiedSec: 100 + id,
    year: 2020,
    trackNumber: id,
    sizeBytes: 5000 + id,
    dateAddedSec: 90 + id,
  );
}

/// A repository whose adds fail, to prove a failed "Done" commit never
/// misleads the UI into believing the write landed.
class _FailingPlaylistRepository extends PlaylistRepository {
  _FailingPlaylistRepository(super.db);

  @override
  Future<void> addSongs(int playlistId, List<int> songRowIds) async {
    throw Exception('boom');
  }
}

void main() {
  late AppDatabase db;
  late LibraryRepository libraryRepo;
  late PlaylistRepository playlistRepo;

  Future<AppDatabase> seedDb({required int songs}) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    libraryRepo = LibraryRepository(database);
    playlistRepo = PlaylistRepository(database);
    await libraryRepo.syncTracks([
      for (var i = 1; i <= songs; i++) _msTrack(i),
    ]);
    return database;
  }

  /// Pumps a host screen that pushes the picker as a real route, so a test can
  /// prove "Done" / Back actually close the picker.
  Future<void> openPicker(
    WidgetTester tester, {
    required int pid,
    PlaylistRepository? repository,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          if (repository != null)
            playlistRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).push(
                    MaterialPageRoute<void>(
                      fullscreenDialog: true,
                      builder: (_) => AddSongsPickerScreen(playlistId: pid),
                    ),
                  ),
                  child: const Text('open picker'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open picker'));
    await tester.pumpAndSettle();
  }

  Future<int> pumpPicker(
    WidgetTester tester, {
    PlaylistRepository? repository,
  }) async {
    final pid = await playlistRepo.createPlaylist('Test');
    await openPicker(tester, pid: pid, repository: repository);
    return pid;
  }

  Future<Set<int>> members(int pid) => playlistRepo.memberSongRowIds(pid);
  Future<List<int>> order(int pid) async =>
      (await playlistRepo.songsOf(pid)).map((s) => s.song.id).toList();

  Finder addIcon(int songId) => find.byKey(ValueKey('add-song-$songId'));
  Finder removeIcon(int songId) => find.byKey(ValueKey('remove-song-$songId'));
  final selectAll = find.text('Select All');
  final doneButton = find.byKey(const ValueKey('done-button'));
  final hostVisible = find.text('open picker');

  testWidgets('Test 1 — initial rendering: members show -, non-members +', (
    tester,
  ) async {
    db = await seedDb(songs: 4);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [1, 4]); // A and D are members

    await openPicker(tester, pid: pid);

    expect(removeIcon(1), findsOneWidget);
    expect(addIcon(2), findsOneWidget);
    expect(addIcon(3), findsOneWidget);
    expect(removeIcon(4), findsOneWidget);
  });

  testWidgets('Test 2 — tapping + only stages: no DB write, no snackbar', (
    tester,
  ) async {
    db = await seedDb(songs: 4);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [1, 4]);

    await openPicker(tester, pid: pid);
    await tester.tap(addIcon(2));
    await tester.pumpAndSettle();

    // Visual state flips to selected...
    expect(removeIcon(2), findsOneWidget);
    expect(addIcon(2), findsNothing);
    // ...but nothing was committed anywhere.
    expect(await members(pid), {1, 4});
    expect(find.text('Added "Song 2" to playlist'), findsNothing);
    expect(find.text('Added to playlist'), findsNothing);
  });

  testWidgets('Test 3 — tapping + again undoes the pending add', (
    tester,
  ) async {
    db = await seedDb(songs: 4);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [1, 4]);

    await openPicker(tester, pid: pid);
    await tester.tap(addIcon(2));
    await tester.pumpAndSettle();
    await tester.tap(removeIcon(2));
    await tester.pumpAndSettle();

    expect(addIcon(2), findsOneWidget);
    expect(removeIcon(2), findsNothing);
    expect(await members(pid), {1, 4});
  });

  testWidgets('Test 4 — tapping - on a member stages a removal (shows +)', (
    tester,
  ) async {
    db = await seedDb(songs: 4);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [1, 4]);

    await openPicker(tester, pid: pid);
    await tester.tap(removeIcon(1));
    await tester.pumpAndSettle();

    expect(addIcon(1), findsOneWidget);
    expect(removeIcon(1), findsNothing);
    expect(await members(pid), {1, 4}, reason: 'DB untouched until Done');
  });

  testWidgets('Test 5 — tapping + on a pending-removed member restores it', (
    tester,
  ) async {
    db = await seedDb(songs: 4);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [1, 4]);

    await openPicker(tester, pid: pid);
    await tester.tap(removeIcon(1));
    await tester.pumpAndSettle();
    await tester.tap(addIcon(1));
    await tester.pumpAndSettle();

    expect(removeIcon(1), findsOneWidget);
    expect(addIcon(1), findsNothing);
    expect(await members(pid), {1, 4});
  });

  testWidgets('Test 6 — Select All is selection-only: zero database writes', (
    tester,
  ) async {
    db = await seedDb(songs: 4);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [1, 4]);

    await openPicker(tester, pid: pid);
    await tester.tap(selectAll);
    await tester.pumpAndSettle();

    for (var id = 1; id <= 4; id++) {
      expect(removeIcon(id), findsOneWidget, reason: 'song $id selected');
    }
    expect(await members(pid), {1, 4}, reason: 'Select All must not write');
    expect(find.textContaining('Added'), findsNothing);
    expect(find.textContaining('Removed'), findsNothing);
  });

  testWidgets('Test 7 — Select All, deselect one, Done: mixed add+remove', (
    tester,
  ) async {
    db = await seedDb(songs: 4);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [1, 4]);

    await openPicker(tester, pid: pid);
    await tester.tap(selectAll);
    await tester.pumpAndSettle();
    await tester.tap(removeIcon(4));
    await tester.pumpAndSettle();

    await tester.tap(doneButton);
    await tester.pumpAndSettle();

    expect(await members(pid), {1, 2, 3});
    expect(await order(pid), hasLength(3));
    expect(find.text('Added 2 songs, removed 1 song.'), findsOneWidget);
    expect(hostVisible, findsOneWidget, reason: 'Done closes the picker');
  });

  testWidgets(
    'Test 8 — Select All then Done commits everything, reopens clean',
    (tester) async {
      db = await seedDb(songs: 4);
      final pid = await playlistRepo.createPlaylist('Test');
      await playlistRepo.addSongs(pid, [1, 4]);

      await openPicker(tester, pid: pid);
      await tester.tap(selectAll);
      await tester.pumpAndSettle();
      await tester.tap(doneButton);
      await tester.pumpAndSettle();

      expect(await members(pid), {1, 2, 3, 4});
      expect((await order(pid)).take(2).toList(), [
        1,
        4,
      ], reason: 'existing members keep their leading order');
      expect(find.text('Added 2 songs to playlist'), findsOneWidget);
      expect(hostVisible, findsOneWidget);

      // Reopen: every song now renders as a member.
      await openPicker(tester, pid: pid);
      for (var id = 1; id <= 4; id++) {
        expect(removeIcon(id), findsOneWidget, reason: 'song $id persisted');
      }
    },
  );

  testWidgets(
    'Test 9 — Select All, deselect some back: net-zero closes silently',
    (tester) async {
      db = await seedDb(songs: 4);
      final pid = await playlistRepo.createPlaylist('Test');
      await playlistRepo.addSongs(pid, [1, 4]);

      await openPicker(tester, pid: pid);
      await tester.tap(selectAll);
      await tester.pumpAndSettle();
      await tester.tap(removeIcon(2));
      await tester.tap(removeIcon(3));
      await tester.pumpAndSettle();

      await tester.tap(doneButton);
      await tester.pumpAndSettle();

      expect(await members(pid), {1, 4});
      expect(find.textContaining('Added'), findsNothing);
      expect(find.textContaining('Removed'), findsNothing);
      expect(hostVisible, findsOneWidget);
    },
  );

  testWidgets(
    'Test 10 — Select All then deselect every member: Done removes all',
    (tester) async {
      db = await seedDb(songs: 4);
      final pid = await playlistRepo.createPlaylist('Test');
      await playlistRepo.addSongs(pid, [1, 2, 3, 4]);

      await openPicker(tester, pid: pid);
      await tester.tap(selectAll);
      await tester.pumpAndSettle();
      for (var id = 1; id <= 4; id++) {
        await tester.tap(removeIcon(id));
      }
      await tester.pumpAndSettle();

      await tester.tap(doneButton);
      await tester.pumpAndSettle();

      expect(await members(pid), isEmpty);
      expect(find.text('Removed 4 songs from playlist'), findsOneWidget);
    },
  );

  testWidgets('Test 11 — Back discards pending: no database writes', (
    tester,
  ) async {
    db = await seedDb(songs: 4);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [1, 4]);

    await openPicker(tester, pid: pid);
    await tester.tap(addIcon(2));
    await tester.tap(removeIcon(4));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(hostVisible, findsOneWidget);
    expect(await members(pid), {1, 4});
  });

  testWidgets('Test 12 — empty playlist: Select All + Done adds every song', (
    tester,
  ) async {
    db = await seedDb(songs: 3);
    final pid = await pumpPicker(tester);

    for (var id = 1; id <= 3; id++) {
      expect(addIcon(id), findsOneWidget);
    }
    await tester.tap(selectAll);
    await tester.pumpAndSettle();
    await tester.tap(doneButton);
    await tester.pumpAndSettle();

    expect(await members(pid), {1, 2, 3});
    expect(find.text('Added 3 songs to playlist'), findsOneWidget);
    expect(hostVisible, findsOneWidget);
  });

  testWidgets('Test 13 — every visible song already member: Done is a no-op', (
    tester,
  ) async {
    db = await seedDb(songs: 3);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [1, 2, 3]);

    await openPicker(tester, pid: pid);
    for (var id = 1; id <= 3; id++) {
      expect(removeIcon(id), findsOneWidget);
    }
    await tester.tap(selectAll);
    await tester.pumpAndSettle();
    await tester.tap(doneButton);
    await tester.pumpAndSettle();

    expect(await members(pid), {1, 2, 3});
    expect(find.textContaining('Added'), findsNothing);
    expect(find.textContaining('Removed'), findsNothing);
    expect(hostVisible, findsOneWidget);
  });

  testWidgets(
    'Test 14 — duplicate safety: Select All + Done never duplicates',
    (tester) async {
      db = await seedDb(songs: 3);
      final pid = await playlistRepo.createPlaylist('Test');
      await playlistRepo.addSongs(pid, [1]);

      await openPicker(tester, pid: pid);
      await tester.tap(selectAll);
      await tester.pumpAndSettle();
      await tester.tap(doneButton);
      await tester.pumpAndSettle();

      expect(await members(pid), {1, 2, 3});
      expect(await order(pid), hasLength(3), reason: 'no duplicate rows');
    },
  );

  testWidgets('Test 15 — large song list: Select All covers every page', (
    tester,
  ) async {
    db = await seedDb(songs: 205);
    final pid = await pumpPicker(tester);

    await tester.tap(selectAll);
    await tester.pumpAndSettle();
    await tester.tap(doneButton);
    await tester.pumpAndSettle();

    final expected = {for (var id = 1; id <= 205; id++) id};
    expect(await members(pid), expected);
// Direct count of the playlist_songs rows: proves every song landed exactly
    // once (songsOf caps at its default limit of 200, so it can't count here).
    final rows = await db.select(db.playlistSongs).get();
    final rowCount = rows.where((r) => r.playlistId == pid).length;
    expect(rowCount, expected.length);
  });

  testWidgets(
    'Test 16 — failed Done commit: error snackbar, picker stays open',
    (tester) async {
      db = await seedDb(songs: 3);
      final failing = _FailingPlaylistRepository(db);
      final pid = await playlistRepo.createPlaylist('Test');

      await openPicker(tester, pid: pid, repository: failing);
      await tester.tap(addIcon(2));
      await tester.pumpAndSettle();
      await tester.tap(doneButton);
      await tester.pumpAndSettle();

      expect(
        find.text('Could not update the playlist. Please try again.'),
        findsOneWidget,
      );
      expect(await members(pid), isEmpty);
      expect(doneButton, findsOneWidget, reason: 'picker stays open to retry');
      expect(hostVisible, findsNothing);
    },
  );

  testWidgets('Test 17 — Done with no pending changes just closes', (
    tester,
  ) async {
    db = await seedDb(songs: 3);
    final pid = await pumpPicker(tester);

    await tester.tap(doneButton);
    await tester.pumpAndSettle();

    expect(await members(pid), isEmpty);
    expect(find.textContaining('Added'), findsNothing);
    expect(hostVisible, findsOneWidget);
  });
}

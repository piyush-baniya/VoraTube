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
  /// prove "Done" / the close button actually close the picker.
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

  testWidgets('Test 1 — empty playlist: Select All visible, every song +', (
    tester,
  ) async {
    db = await seedDb(songs: 4);
    await pumpPicker(tester);

    expect(selectAll, findsOneWidget);
    for (var id = 1; id <= 4; id++) {
      expect(addIcon(id), findsOneWidget);
      expect(removeIcon(id), findsNothing);
    }
  });

  testWidgets('Test 2 — non-empty playlist: Select All NOT visible', (
    tester,
  ) async {
    db = await seedDb(songs: 4);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [1]); // A is a member

    await openPicker(tester, pid: pid);

    expect(selectAll, findsNothing);
    expect(removeIcon(1), findsOneWidget);
    for (var id = 2; id <= 4; id++) {
      expect(addIcon(id), findsOneWidget);
    }
  });

  testWidgets(
    'Test 3 — Select All on empty playlist: local only, DB stays empty',
    (tester) async {
      db = await seedDb(songs: 4);
      final pid = await pumpPicker(tester);

      await tester.tap(selectAll);
      await tester.pumpAndSettle();

      for (var id = 1; id <= 4; id++) {
        expect(
          removeIcon(id),
          findsOneWidget,
          reason: 'song $id pending-selected',
        );
      }
      expect(await members(pid), isEmpty, reason: 'no database write');
      expect(find.textContaining('Added'), findsNothing);
      expect(find.textContaining('Removed'), findsNothing);
    },
  );

  testWidgets('Test 4 — Select All, deselect C, Done: A/B/D added, C not', (
    tester,
  ) async {
    db = await seedDb(songs: 4);
    final pid = await pumpPicker(tester);

    await tester.tap(selectAll);
    await tester.pumpAndSettle();
    await tester.tap(removeIcon(3)); // C
    await tester.pumpAndSettle();

    await tester.tap(doneButton);
    await tester.pumpAndSettle();

    expect(await members(pid), {1, 2, 4});
    expect(await order(pid), hasLength(3));
    expect(find.text('Added 3 songs to playlist'), findsOneWidget);
    expect(hostVisible, findsOneWidget);
  });

  testWidgets('Test 5 — non-empty playlist: manual add B + remove A, Done', (
    tester,
  ) async {
    db = await seedDb(songs: 4);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [1]);

    await openPicker(tester, pid: pid);
    expect(selectAll, findsNothing);

    await tester.tap(addIcon(2)); // B pending-add
    await tester.tap(removeIcon(1)); // A pending-remove
    await tester.pumpAndSettle();
    await tester.tap(doneButton);
    await tester.pumpAndSettle();

    expect(await members(pid), {2});
    expect(find.text('Added 1 song, removed 1 song.'), findsOneWidget);
    expect(hostVisible, findsOneWidget);
  });

  testWidgets('Test 6 — pending toggles never touch DB; Done commits once', (
    tester,
  ) async {
    db = await seedDb(songs: 4);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [1]);

    await openPicker(tester, pid: pid);
    await tester.tap(addIcon(2));
    await tester.pumpAndSettle();
    expect(await members(pid), {1}, reason: 'tap + does not write');

    await tester.tap(removeIcon(1));
    await tester.pumpAndSettle();
    expect(await members(pid), {1}, reason: 'tap - does not write');
    expect(find.textContaining('Added'), findsNothing);

    await tester.tap(doneButton);
    await tester.pumpAndSettle();
    expect(await members(pid), {2});
    expect(hostVisible, findsOneWidget);
  });

  testWidgets('Test 7 — reverting a pending change restores the icon', (
    tester,
  ) async {
    db = await seedDb(songs: 4);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [1]);

    await openPicker(tester, pid: pid);
    await tester.tap(addIcon(2));
    await tester.pumpAndSettle();
    await tester.tap(removeIcon(2));
    await tester.pumpAndSettle();

    expect(addIcon(2), findsOneWidget);
    expect(removeIcon(2), findsNothing);
    expect(await members(pid), {1});
  });

  testWidgets('Test 8 — Select All again is a local toggle-off: no writes', (
    tester,
  ) async {
    db = await seedDb(songs: 4);
    final pid = await pumpPicker(tester);

    await tester.tap(selectAll);
    await tester.pumpAndSettle();
    for (var id = 1; id <= 4; id++) {
      expect(removeIcon(id), findsOneWidget);
    }

    await tester.tap(selectAll);
    await tester.pumpAndSettle();
    for (var id = 1; id <= 4; id++) {
      expect(addIcon(id), findsOneWidget);
    }
    expect(await members(pid), isEmpty);
    expect(find.textContaining('Added'), findsNothing);
  });

  testWidgets('Test 9 — Done with no pending changes just closes', (
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

  testWidgets('Test 10 — duplicate safety: Select All + Done adds once each', (
    tester,
  ) async {
    db = await seedDb(songs: 3);
    final pid = await pumpPicker(tester);

    await tester.tap(selectAll);
    await tester.pumpAndSettle();
    await tester.tap(doneButton);
    await tester.pumpAndSettle();

    expect(await members(pid), {1, 2, 3});
    final rows = await db.select(db.playlistSongs).get();
    expect(rows.where((r) => r.playlistId == pid), hasLength(3));
  });

  testWidgets('Test 11 — large empty playlist: Select All spans every page', (
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
    // Direct count of playlist_songs rows: exactly one row per song (songsOf
    // caps at its default limit of 200, so it can't count here).
    final rows = await db.select(db.playlistSongs).get();
    expect(rows.where((r) => r.playlistId == pid), hasLength(205));
  });

  testWidgets('Test 12 — committed playlist then reopened: no Select All', (
    tester,
  ) async {
    db = await seedDb(songs: 3);
    final pid = await pumpPicker(tester);

    await tester.tap(selectAll);
    await tester.pumpAndSettle();
    await tester.tap(doneButton);
    await tester.pumpAndSettle();
    expect(await members(pid), {1, 2, 3});

    await openPicker(tester, pid: pid);
    for (var id = 1; id <= 3; id++) {
      expect(removeIcon(id), findsOneWidget);
    }
    expect(selectAll, findsNothing, reason: 'playlist no longer empty');
  });

  testWidgets('Test 13 — close button discards pending: no DB writes', (
    tester,
  ) async {
    db = await seedDb(songs: 4);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [1]);

    await openPicker(tester, pid: pid);
    await tester.tap(addIcon(2));
    await tester.tap(removeIcon(1));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(hostVisible, findsOneWidget);
    expect(await members(pid), {1});
  });

  testWidgets(
    'Test 14 — failed Done commit: error snackbar, picker stays open',
    (tester) async {
      db = await seedDb(songs: 3);
      final failing = _FailingPlaylistRepository(db);
      final pid = await playlistRepo.createPlaylist('Test');
      await playlistRepo.addSongs(pid, [1]);

      await openPicker(tester, pid: pid, repository: failing);
      await tester.tap(addIcon(2));
      await tester.pumpAndSettle();
      await tester.tap(doneButton);
      await tester.pumpAndSettle();

      expect(
        find.text('Could not update the playlist. Please try again.'),
        findsOneWidget,
      );
      expect(await members(pid), {1});
      expect(doneButton, findsOneWidget, reason: 'picker stays open to retry');
      expect(hostVisible, findsNothing);
    },
  );

  testWidgets('Test 15 — mixed commit preserves existing member order', (
    tester,
  ) async {
    db = await seedDb(songs: 4);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [1, 4]);

    await openPicker(tester, pid: pid);
    await tester.tap(addIcon(2)); // B pending-add
    await tester.tap(removeIcon(4)); // D pending-remove
    await tester.pumpAndSettle();
    await tester.tap(doneButton);
    await tester.pumpAndSettle();

    expect(await members(pid), {1, 2});
    expect((await order(pid)).take(2).toList(), [
      1,
      2,
    ], reason: 'existing member A keeps its leading position');
    expect(find.text('Added 1 song, removed 1 song.'), findsOneWidget);
  });
}

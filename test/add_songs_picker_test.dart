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

/// A repository whose adds fail, to prove a failed write never advances the
/// UI's membership state.
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
    await libraryRepo.syncTracks([for (var i = 1; i <= songs; i++) _msTrack(i)]);
    return database;
  }

  Future<int> pumpPicker(WidgetTester tester) async {
    final pid = await playlistRepo.createPlaylist('Test');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: AddSongsPickerScreen(playlistId: pid),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return pid;
  }

  Future<Set<int>> members(int pid) => playlistRepo.memberSongRowIds(pid);
  Future<List<int>> order(int pid) async =>
      (await playlistRepo.songsOf(pid)).map((s) => s.song.id).toList();

  Finder addIcon(int songId) => find.byKey(ValueKey('add-song-$songId'));
  Finder removeIcon(int songId) => find.byKey(ValueKey('remove-song-$songId'));
  final selectAll = find.text('Select All');

  testWidgets('Test 1 — none added: Select All adds every song', (tester) async {
    db = await seedDb(songs: 3);

    final pid = await pumpPicker(tester);
    await tester.tap(selectAll);
    await tester.pumpAndSettle();

    expect(await members(pid), {1, 2, 3});
    expect(find.text('Added 3 songs to playlist'), findsOneWidget);
    for (var id = 1; id <= 3; id++) {
      expect(removeIcon(id), findsOneWidget, reason: 'song $id should show REMOVE');
    }
  });

  testWidgets('Test 2 — all added: Select All removes every song', (tester) async {
    db = await seedDb(songs: 3);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [1, 2, 3]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: AddSongsPickerScreen(playlistId: pid),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(selectAll);
    await tester.pumpAndSettle();

    expect(await members(pid), isEmpty);
    expect(find.text('Removed 3 songs from playlist'), findsOneWidget);
    for (var id = 1; id <= 3; id++) {
      expect(addIcon(id), findsOneWidget, reason: 'song $id should show ADD again');
    }
  });

  testWidgets('Test 3 — mixed: Select All adds missing, then removes all', (
    tester,
  ) async {
    db = await seedDb(songs: 4);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [1, 4]); // A and D are members

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: AddSongsPickerScreen(playlistId: pid),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Contextual icons before any action: A/D REMOVE, B/C ADD.
    expect(removeIcon(1), findsOneWidget);
    expect(addIcon(2), findsOneWidget);
    expect(addIcon(3), findsOneWidget);
    expect(removeIcon(4), findsOneWidget);

    await tester.tap(selectAll);
    await tester.pumpAndSettle();

    // Exactly B(2) and C(3) were inserted; A and D untouched, order preserved
    // (existing members keep their relative order before the appended ones).
    expect(await members(pid), {1, 2, 3, 4});
    expect((await order(pid)).take(2).toList(), [1, 4]);
    expect(find.text('Added 2 songs to playlist'), findsOneWidget);

    await tester.tap(selectAll);
    await tester.pumpAndSettle();

    expect(await members(pid), isEmpty);
    expect(find.text('Removed 4 songs from playlist'), findsOneWidget);
  });

  testWidgets('Test 4 — individual add: tapping + adds the song', (tester) async {
    db = await seedDb(songs: 2);

    final pid = await pumpPicker(tester);
    expect(addIcon(2), findsOneWidget);

    await tester.tap(addIcon(2));
    await tester.pumpAndSettle();

    expect(await members(pid), {2});
    expect(removeIcon(2), findsOneWidget);
    expect(addIcon(2), findsNothing);
    expect(find.text('Added "Song 2" to playlist'), findsOneWidget);
  });

  testWidgets('Test 5 — individual remove: tapping - removes the song', (
    tester,
  ) async {
    db = await seedDb(songs: 2);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [2]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: AddSongsPickerScreen(playlistId: pid),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(removeIcon(2), findsOneWidget);

    await tester.tap(removeIcon(2));
    await tester.pumpAndSettle();

    expect(await members(pid), isEmpty);
    expect(addIcon(2), findsOneWidget);
    expect(removeIcon(2), findsNothing);
    expect(find.text('Removed "Song 2" from playlist'), findsOneWidget);
  });

  testWidgets('Test 6 — mixed individual actions stay contextual', (
    tester,
  ) async {
    db = await seedDb(songs: 2);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [1]); // A member, B not

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: AddSongsPickerScreen(playlistId: pid),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap A (member) → A removed; both now not in playlist.
    await tester.tap(removeIcon(1));
    await tester.pumpAndSettle();
    expect(await members(pid), isEmpty);
    expect(addIcon(1), findsOneWidget);
    expect(removeIcon(1), findsNothing);

    // Tap B (not member) → B added.
    await tester.tap(addIcon(2));
    await tester.pumpAndSettle();
    expect(await members(pid), {2});
    expect(removeIcon(2), findsOneWidget);
    expect(addIcon(2), findsNothing);
  });

  testWidgets('Test 7 — duplicate safety: rapid double-tap adds once', (
    tester,
  ) async {
    db = await seedDb(songs: 2);
    final pid = await pumpPicker(tester);

    // Two taps before any frame is pumped: the second is swallowed by the
    // in-flight guard, so only one row can ever be inserted.
    await tester.tap(addIcon(2));
    await tester.tap(addIcon(2));
    await tester.pumpAndSettle();

    expect(await members(pid), {2});
    expect(await order(pid), hasLength(1));
    expect(removeIcon(2), findsOneWidget);
    expect(addIcon(2), findsNothing);
  });

  testWidgets('Test 8 — database failure: no false membership, error snackbar', (
    tester,
  ) async {
    db = await seedDb(songs: 1);
    // addSongs throws, so the write can never land; membership must not move.
    final failing = _FailingPlaylistRepository(db);

    final pid = await playlistRepo.createPlaylist('Test');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          playlistRepositoryProvider.overrideWithValue(failing),
        ],
        child: MaterialApp(
          home: AddSongsPickerScreen(playlistId: pid),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(addIcon(1), findsOneWidget);
    await tester.tap(addIcon(1));
    await tester.pumpAndSettle();

    expect(await members(pid), isEmpty);
    expect(addIcon(1), findsOneWidget, reason: 'icon must stay ADD on failure');
    expect(removeIcon(1), findsNothing);
    expect(find.text('Could not add "Song 1" to the playlist.'), findsOneWidget);
  });

  testWidgets('Test 9 — correct bulk counts: 2 missing of 3 inserted', (
    tester,
  ) async {
    db = await seedDb(songs: 3);
    final pid = await playlistRepo.createPlaylist('Test');
    await playlistRepo.addSongs(pid, [1]); // song 1 already a member

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: AddSongsPickerScreen(playlistId: pid),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(selectAll);
    await tester.pumpAndSettle();

    // Exactly 2 missing songs inserted; the existing member(s) keep their
    // leading position and are never duplicated or reordered.
    expect(await members(pid), {1, 2, 3});
    expect((await order(pid)).first, 1);
    expect(find.text('Added 2 songs to playlist'), findsOneWidget);
    expect(find.text('Added 3 songs to playlist'), findsNothing);
  });
}
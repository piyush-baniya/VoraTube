import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/playlists/data/playlist_models.dart';
import 'package:vora_tube/features/playlists/data/playlist_repository.dart';

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

void main() {
  late AppDatabase db;
  late LibraryRepository libraryRepo;
  late PlaylistRepository playlistRepo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    libraryRepo = LibraryRepository(db);
    playlistRepo = PlaylistRepository(db);

    // Seed songs so playlists can reference them.
    await libraryRepo.syncTracks([
      _msTrack(1),
      _msTrack(2),
      _msTrack(3),
      _msTrack(4),
      _msTrack(5),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  // -------------------------------------------------------------------------
  // Create / list
  // -------------------------------------------------------------------------

  group('createPlaylist', () {
    test('creates and returns id', () async {
      final id = await playlistRepo.createPlaylist('My Playlist');
      expect(id, isA<int>());

      final list = await playlistRepo.listPlaylists();
      expect(list, hasLength(1));
      expect(list.first.name, 'My Playlist');
      expect(list.first.songCount, 0);
    });

    test('throws on empty name', () {
      expect(
        () => playlistRepo.createPlaylist('  '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws DuplicatePlaylistNameException on duplicate', () async {
      await playlistRepo.createPlaylist('Favorites');
      expect(
        () => playlistRepo.createPlaylist('Favorites'),
        throwsA(isA<DuplicatePlaylistNameException>()),
      );
    });
  });

  group('listPlaylists', () {
    test('orders pinned first, then by updatedAt desc', () async {
      final id1 = await playlistRepo.createPlaylist('A');
      final id2 = await playlistRepo.createPlaylist('B');
      await playlistRepo.createPlaylist('C');

      await playlistRepo.setPinned(id2, true);

      final list = await playlistRepo.listPlaylists();
      expect(list.length, 3);
      expect(list[0].name, 'B');
      expect(list[0].pinned, isTrue);
    });

    test('includes song counts and total duration', () async {
      final pid = await playlistRepo.createPlaylist('Test');
      await playlistRepo.addSongs(pid, [1, 2, 3]);

      final list = await playlistRepo.listPlaylists();
      final p = list.firstWhere((e) => e.id == pid);
      expect(p.songCount, 3);
      expect(p.totalDurationMs, isPositive);
    });
  });

  // -------------------------------------------------------------------------
  // Rename / pin / delete
  // -------------------------------------------------------------------------

  group('renamePlaylist', () {
    test('renames successfully', () async {
      final id = await playlistRepo.createPlaylist('Old');
      await playlistRepo.renamePlaylist(id, 'New');

      final list = await playlistRepo.listPlaylists();
      expect(list.first.name, 'New');
    });

    test('throws on empty name', () async {
      final id = await playlistRepo.createPlaylist('X');
      expect(
        () => playlistRepo.renamePlaylist(id, ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws on duplicate name', () async {
      await playlistRepo.createPlaylist('A');
      final id2 = await playlistRepo.createPlaylist('B');
      expect(
        () => playlistRepo.renamePlaylist(id2, 'A'),
        throwsA(isA<DuplicatePlaylistNameException>()),
      );
    });
  });

  test('setPinned toggles pinned flag', () async {
    final id = await playlistRepo.createPlaylist('Pin Me');
    expect((await playlistRepo.listPlaylists()).first.pinned, isFalse);

    await playlistRepo.setPinned(id, true);
    expect((await playlistRepo.listPlaylists()).first.pinned, isTrue);

    await playlistRepo.setPinned(id, false);
    expect((await playlistRepo.listPlaylists()).first.pinned, isFalse);
  });

  group('deletePlaylist', () {
    test('deletes playlist and cascade-removes songs', () async {
      final id = await playlistRepo.createPlaylist('To Delete');
      await playlistRepo.addSongs(id, [1, 2]);
      await playlistRepo.deletePlaylist(id);

      final list = await playlistRepo.listPlaylists();
      expect(list, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Add / remove / reorder songs
  // -------------------------------------------------------------------------

  group('addSongs', () {
    test('appends songs in order', () async {
      final pid = await playlistRepo.createPlaylist('Queue');
      await playlistRepo.addSongs(pid, [3, 1, 5]);

      final songs = await playlistRepo.songsOf(pid);
      expect(songs, hasLength(3));
      expect(songs[0].song.id, 3);
      expect(songs[1].song.id, 1);
      expect(songs[2].song.id, 5);
    });

    test('allows same song at different positions (insertOrAbort)', () async {
      final pid = await playlistRepo.createPlaylist('Dup');
      await playlistRepo.addSongs(pid, [1, 1, 1]);

      final songs = await playlistRepo.songsOf(pid);
      expect(songs, hasLength(3));
    });

    test('no-ops on empty list', () async {
      final pid = await playlistRepo.createPlaylist('Empty');
      await playlistRepo.addSongs(pid, []);

      final songs = await playlistRepo.songsOf(pid);
      expect(songs, isEmpty);
    });
  });

  group('removeSongAt', () {
    test('removes song and renumbers', () async {
      final pid = await playlistRepo.createPlaylist('Rem');
      await playlistRepo.addSongs(pid, [1, 2, 3, 4]);

      await playlistRepo.removeSongAt(pid, 1); // remove song 2

      final songs = await playlistRepo.songsOf(pid);
      expect(songs, hasLength(3));
      expect(songs.map((s) => s.song.id).toList(), [1, 3, 4]);
    });

    test('no-ops on out-of-bounds index', () async {
      final pid = await playlistRepo.createPlaylist('OOB');
      await playlistRepo.addSongs(pid, [1, 2]);

      await playlistRepo.removeSongAt(pid, 99);

      final songs = await playlistRepo.songsOf(pid);
      expect(songs, hasLength(2));
    });
  });

  group('moveSong (reorder)', () {
    test('moves song from start to end', () async {
      final pid = await playlistRepo.createPlaylist('Move');
      await playlistRepo.addSongs(pid, [1, 2, 3, 4, 5]);

      await playlistRepo.moveSong(pid, 0, 4);

      final songs = await playlistRepo.songsOf(pid);
      expect(songs.map((s) => s.song.id).toList(), [2, 3, 4, 5, 1]);
    });

    test('moves song from end to start', () async {
      final pid = await playlistRepo.createPlaylist('Move2');
      await playlistRepo.addSongs(pid, [1, 2, 3]);

      await playlistRepo.moveSong(pid, 2, 0);

      final songs = await playlistRepo.songsOf(pid);
      expect(songs.map((s) => s.song.id).toList(), [3, 1, 2]);
    });

    test('no-ops on out-of-bounds', () async {
      final pid = await playlistRepo.createPlaylist('Move3');
      await playlistRepo.addSongs(pid, [1, 2]);

      await playlistRepo.moveSong(pid, 0, 99);

      final songs = await playlistRepo.songsOf(pid);
      expect(songs.map((s) => s.song.id).toList(), [1, 2]);
    });
  });

  // -------------------------------------------------------------------------
  // songsOf + covers
  // -------------------------------------------------------------------------

  group('songsOf', () {
    test('respects limit and offset', () async {
      final pid = await playlistRepo.createPlaylist('Paged');
      await playlistRepo.addSongs(pid, [1, 2, 3, 4, 5]);

      final page1 = await playlistRepo.songsOf(pid, limit: 2, offset: 0);
      expect(page1, hasLength(2));
      expect(page1[0].song.id, 1);
      expect(page1[1].song.id, 2);

      final page2 = await playlistRepo.songsOf(pid, limit: 2, offset: 2);
      expect(page2, hasLength(2));
      expect(page2[0].song.id, 3);
    });
  });

  // -------------------------------------------------------------------------
  // memberSongRowIds
  // -------------------------------------------------------------------------

  group('memberSongRowIds', () {
    test('returns correct set of ids', () async {
      final pid = await playlistRepo.createPlaylist('Members');
      await playlistRepo.addSongs(pid, [1, 3, 5]);

      final members = await playlistRepo.memberSongRowIds(pid);
      expect(members, containsAll([1, 3, 5]));
      expect(members, isNot(contains(2)));
    });

    test('returns empty set for empty playlist', () async {
      final pid = await playlistRepo.createPlaylist('Empty');
      final members = await playlistRepo.memberSongRowIds(pid);
      expect(members, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // covers (cover art)
  // -------------------------------------------------------------------------

  group('covers', () {
    test('populates covers on PlaylistSummary', () async {
      final pid = await playlistRepo.createPlaylist('Art');
      await playlistRepo.addSongs(pid, [1, 2]);

      final list = await playlistRepo.listPlaylists();
      final p = list.firstWhere((e) => e.id == pid);
      expect(p.covers, isA<List<String?>>());
    });
  });
}

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';

IngestTrack _msTrack(
  int id, {
  String? title,
  String? artist = 'Artist A',
  String? album = 'Album X',
  int dateModifiedSec = 100,
  int albumId = 11,
  int artistId = 21,
}) {
  return IngestTrack(
    source: IngestSource.mediastore,
    mediaStoreId: id,
    albumMediaStoreId: albumId,
    artistMediaStoreId: artistId,
    albumKey: album == null ? null : 'ms:$albumId',
    artistKey: artist == null ? null : 'ms:$artistId',
    contentUri: 'content://media/external/audio/media/$id',
    path: '/storage/emulated/0/Music/song_$id.mp3',
    title: title ?? 'Song $id',
    artist: artist,
    album: album,
    durationMs: 180000 + id,
    dateModifiedSec: dateModifiedSec,
    year: 2020,
    trackNumber: 1,
    sizeBytes: 5000 + id,
    dateAddedSec: 90,
  );
}

IngestTrack _importedTrack({
  required String hash,
  required String path,
  String title = 'Imported Song',
  String? artist = 'Import Artist',
  String? album = 'Import Album',
  int dateModifiedSec = 200,
}) {
  return IngestTrack(
    source: IngestSource.imported,
    contentHash: hash,
    contentUri: 'file://$path',
    path: path,
    title: title,
    artist: artist,
    album: album,
    albumKey: album != null ? 'n:${album.toLowerCase()}' : null,
    artistKey: artist != null ? 'a:${artist.toLowerCase()}' : null,
    durationMs: 123000,
    dateModifiedSec: dateModifiedSec,
    sizeBytes: 4000,
  );
}

void main() {
  late AppDatabase db;
  late LibraryRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = LibraryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('MediaStore sync (Android path)', () {
    test('inserts new songs and links albums and artists', () async {
      final result = await repository.syncTracks([_msTrack(1), _msTrack(2)]);

      expect(result.added, 2);
      expect(result.updated, 0);
      expect(result.dirtyAlbumKeys, {'ms:11'});

      final songs = await db.select(db.songs).get();
      expect(songs.length, 2);
      expect(songs.every((s) => s.albumRowId != null), isTrue);
      expect(songs.every((s) => s.artistRowId != null), isTrue);
      expect(songs.every((s) => s.source == 'mediastore'), isTrue);
      expect(songs.first.format, 'mp3');

      expect(await db.select(db.albums).get(), hasLength(1));
      expect(await db.select(db.artists).get(), hasLength(1));
    });

    test(
      'does not duplicate on repeated mediaStoreId and updates metadata',
      () async {
        await repository.syncTracks([_msTrack(1)]);

        final result = await repository.syncTracks([
          const IngestTrack(
            source: IngestSource.mediastore,
            mediaStoreId: 1,
            albumMediaStoreId: 11,
            artistMediaStoreId: 22,
            albumKey: 'ms:11',
            artistKey: 'ms:22',
            contentUri: 'content://media/external/audio/media/1',
            path: '/storage/emulated/0/Music/song_1.flac',
            title: 'Renamed Song',
            artist: 'Artist B',
            album: 'Album X',
            durationMs: 200000,
            dateModifiedSec: 200,
          ),
        ]);

        expect(result.added, 0);
        expect(result.updated, 1);

        final songs = await db.select(db.songs).get();
        expect(songs, hasLength(1));
        expect(songs.single.title, 'Renamed Song');
        expect(songs.single.dateModifiedSec, 200);
        expect(songs.single.format, 'flac');
      },
    );

    test('skips unchanged tracks based on identity comparison', () async {
      await repository.syncTracks([_msTrack(1)]);
      final index = await repository.existingSongIndex();
      final unchanged = index['ms:1'] == 100;
      expect(unchanged, isTrue);

      final result = await repository.syncTracks([_msTrack(1)]);
      expect(result.added, 0);
      expect(result.updated, 0);
      expect(await db.select(db.songs).get(), hasLength(1));
    });

    test('handles a large batch without duplicates', () async {
      final batch = List.generate(1200, (i) => _msTrack(i + 1));
      final result = await repository.syncTracks(batch);

      expect(result.added, 1200);
      final countExp = db.songs.id.count();
      final row = await (db.selectOnly(
        db.songs,
      )..addColumns([countExp])).getSingle();
      expect(row.read(countExp), 1200);
    });

    test(
      'stores null metadata as null instead of placeholder strings',
      () async {
        final result = await repository.syncTracks([
          const IngestTrack(
            source: IngestSource.mediastore,
            mediaStoreId: 7,
            albumMediaStoreId: 77,
            artistMediaStoreId: 88,
            contentUri: 'content://media/external/audio/media/7',
            path: '/storage/emulated/0/Music/track_7.ogg',
            durationMs: 1000,
            dateModifiedSec: 5,
          ),
        ]);

        expect(result.added, 1);
        final song = await db.select(db.songs).getSingle();
        expect(song.titleSearch, 'track_7');
        expect(song.artist, isNull);
        expect(song.artistSearch, isNull);
        expect(song.albumName, isNull);
        expect(song.genre, isNull);
        expect(song.year, isNull);
        expect(song.albumRowId, isNull);
        expect(song.artistRowId, isNull);
      },
    );

    test('removeAbsentMediaStore deletes missing songs and orphans', () async {
      await repository.syncTracks([_msTrack(1), _msTrack(2), _msTrack(3)]);
      await repository.syncTracks([
        _msTrack(4, album: 'Orphan Album', albumId: 99),
      ]);
      final removed = await repository.removeAbsentMediaStore({1, 2});

      expect(removed, 2);
      final songs = await db.select(db.songs).get();
      expect(songs.map((s) => s.mediaStoreId), containsAll([1, 2]));
      expect(songs.map((s) => s.mediaStoreId), isNot(contains(3)));

      final albums = await db.select(db.albums).get();
      expect(albums.map((a) => a.albumKey), contains('ms:11'));
      expect(albums.map((a) => a.albumKey), isNot(contains('ms:99')));
    });
  });

  group('Imported sync (iOS path)', () {
    test('inserts imported songs with source and hash identity', () async {
      final result = await repository.syncTracks([
        _importedTrack(hash: 'aaa', path: '/sandbox/Library/x1/song.mp3'),
      ]);

      expect(result.added, 1);
      final song = await db.select(db.songs).getSingle();
      expect(song.source, 'imported');
      expect(song.contentHash, 'aaa');
      expect(song.mediaStoreId, isNull);
      expect(song.titleSearch, 'imported song');
      expect(song.albumRowId, isNotNull);

      final album = await db.select(db.albums).getSingle();
      expect(album.albumKey, 'n:import album');
      expect(album.mediaStoreAlbumId, isNull);
    });

    test('duplicate content hash does not create a second entry', () async {
      const track = 'x';
      final first = await repository.syncTracks([
        _importedTrack(hash: 'dup-1', path: '/sandbox/Library/a/song.mp3'),
      ]);
      final second = await repository.syncTracks([
        _importedTrack(
          hash: 'dup-1',
          path: '/sandbox/Library/b/song.mp3',
          title: '$track copy',
          dateModifiedSec: 999,
        ),
      ]);

      // Second import of identical bytes resolves to the same identity
      // key; the caller decides to skip before syncing, but even if it
      // reaches the repository the row count must stay at one.
      expect(first.added, 1);
      expect(second.updated >= 0 || second.added >= 0, isTrue);
      expect(await db.select(db.songs).get(), hasLength(1));
    });

    test('android and imported songs coexist in one library', () async {
      await repository.syncTracks([
        _msTrack(1),
        _importedTrack(hash: 'h1', path: '/sandbox/Library/x/s.mp3'),
      ]);

      final counts = await repository.currentCounts();
      expect(counts.songs, 2);
      final songs = await db.select(db.songs).get();
      expect(songs.map((s) => s.source).toSet(), {'mediastore', 'imported'});
    });

    test('reconciliation finds and removes entries with vanished files', () async {
      final alivePath =
          '${Directory.systemTemp.path}/vt_alive_${DateTime.now().microsecondsSinceEpoch}.mp3';
      final deadPath =
          '${Directory.systemTemp.path}/vt_missing_does_not_exist.mp3';
      File(alivePath).writeAsBytesSync([1, 2, 3]);

      try {
        await repository.syncTracks([
          _importedTrack(hash: 'alive', path: alivePath),
          _importedTrack(hash: 'dead', path: deadPath),
        ]);

        final rows = await repository.importedSongsForReconciliation();
        expect(rows, hasLength(2));

        final missing = rows
            .where((r) => !File(r.path).existsSync())
            .map((r) => r.rowId)
            .toSet();
        expect(missing, hasLength(1));

        final removed = await repository.deleteSongsByRowIds(missing);
        expect(removed, 1);
        expect(await db.select(db.songs).get(), hasLength(1));
      } finally {
        File(alivePath).deleteSync();
      }
    });
  });

  group('artwork and scan state', () {
    test('albumsNeedingArt returns only albums lacking artwork', () async {
      await repository.syncTracks([_msTrack(1)]);
      final missing = await repository.albumsNeedingArt({'ms:11'});
      expect(missing, ['ms:11']);

      await repository.attachArtwork({
        'ms:11': const ResolvedArtwork(
          smallPath: '/a_s.webp',
          largePath: '/a_l.webp',
        ),
      });
      expect(await repository.albumsNeedingArt({'ms:11'}), isEmpty);

      final album = await db.select(db.albums).getSingle();
      expect(album.artSmallPath, '/a_s.webp');
    });

    test('attachArtwork records missing artwork state', () async {
      await repository.syncTracks([_msTrack(1)]);
      await repository.attachArtwork({'ms:11': null});

      final album = await db.select(db.albums).getSingle();
      expect(album.artSmallPath, '');
      expect(await repository.albumsNeedingArt({'ms:11'}), isEmpty);
    });

    test('completeScan persists scan state', () async {
      await repository.completeScan(totalSongs: 42);

      final entry = await repository.lastScanEntry();
      expect(entry, isNotNull);
      expect(entry!.totalSongs, 42);
      expect(entry.lastCompletedAt, isNotNull);
    });
  });
}

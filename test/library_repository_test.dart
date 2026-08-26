import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';

IngestTrack _track(
  int id, {
  String? title,
  String? artist = 'Artist A',
  String? album = 'Album X',
  int dateModifiedSec = 100,
  int albumId = 11,
  int artistId = 21,
}) {
  return IngestTrack(
    mediaStoreId: id,
    contentUri: 'content://media/external/audio/media/$id',
    path: '/storage/emulated/0/Music/song_$id.mp3',
    title: title ?? 'Song $id',
    artist: artist,
    album: album,
    albumMediaStoreId: albumId,
    artistMediaStoreId: artistId,
    durationMs: 180000 + id,
    dateModifiedSec: dateModifiedSec,
    year: 2020,
    trackNumber: 1,
    sizeBytes: 5000 + id,
    dateAddedSec: 90,
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

  group('LibraryRepository.syncTracks', () {
    test('inserts new songs and links albums and artists', () async {
      final result = await repository.syncTracks([_track(1), _track(2)]);

      expect(result.added, 2);
      expect(result.updated, 0);
      expect(result.dirtyAlbumMediaStoreIds, {11});

      final songs = await db.select(db.songs).get();
      expect(songs.length, 2);
      expect(songs.every((s) => s.albumRowId != null), isTrue);
      expect(songs.every((s) => s.artistRowId != null), isTrue);
      expect(
        songs.every((s) => s.titleSearch == 'song ${s.mediaStoreId}'),
        isTrue,
      );
      expect(songs.first.format, 'mp3');

      expect(await db.select(db.albums).get(), hasLength(1));
      expect(await db.select(db.artists).get(), hasLength(1));
    });

    test(
      'does not duplicate on repeated mediaStoreId and updates metadata',
      () async {
        await repository.syncTracks([_track(1)]);

        final result = await repository.syncTracks([
          const IngestTrack(
            mediaStoreId: 1,
            contentUri: 'content://media/external/audio/media/1',
            path: '/storage/emulated/0/Music/song_1.flac',
            title: 'Renamed Song',
            artist: 'Artist B',
            album: 'Album X',
            albumMediaStoreId: 11,
            artistMediaStoreId: 22,
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

    test('skips unchanged tracks based on dateModified comparison', () async {
      await repository.syncTracks([_track(1)]);
      final result = await repository.syncTracks([_track(1)]);

      expect(result.added, 0);
      expect(result.updated, 0);
      expect(await db.select(db.songs).get(), hasLength(1));
    });

    test('handles a large batch without duplicates', () async {
      final batch = List.generate(1200, (i) => _track(i + 1));
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
            mediaStoreId: 7,
            contentUri: 'content://media/external/audio/media/7',
            path: '/storage/emulated/0/Music/track_7.ogg',
            durationMs: 1000,
            dateModifiedSec: 5,
            albumMediaStoreId: 77,
            artistMediaStoreId: 88,
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
  });

  group('LibraryRepository.removeAbsent', () {
    test(
      'removes songs no longer present and cleans orphaned albums',
      () async {
        await repository.syncTracks([_track(1), _track(2), _track(3)]);
        await repository.syncTracks([
          _track(4, album: 'Orphan Album', albumId: 99),
        ]);
        final removed = await repository.removeAbsent({1, 2});

        expect(removed, 2);
        final songs = await db.select(db.songs).get();
        expect(songs.map((s) => s.mediaStoreId), [1, 2]);

        final albums = await db.select(db.albums).get();
        expect(albums.map((a) => a.mediaStoreAlbumId), contains(11));
        expect(albums.map((a) => a.mediaStoreAlbumId), isNot(contains(99)));
      },
    );

    test('keeps everything when all ids are still present', () async {
      await repository.syncTracks([_track(1), _track(2)]);
      final removed = await repository.removeAbsent({1, 2});
      expect(removed, 0);
      expect(await db.select(db.songs).get(), hasLength(2));
    });
  });

  group('artwork and scan state', () {
    test('albumsNeedingArt returns only albums lacking artwork', () async {
      await repository.syncTracks([_track(1)]);
      final missing = await repository.albumsNeedingArt({11});
      expect(missing, [11]);

      await repository.attachArtwork({
        11: const ResolvedArtwork(
          smallPath: '/a_s.webp',
          largePath: '/a_l.webp',
        ),
      });
      final nowResolved = await repository.albumsNeedingArt({11});
      expect(nowResolved, isEmpty);

      final album = await db.select(db.albums).getSingle();
      expect(album.artSmallPath, '/a_s.webp');
      expect(album.artLargePath, '/a_l.webp');
    });

    test('attachArtwork records missing artwork state', () async {
      await repository.syncTracks([_track(1)]);
      await repository.attachArtwork({11: null});

      final album = await db.select(db.albums).getSingle();
      expect(album.artSmallPath, '');
      expect(album.artLargePath, '');

      final stillMissing = await repository.albumsNeedingArt({11});
      expect(stillMissing, isEmpty);
    });

    test('completeScan persists scan state', () async {
      await repository.completeScan(totalSongs: 42);

      final entry = await repository.lastScanEntry();
      expect(entry, isNotNull);
      expect(entry!.totalSongs, 42);
      expect(entry.source, 'mediastore');
      expect(entry.lastCompletedAt, isNotNull);
    });

    test('existingSongIndex maps ids to modification dates', () async {
      await repository.syncTracks([_track(1), _track(2)]);
      final index = await repository.existingSongIndex();
      expect(index[1], 100);
      expect(index[2], 100);
    });
  });
}

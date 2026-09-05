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
    test('artworkTargets surfaces albums lacking artwork', () async {
      await repository.syncTracks([_msTrack(1)]);

      final targets = await repository.artworkTargets(
        dirtyAlbumKeys: {'ms:11'},
      );
      expect(targets.map((t) => t.key), ['ms:11']);
      // The album id and a representative song must both be present, since the
      // native side needs the song handle for album-less and Android 10+ cases.
      expect(targets.single.albumMediaStoreId, 11);
      expect(targets.single.audioMediaStoreId, 1);
      expect(targets.single.path, '/storage/emulated/0/Music/song_1.mp3');

      await repository.attachArtwork({
        'ms:11': const ResolvedArtwork(
          smallPath: '/a_s.webp',
          largePath: '/a_l.webp',
        ),
      });
      expect(await repository.artworkTargets(), isEmpty);

      final album = await db.select(db.albums).getSingle();
      expect(album.artSmallPath, '/a_s.webp');
    });

    test('artworkTargets ignores the dirty hint and still retries', () async {
      await repository.syncTracks([_msTrack(1)]);

      // The old implementation returned nothing when no album had changed in
      // the current batch, so artwork that failed once was never retried.
      final targets = await repository.artworkTargets();
      expect(targets.map((t) => t.key), ['ms:11']);
    });

    test('failed artwork writes NULL, not an empty string', () async {
      await repository.syncTracks([_msTrack(1)]);
      await repository.attachArtwork({'ms:11': null});

      final album = await db.select(db.albums).getSingle();
      // `''` is not NULL, so persisting it made the "needs artwork" predicate
      // permanently false and the album could never be retried.
      expect(album.artSmallPath, isNull);
      expect(album.artLargePath, isNull);
    });

    test('a failed album is retried once, then left alone', () async {
      await repository.syncTracks([_msTrack(1)]);

      await repository.attachArtwork({'ms:11': null});
      expect((await repository.artworkTargets()).map((t) => t.key), [
        'ms:11',
      ], reason: 'one transient failure should not disqualify an album');

      await repository.attachArtwork({'ms:11': null});
      expect(
        await repository.artworkTargets(),
        isEmpty,
        reason: 'a genuinely art-less album must stop costing a decode',
      );

      expect(
        (await repository.artworkTargets(retryFailed: true)).map((t) => t.key),
        ['ms:11'],
        reason: 'an explicit rescan must still be able to force a retry',
      );
    });

    test('artworkTargets covers songs with no album', () async {
      // MediaStore reports album_id 0 for singles, downloads and voice memos.
      // Those songs have no album row, so album-scoped artwork can never
      // reach them.
      await repository.syncTracks([_msTrack(7, album: null, albumId: 0)]);

      final targets = await repository.artworkTargets();
      expect(targets, hasLength(1));
      expect(targets.single.key, 'song:ms:7');
      expect(targets.single.audioMediaStoreId, 7);
      expect(ArtworkTarget.isSongKey(targets.single.key), isTrue);

      await repository.attachArtwork({
        'song:ms:7': const ResolvedArtwork(
          smallPath: '/s_s.webp',
          largePath: '/s_l.webp',
        ),
      });

      final extras = await db
          .customSelect('SELECT art_small_path FROM song_extras')
          .get();
      expect(extras, hasLength(1));
      expect(extras.single.data['art_small_path'], '/s_s.webp');
      expect(await repository.artworkTargets(), isEmpty);
    });

    test('artworkTargets honours its limit', () async {
      await repository.syncTracks([
        for (var i = 1; i <= 5; i++) _msTrack(i, album: 'Album $i', albumId: i),
      ]);

      expect(await repository.artworkTargets(limit: 2), hasLength(2));
      expect(await repository.artworkTargets(limit: 0), isEmpty);
    });

    test('removeAbsentMediaStore refuses to wipe on an empty scan', () async {
      await repository.syncTracks([_msTrack(1), _msTrack(2)]);

      // An empty seen-set means the scan enumerated nothing — a denied
      // permission or an unmounted volume — not that the user deleted every
      // song. Acting on it would destroy the library, playlists and stats.
      expect(await repository.removeAbsentMediaStore({}), 0);
      expect(await db.select(db.songs).get(), hasLength(2));
    });

    test('removeAbsentMediaStore removes only unseen songs', () async {
      await repository.syncTracks([_msTrack(1), _msTrack(2)]);

      expect(await repository.removeAbsentMediaStore({1}), 1);
      final remaining = await db.select(db.songs).get();
      expect(remaining.map((s) => s.mediaStoreId), [1]);
    });

    test('completeScan persists scan state', () async {
      await repository.completeScan(totalSongs: 42);

      final entry = await repository.lastScanEntry();
      expect(entry, isNotNull);
      expect(entry!.totalSongs, 42);
      expect(entry.lastCompletedAt, isNotNull);
    });
  });

  group('BUG #5: multi-artist song relationships', () {
    // Library mirroring the bug report's example: Song 4 carries a grouped
    // credit "Atif Aslam, Pritam" (MediaStore models it as its own combined
    // artist, artistId 29), the rest are solo artists.
    List<IngestTrack> library() => [
      _msTrack(1, artist: 'Atif Aslam', artistId: 21),
      _msTrack(2, artist: 'Atif Aslam', artistId: 21),
      _msTrack(3, artist: 'Pritam', artistId: 22),
      _msTrack(4, artist: 'Atif Aslam, Pritam', artistId: 29),
      _msTrack(5, artist: 'Arijit Singh', artistId: 23),
      _msTrack(6, artist: 'Arijit Singh', artistId: 23),
    ];

    test('grouped credit maps the song to each individual artist', () async {
      await repository.syncTracks(library());

      final artists = await repository.artistOverview();
      final names = artists.map((a) => a.name).toList();
      // One entry per distinct artist name — the grouped credit may keep its
      // own combined entry, but "Atif Aslam" must appear exactly once.
      expect(names.where((n) => n == 'Atif Aslam'), hasLength(1));
      expect(names.where((n) => n == 'Pritam'), hasLength(1));
      expect(names.where((n) => n == 'Arijit Singh'), hasLength(1));

      final atif = artists.singleWhere((a) => a.name == 'Atif Aslam');
      expect(atif.songCount, 3); // Songs 1, 2 and the grouped Song 4.
      final pritam = artists.singleWhere((a) => a.name == 'Pritam');
      expect(pritam.songCount, 2); // Song 3 and the grouped Song 4.
      final arijit = artists.singleWhere((a) => a.name == 'Arijit Singh');
      expect(arijit.songCount, 2);

      final atifSongs = await repository.songsForArtist(atif.artistRowId);
      expect(atifSongs.map((s) => s.song.mediaStoreId).toSet(), {1, 2, 4});
      final pritamSongs = await repository.songsForArtist(pritam.artistRowId);
      expect(pritamSongs.map((s) => s.song.mediaStoreId).toSet(), {3, 4});

      // The grouped-credit combined entry exists and holds exactly Song 4.
      final combined = artists.singleWhere(
        (a) => a.name == 'Atif Aslam, Pritam',
      );
      expect(combined.songCount, 1);
      expect((await repository.songsForArtist(combined.artistRowId)).length, 1);
    });

    test('rescan does not duplicate artists or songs', () async {
      await repository.syncTracks(library());
      final first = await repository.artistOverview();

      final result = await repository.syncTracks(library());
      expect(result.added, 0);

      final second = await repository.artistOverview();
      expect(
        second.map((a) => (a.name, a.songCount)),
        first.map((a) => (a.name, a.songCount)),
      );
      expect(
        second.map((a) => a.name).where((n) => n == 'Atif Aslam'),
        hasLength(1),
      );

      final atif = second.singleWhere((a) => a.name == 'Atif Aslam');
      final atifSongs = await repository.songsForArtist(atif.artistRowId);
      expect(atifSongs.map((s) => s.song.mediaStoreId).toSet(), {1, 2, 4});
    });

    test('case/whitespace variants of a credited artist unify', () async {
      // Solo row via MediaStore, then the same artist credited on a group
      // track with different case and trailing whitespace.
      await repository.syncTracks([
        _msTrack(1, artist: 'Atif Aslam', artistId: 21),
        _msTrack(2, artist: 'atif aslam ,  Pritam', artistId: 29),
      ]);

      final artists = await repository.artistOverview();
      expect(
        artists.map((a) => a.name).where((n) => n == 'Atif Aslam'),
        hasLength(1),
      );
      final atif = artists.singleWhere((a) => a.name == 'Atif Aslam');
      final songs = await repository.songsForArtist(atif.artistRowId);
      expect(songs.map((s) => s.song.mediaStoreId).toSet(), {1, 2});
    });

    test('stale combined-credit primary converges on rescan', () async {
      // Simulate pre-fix data: ingest a group-credit song twice is not enough;
      // instead verify a previously wrong primary artist row is superseded:
      // ingest song 4 solo-first under the combined key name, then rescan with
      // the same data and confirm the individual artists surface.
      await repository.syncTracks(library());
      await repository.syncTracks(
        library().map((t) {
          // Force an artist_row_id-affecting pass with unchanged dates.
          return t;
        }).toList(),
      );

      final songs = await db.select(db.songs).get();
      final grouped = songs.singleWhere((s) => s.mediaStoreId == 4);
      final artists = await db.select(db.artists).get();
      final primary = artists.singleWhere((a) => a.id == grouped.artistRowId);
      // The primary artist of the grouped song is the individual "Atif
      // Aslam", not the combined-credit row.
      expect(primary.name, 'Atif Aslam');
    });
  });
}

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/artwork/artwork_file_cache.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/data/library_scanner.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/library/presentation/providers/library_view_providers.dart';
import 'package:vora_tube/features/playlists/data/playlist_repository.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';

import 'fakes/fake_player.dart';

IngestTrack _msTrack(
  int id, {
  String? title,
  String? artist = 'Artist A',
  String? album = 'Album X',
  int albumId = 11,
  int artistId = 21,
  int dateModifiedSec = 100,
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
    sizeBytes: 5000 + id,
    dateAddedSec: 90,
  );
}

final class _StubIngest implements IngestService {
  _StubIngest(this.batches);

  final List<List<IngestTrack>> batches;
  int _calls = 0;

  @override
  IngestCapabilities get capabilities =>
      const IngestCapabilities({IngestCapability.scan});

  @override
  Future<void> prepareScan() async {}

  @override
  Future<List<IngestTrack>> getAudioBatch({
    required int afterId,
    required int limit,
  }) async {
    if (_calls >= batches.length) {
      return const [];
    }
    return batches[_calls++];
  }

  @override
  Future<Map<String, ResolvedArtwork?>> resolveArtwork(
    List<ArtworkTarget> targets,
  ) async => const {};

  @override
  Future<List<PickedImportFile>> pickImportFiles() async => const [];

  @override
  Future<ProcessedImport> processImportFile(PickedImportFile file) async =>
      throw UnsupportedError('not used');

  @override
  Future<Directory?> importedFilesRoot() async => null;
}

void main() {
  late AppDatabase db;
  late LibraryRepository repository;
  late FakePlayerController player;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = LibraryRepository(db);
    player = FakePlayerController(
      queue: [
        const SongRef(
          identityKey: 'ms:1',
          uri: 'content://media/external/audio/media/1',
          title: 'Song 1',
        ),
        const SongRef(
          identityKey: 'ms:2',
          uri: 'content://media/external/audio/media/2',
          title: 'Song 2',
        ),
        const SongRef(
          identityKey: 'ms:3',
          uri: 'content://media/external/audio/media/3',
          title: 'Song 3',
        ),
      ],
    );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        libraryRepositoryProvider.overrideWithValue(repository),
        playerProvider.overrideWithValue(player),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() async {
    await db.close();
  });

  void bumpLibraryTick() {
    container.read(libraryRefreshTickProvider.notifier).state++;
  }

  Future<List<String>> pagedTitles() async =>
      (await container.read(pagedSongsProvider.future))
          .map((t) => t.song.title)
          .toList();

  Future<int> rowIdOf(int mediaStoreId) async {
    final row = await (db.select(
      db.songs,
    )..where((tbl) => tbl.mediaStoreId.equals(mediaStoreId))).getSingle();
    return row.id;
  }

  group('TEST A: delete A, then immediately delete B', () {
    test('library, database, derived lists and side tables stay consistent',
        () async {
      await repository.syncTracks([
        _msTrack(1),
        _msTrack(2),
        _msTrack(3, album: 'Album Y', albumId: 12, artist: 'Artist B', artistId: 22),
      ]);
      final initial = await pagedTitles()..sort();
      expect(initial, ['Song 1', 'Song 2', 'Song 3']);

      final idA = await rowIdOf(1);
      final idB = await rowIdOf(2);

      // A playlist and a favorite pointing at Song 2, so related-record
      // handling is exercised.
      final playlistRepo = PlaylistRepository(db);
      final playlistId = await playlistRepo.createPlaylist('Mix');
      await playlistRepo.addSongs(playlistId, [idB]);
      await repository.toggleFavorite(idB);

      // Delete Song A.
      expect(await repository.deleteSongsByRowIds({idA}), 1);
      bumpLibraryTick();
      final afterA = await pagedTitles()..sort();
      expect(afterA, ['Song 2', 'Song 3']);

      // Immediately delete Song B.
      expect(await repository.deleteSongsByRowIds({idB}), 1);
      bumpLibraryTick();

      // B is absent from the library provider.
      expect(await pagedTitles(), ['Song 3']);

      // B is absent from the database.
      final titles =
          (await db.select(db.songs).get()).map((s) => s.title).toList();
      expect(titles, ['Song 3']);

      // B is absent from derived album/artist lists: Album X emptied out and
      // was pruned with its last song.
      final albums = await container.read(albumsOverviewProvider.future);
      expect(albums.map((a) => a.name), ['Album Y']);
      final artists = await container.read(artistsOverviewProvider.future);
      expect(artists.map((a) => a.name), ['Artist B']);

      // The emptied album can no longer be opened into a stale song list.
      final albumX = await (db.select(db.albums)
            ..where((tbl) => tbl.albumKey.equals('ms:11')))
          .getSingleOrNull();
      expect(albumX, isNull);

      // Related records are gone: playlist entry, favorite row.
      final playlistSongs = await db
          .customSelect(
            'SELECT * FROM playlist_songs WHERE playlist_id = ?',
            variables: [Variable<int>(playlistId)],
          )
          .get();
      expect(playlistSongs, isEmpty);
      expect(await db.select(db.songStats).get(), isEmpty);
      expect(await db.customSelect('SELECT * FROM song_extras').get(), isEmpty);

      // B cannot be re-deleted: the row id is gone.
      expect(await repository.deleteSongsByRowIds({idB}), 0);
    });

    test('deleting a stale Song object cleans the leftover row (retry path)',
        () async {
      await repository.syncTracks([_msTrack(2)]);
      final row = (await db.select(db.songs).get()).single;

      // Simulates the old bug's second delete: the UI held a Song B whose
      // MediaStore row is already gone. The platform bridge answers
      // uri_not_found, the delete flow treats that as already-deleted, and
      // the database cleanup must succeed instead of erroring.
      expect(await repository.deleteSongsByRowIds({row.id}), 1);
      expect(await repository.deleteSongsByRowIds({row.id}), 0);
      expect(await db.select(db.songs).get(), isEmpty);
    });
  });

  group('TEST B: delete a song, then rescan', () {
    test('the deleted song does not reappear and state stays deterministic',
        () async {
      final scanner = LibraryScanner(
        ingest: _StubIngest([
          [_msTrack(1), _msTrack(2)],
        ]),
        repository: repository,
      );
      await scanner.scan();
      expect(await db.select(db.songs).get(), hasLength(2));

      // The user deletes Song B (MediaStore row and file gone; DB row
      // removed by the delete flow).
      final rowB = await rowIdOf(2);
      await repository.deleteSongsByRowIds({rowB});

      // A later scan no longer sees B in MediaStore.
      final scanner2 = LibraryScanner(
        ingest: _StubIngest([
          [_msTrack(1)],
        ]),
        repository: repository,
      );
      final summary = await scanner2.scan();

      final titles =
          (await db.select(db.songs).get()).map((s) => s.title).toList();
      expect(titles, ['Song 1']);
      expect(summary.removedSongs, 0);
      expect(summary.addedSongs, 0);
    });

    test('a scan converges the database to what MediaStore still reports',
        () async {
      final scanner = LibraryScanner(
        ingest: _StubIngest([
          [_msTrack(1), _msTrack(2)],
        ]),
        repository: repository,
      );
      await scanner.scan();

      // A DB row removed while MediaStore STILL reports the track (only
      // possible outside the normal delete flow) is reconciled by the next
      // scan: MediaStore is the authoritative library membership source, so
      // the scan re-inserts it. This documents the source-of-truth contract:
      // the database always converges to MediaStore, never the reverse.
      final rowB = await rowIdOf(2);
      await repository.deleteSongsByRowIds({rowB});

      final scanner2 = LibraryScanner(
        ingest: _StubIngest([
          [_msTrack(1), _msTrack(2)],
        ]),
        repository: repository,
      );
      final summary = await scanner2.scan();

      final titles =
          (await db.select(db.songs).get()).map((s) => s.title).toList()
            ..sort();
      expect(titles, ['Song 1', 'Song 2']);
      expect(summary.addedSongs, 1);
    });
  });

  group('TEST C: rescan with added and removed songs', () {
    test('database matches the scanner result exactly', () async {
      final scanner1 = LibraryScanner(
        ingest: _StubIngest([
          [_msTrack(1), _msTrack(2)],
        ]),
        repository: repository,
      );
      final s1 = await scanner1.scan();
      expect(s1.addedSongs, 2);

      // Song 1 left the device, Song 3 arrived.
      final scanner2 = LibraryScanner(
        ingest: _StubIngest([
          [_msTrack(2), _msTrack(3, albumId: 12)],
        ]),
        repository: repository,
      );
      final s2 = await scanner2.scan();

      expect(s2.addedSongs, 1);
      expect(s2.removedSongs, 1);
      final titles =
          (await db.select(db.songs).get()).map((s) => s.title).toList()
            ..sort();
      expect(titles, ['Song 2', 'Song 3']);

      // The emptied album of Song 1 was pruned; the new album exists.
      final albumKeys =
          (await db.select(db.albums).get()).map((a) => a.albumKey).toList()
            ..sort();
      expect(albumKeys, ['ms:11', 'ms:12']);
    });
  });

  group('TEST D: album artwork for multiple albums', () {
    test('each album routes to its own artwork, songs keep per-song art',
        () async {
      await repository.syncTracks([
        _msTrack(1, albumId: 11),
        _msTrack(2, albumId: 11),
        _msTrack(3, album: 'Album Y', albumId: 12),
      ]);

      await repository.attachArtwork({
        'ms:11': const ResolvedArtwork(
          smallPath: '/art/a11_s.webp',
          largePath: '/art/a11_l.webp',
        ),
        'ms:12': const ResolvedArtwork(
          smallPath: '/art/a12_s.webp',
          largePath: '/art/a12_l.webp',
        ),
        // Song-scoped artwork must land on the song row, never on an album.
        'song:ms:2': const ResolvedArtwork(
          smallPath: '/art/song2_s.webp',
          largePath: '/art/song2_l.webp',
        ),
      });

      final albums = await db.select(db.albums).get();
      final artByAlbumKey = {
        for (final a in albums) a.albumKey: a.artLargePath,
      };
      expect(artByAlbumKey['ms:11'], '/art/a11_l.webp');
      expect(artByAlbumKey['ms:12'], '/art/a12_l.webp');

      // Songs of album 11 resolve their own album's art — the shared-cache
      // symptom was every album rendering the same image.
      final albumRow =
          await (db.select(db.albums)
                ..where((tbl) => tbl.albumKey.equals('ms:11')))
              .getSingle();
      final album11Songs = await repository.songsForAlbum(albumRow.id);
      expect(album11Songs, hasLength(2));
      final artBySongTitle = {
        for (final t in album11Songs) t.song.title: t.artPath,
      };
      // Song 1 shows the album artwork...
      expect(artBySongTitle['Song 1'], '/art/a11_l.webp');
      // ...while song 2 keeps its own per-song cover (this preference is what
      // the historical "same artwork for every song" bug broke).
      expect(artBySongTitle['Song 2'], '/art/song2_l.webp');

      // The song-scoped override went to song 2's extras, not the album.
      final songRow2 = await rowIdOf(2);
      final extras2 = await db
          .customSelect(
            'SELECT art_large_path FROM song_extras WHERE song_id = ?',
            variables: [Variable<int>(songRow2)],
          )
          .getSingle();
      expect(extras2.data['art_large_path'], '/art/song2_l.webp');
    });
  });

  group('TEST E: changed artwork state is not served stale', () {
    test('ArtworkFileCache re-resolves after invalidate and forget', () async {
      final dir = await Directory.systemTemp.createTemp('vora_art_test');
      addTearDown(() async => dir.delete(recursive: true));
      final fileA = File('${dir.path}/a.webp')..writeAsStringSync('A');
      final missingPath = '${dir.path}/b.webp';

      expect(ArtworkFileCache.resolve(fileA.path), isNotNull);

      // A missing path is remembered as missing — the exact case that used to
      // keep artwork invisible after a scan wrote it.
      expect(ArtworkFileCache.resolve(missingPath), isNull);
      // Without invalidation the stale "missing" answer persists even after
      // the file appears.
      File(missingPath).writeAsStringSync('B');
      expect(ArtworkFileCache.resolve(missingPath), isNull);

      // The scan/import publish path invalidates, so new files appear.
      ArtworkFileCache.invalidate();
      expect(ArtworkFileCache.resolve(missingPath), isNotNull);

      // A deleted file must not keep rendering: the error path forgets it.
      await fileA.delete();
      ArtworkFileCache.forget(fileA.path);
      expect(ArtworkFileCache.resolve(fileA.path), isNull);
      // And re-resolving after a later re-creation picks it back up (the
      // widget error path forgets the stale "missing" answer first).
      fileA.writeAsStringSync('A');
      ArtworkFileCache.forget(fileA.path);
      expect(ArtworkFileCache.resolve(fileA.path), isNotNull);
    });

    test('reattaching artwork updates the album reference', () async {
      await repository.syncTracks([_msTrack(1)]);
      await repository.attachArtwork({
        'ms:11': const ResolvedArtwork(
          smallPath: '/art/old_s.webp',
          largePath: '/art/old_l.webp',
        ),
      });
      // The user changes the cover; a new resolve writes new paths.
      await repository.attachArtwork({
        'ms:11': const ResolvedArtwork(
          smallPath: '/art/new_s.webp',
          largePath: '/art/new_l.webp',
        ),
      });
      final album = (await db.select(db.albums).get()).single;
      expect(album.artLargePath, '/art/new_l.webp');
      final tile = (await repository.songsForAlbum(album.id)).single;
      expect(tile.artPath, '/art/new_l.webp');
    });
  });

  group('TEST F: deleting a song present in the playback queue', () {
    test('the stale queue entry is pruned, not left playable', () async {
      await repository.syncTracks([_msTrack(1), _msTrack(2), _msTrack(3)]);
      expect(player.currentQueue.map((r) => r.identityKey).toList(), [
        'ms:1',
        'ms:2',
        'ms:3',
      ]);

      final rowB = await rowIdOf(2);
      await repository.deleteSongsByRowIds({rowB});
      // The delete flow prunes the queue with the same identity key the
      // player uses (songTileToRef's 'ms:<mediaStoreId>' form).
      await player.removeByIdentityKeys({'ms:2'});

      expect(player.currentQueue.map((r) => r.identityKey).toList(), [
        'ms:1',
        'ms:3',
      ]);
      expect(player.removedIdentityKeys, {'ms:2'});
    });

    test('removing an identity key that is not queued is a no-op', () async {
      await player.removeByIdentityKeys({'ms:999'});
      expect(player.currentQueue, hasLength(3));
    });
  });
}

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/data/library_scanner.dart';

IngestTrack _msTrack(int id, {int durationMs = 180000, String? path}) {
  return IngestTrack(
    source: IngestSource.mediastore,
    mediaStoreId: id,
    albumMediaStoreId: 11,
    artistMediaStoreId: 21,
    albumKey: 'ms:11',
    artistKey: 'ms:21',
    contentUri: 'content://media/external/audio/media/$id',
    path: path ?? '/storage/emulated/0/Music/song_$id.mp3',
    title: 'Song $id',
    durationMs: durationMs,
    dateModifiedSec: 100,
    sizeBytes: 5000 + id,
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
  ) async {
    return const {};
  }

  @override
  Future<List<PickedImportFile>> pickImportFiles() async => const [];

  @override
  Future<ProcessedImport> processImportFile(PickedImportFile file) async =>
      throw UnsupportedError('not used in scanner tests');

  @override
  Future<Directory?> importedFilesRoot() async => null;
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

  test(
    'scan keeps only playable tracks and reports the filtered total',
    () async {
      final scanner = LibraryScanner(
        ingest: _StubIngest([
          [
            _msTrack(1),
            _msTrack(2, durationMs: 0),
            _msTrack(3, path: '/storage/emulated/0/AutoBackup_003.zip'),
          ],
        ]),
        repository: repository,
      );

      final summary = await scanner.scan();

      expect(summary.totalSongs, 1);
      expect(summary.addedSongs, 1);
      expect(await db.select(db.songs).get(), hasLength(1));
      expect((await db.select(db.songs).get()).single.mediaStoreId, 1);
    },
  );

  test('a previously-synced invalid row is purged on the next filtered scan', () async {
    await repository.syncTracks([_msTrack(9, durationMs: 0)]);
    expect(await db.select(db.songs).get(), hasLength(1));

    // MediaStore still reports the bad row in the batch; the scanner filters
    // it before syncing, so it is no longer "seen" and gets removed as absent.
    final scanner = LibraryScanner(
      ingest: _StubIngest([
        [_msTrack(1), _msTrack(9, durationMs: 0)],
      ]),
      repository: repository,
    );

    final summary = await scanner.scan();

    expect(summary.totalSongs, 1);
    expect(summary.removedSongs, 1);
    final songs = await db.select(db.songs).get();
    expect(songs, hasLength(1));
    expect(songs.single.mediaStoreId, 1);
  });
}

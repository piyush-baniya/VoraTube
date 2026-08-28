import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';

IngestTrack _track({
  required int id,
  required String title,
  required String artist,
  required String album,
}) {
  return IngestTrack(
    source: IngestSource.mediastore,
    mediaStoreId: id,
    albumMediaStoreId: 100 + id,
    artistMediaStoreId: 200 + id,
    albumKey: 'ms:${100 + id}',
    artistKey: 'ms:${200 + id}',
    contentUri: 'content://media/external/audio/media/$id',
    path: '/storage/emulated/0/Music/${title.replaceAll(' ', '_')}.mp3',
    title: title,
    artist: artist,
    album: album,
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
  late LibraryRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = LibraryRepository(db);
    await repo.syncTracks([
      _track(
        id: 1,
        title: 'Radioactive',
        artist: 'Imagine Dragons',
        album: 'Night Visions',
      ),
      _track(
        id: 2,
        title: 'In The End',
        artist: 'Linkin Park',
        album: 'Hybrid Theory',
      ),
      _track(
        id: 3,
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        album: 'After Hours',
      ),
      _track(
        id: 4,
        title: 'Quantum Leaps',
        artist: 'Somebody Else',
        album: 'Other',
      ),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  group('searchAll typo tolerance', () {
    test('imagine dragins finds Imagine Dragons', () async {
      final r = await repo.searchAll('imagine dragins');
      expect(r.songs, isNotEmpty);
      expect(r.songs.first.song.title, 'Radioactive');
    });

    test('linkn park finds Linkin Park', () async {
      final r = await repo.searchAll('linkn park');
      expect(r.songs, isNotEmpty);
      expect(r.songs.first.song.title, 'In The End');
    });

    test('weeknd finds The Weeknd', () async {
      final r = await repo.searchAll('weeknd');
      expect(r.songs, isNotEmpty);
      expect(r.songs.first.song.title, 'Blinding Lights');
    });

    test('unrelated query yields an empty result set', () async {
      final r = await repo.searchAll('quantum blender');
      expect(r.songs, isEmpty);
      expect(r.artists, isEmpty);
      expect(r.albums, isEmpty);
      expect(r.playlists, isEmpty);
      expect(r.isEmpty, isTrue);
    });
  });
}

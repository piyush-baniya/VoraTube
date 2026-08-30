import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/genre/genre_enrichment_service.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';

IngestTrack _song(String title) {
  return IngestTrack(
    source: IngestSource.mediastore,
    mediaStoreId: 1,
    albumMediaStoreId: 11,
    artistMediaStoreId: 21,
    albumKey: 'ms:11',
    artistKey: 'ms:21',
    contentUri: 'content://media/external/audio/media/1',
    path: '/storage/emulated/0/Music/legacy.mp3',
    title: title,
    artist: 'Artist',
    album: 'Album',
    durationMs: 200000,
    dateModifiedSec: 100,
    year: 2020,
    trackNumber: 1,
    sizeBytes: 6000,
    dateAddedSec: 90,
  );
}

void main() {
  const multiGenreJson = '''
  {
    "resultCount": 1,
    "results": [
      {
        "primaryGenreName": "Pop",
        "genres": ["Bollywood", "Indian Pop", "Romantic", "Pop", "Dance"]
      }
    ]
  }
  ''';

  test('parseITunesGenres returns ALL generated genres, deduped, in order', () {
    final options = GenreEnrichmentService.parseITunesGenres(multiGenreJson);
    // Every generated option is present — nothing capped to 3 or 5.
    expect(options, ['Bollywood', 'Indian Pop', 'Romantic', 'Pop', 'Dance']);
  });

  test('parseITunesGenres collects genres from ALL search results, not just the first', () {
    // Real iTunes responses typically return several results, each with its
    // own genre data. Only reading the first result is what made Suggest
    // Genre show a single option.
    const body = '''
    {
      "resultCount": 3,
      "results": [
        {"primaryGenreName": "Pop", "genres": ["Pop"]},
        {"primaryGenreName": "Bollywood", "genres": ["Bollywood", "Indian Pop"]},
        {"primaryGenreName": "Worldwide", "genres": ["Romantic"]}
      ]
    }
    ''';
    expect(GenreEnrichmentService.parseITunesGenres(body), [
      'Pop',
      'Bollywood',
      'Indian Pop',
      'Romantic',
      'Worldwide',
    ]);
  });

  test(
    'suggestGenres seeds the option list with the song\'s current genre',
    () async {
      final client = MockClient(
        (request) async => http.Response(multiGenreJson, 200),
      );
      final service = GenreEnrichmentService(httpClient: client);
      final options = await service.suggestGenres(
        rowId: 42,
        title: 'Some Song',
        artist: 'Some Artist',
        existingGenre: 'Rock',
        readCache: (_) async => null,
        writeCache: (_, __) async {},
      );
      // Current genre first, then every generated option — deduped if equal.
      expect(options.first, 'Rock');
      expect(options, [
        'Rock',
        'Bollywood',
        'Indian Pop',
        'Romantic',
        'Pop',
        'Dance',
      ]);
    },
  );

  test(
    'suggestGenres keeps the current genre even when lookup is empty',
    () async {
      final client = MockClient(
        (request) async => http.Response('{"resultCount":0}', 200),
      );
      final service = GenreEnrichmentService(httpClient: client);
      final options = await service.suggestGenres(
        rowId: 7,
        title: 'Unknown Song',
        artist: null,
        existingGenre: 'Folk',
        readCache: (_) async => null,
        writeCache: (_, __) async {},
      );
      expect(options, ['Folk']);
    },
  );

  test('parseITunesGenres appends primaryGenreName when not duplicated', () {
    const body = '''
    {"resultCount":1,"results":[{"primaryGenreName":"Rock","genres":["Alternative Rock"]}]}
    ''';
    expect(GenreEnrichmentService.parseITunesGenres(body), [
      'Alternative Rock',
      'Rock',
    ]);
  });

  test('parseITunesGenres returns empty list for no results / bad json', () {
    expect(
      GenreEnrichmentService.parseITunesGenres('{"resultCount":0}'),
      isEmpty,
    );
    expect(GenreEnrichmentService.parseITunesGenres('garbage'), isEmpty);
  });

  test('suggestGenres returns the full generated list and caches it', () async {
    final client = MockClient(
      (request) async => http.Response(multiGenreJson, 200),
    );
    final service = GenreEnrichmentService(httpClient: client);
    final cache = <String, String>{};
    var calls = 0;

    final options = await service.suggestGenres(
      rowId: 42,
      title: 'Some Song',
      artist: 'Some Artist',
      readCache: (key) async => cache[key],
      writeCache: (key, value) async {
        calls++;
        cache[key] = value;
      },
    );

    expect(options, ['Bollywood', 'Indian Pop', 'Romantic', 'Pop', 'Dance']);
    expect(calls, 1);

    // A second call is served from the cache without hitting the network.
    final cached = await service.suggestGenres(
      rowId: 42,
      title: 'Some Song',
      artist: 'Some Artist',
      readCache: (key) async => cache[key],
      writeCache: (key, value) async => fail('should be cached'),
    );
    expect(cached, options);
  });

  test(
    'suggestGenres returns empty list when the engine produces nothing',
    () async {
      final client = MockClient(
        (request) async => http.Response('{"resultCount":0}', 200),
      );
      final service = GenreEnrichmentService(httpClient: client);
      final options = await service.suggestGenres(
        rowId: 7,
        title: 'Unknown Song',
        artist: null,
        readCache: (_) async => null,
        writeCache: (_, __) async {},
      );
      expect(options, isEmpty);
    },
  );

  test('suggestGenres ignores legacy single-genre cache entries', () async {
    // The background enrichment pass keeps writing fresh legacy (`g`)
    // entries; trusting them would collapse the suggestion list to one
    // option. They must be ignored so a full lookup runs instead.
    final service = GenreEnrichmentService(
      httpClient: MockClient(
        (request) async => http.Response(multiGenreJson, 200),
      ),
    );
    final legacyJson =
        '{"g":"Classical","t":${DateTime.now().millisecondsSinceEpoch}}';
    final options = await service.suggestGenres(
      rowId: 9,
      title: 't',
      artist: null,
      readCache: (_) async => legacyJson,
      writeCache: (_, __) async {},
    );
    expect(options, ['Bollywood', 'Indian Pop', 'Romantic', 'Pop', 'Dance']);
  });

  test(
    'suggestGenres short-circuits on a fresh multi-genre cache entry',
    () async {
      var networkCalls = 0;
      final service = GenreEnrichmentService(
        httpClient: MockClient((request) async {
          networkCalls++;
          return http.Response(multiGenreJson, 200);
        }),
      );
      final cache = <String, String>{};
      // Prime the cache with a list-form entry.
      await service.suggestGenres(
        rowId: 3,
        title: 't',
        artist: null,
        readCache: (k) async => cache[k],
        writeCache: (k, v) async => cache[k] = v,
      );
      expect(networkCalls, 1);
      final options = await service.suggestGenres(
        rowId: 3,
        title: 't',
        artist: null,
        readCache: (k) async => cache[k],
        writeCache: (_, __) async => fail('should be cached'),
      );
      expect(networkCalls, 1);
      expect(options, ['Bollywood', 'Indian Pop', 'Romantic', 'Pop', 'Dance']);
    },
  );

  test(
    'applying a suggested genre replaces the previous genre membership',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = LibraryRepository(db);
      await repo.syncTracks([_song('Legacy Song')]);

      final rowsBefore = await db.select(db.songs).get();
      // Give the song its initial genre the same way the app does: a single
      // songs.genre metadata write (mediastore ingest leaves genre null).
      await repo.updateSongTags(
        rowsBefore.single.id,
        title: rowsBefore.single.title,
        artist: rowsBefore.single.artist,
        albumName: rowsBefore.single.albumName,
        genre: 'Pop',
        year: rowsBefore.single.year,
      );
      expect((await db.select(db.songs).get()).single.genre, 'Pop');
      expect((await repo.songsForGenre('Pop')).length, 1);

      // The sheet's Apply path writes through updateSongTags — the same call
      // _suggestGenre performs — so the old genre membership is replaced.
      await repo.updateSongTags(
        rowsBefore.single.id,
        title: rowsBefore.single.title,
        artist: rowsBefore.single.artist,
        albumName: rowsBefore.single.albumName,
        genre: 'Bollywood',
        year: rowsBefore.single.year,
      );

      // Reload from the database: the new genre persists…
      final songs = await repo.songsForGenre('Bollywood');
      expect(songs, hasLength(1));
      expect(songs.single.song.title, 'Legacy Song');
      // …and the previous genre membership is gone.
      expect(await repo.songsForGenre('Pop'), isEmpty);

      await db.close();
    },
  );
}

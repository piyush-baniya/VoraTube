import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vora_tube/core/genre/genre_enrichment_service.dart';

void main() {
  const goodJson = '''
  {
    "resultCount": 1,
    "results": [
      {
        "primaryGenreName": "Rock",
        "genres": ["Alternative Rock", "Rock"]
      }
    ]
  }
  ''';

  const emptyJson = '{"resultCount": 0, "results": []}';

  test('parseITunesResponse prefers the first specific genre', () {
    expect(
      GenreEnrichmentService.parseITunesResponse(goodJson),
      'Alternative Rock',
    );
  });

  test('parseITunesResponse returns null for empty results', () {
    expect(GenreEnrichmentService.parseITunesResponse(emptyJson), isNull);
  });

  test('parseITunesResponse returns null for invalid JSON', () {
    expect(GenreEnrichmentService.parseITunesResponse('not json'), isNull);
  });

  test('enrichIfNeeded returns existing local genre without touching cache or network', () async {
    final service = GenreEnrichmentService();
    // An existing genre must short-circuit: no cache read, no network.
    String? cacheRead;
    var networkCalled = false;
    final result = await service.enrichIfNeeded(
      rowId: 1,
      title: 'Song',
      artist: 'Artist',
      existingGenre: 'Jazz',
      readCache: (key) async {
        cacheRead = key;
        return 'something';
      },
      writeCache: (_, __) async {
        fail('writeCache should not be called');
      },
    );
    expect(result, 'Jazz');
    expect(cacheRead, isNull);
    expect(networkCalled, isFalse);
  });

  test('enrichIfNeeded returns fresh cached genre without network', () async {
    final service = GenreEnrichmentService(httpClient: _failClient());
    final now = DateTime.now();
    final cached = '{"g":"Lo-Fi","t":${now.millisecondsSinceEpoch}}';
    var networkCalled = false;
    final result = await service.enrichIfNeeded(
      rowId: 2,
      title: 'Song',
      artist: 'Artist',
      existingGenre: null,
      readCache: (_) async => cached,
      writeCache: (_, __) async {
        networkCalled = true;
      },
    );
    expect(result, 'Lo-Fi');
    expect(networkCalled, isFalse);
  });

  test(
    'enrichIfNeeded fetches online and caches when cache is stale',
    () async {
      var writeCalled = false;
      final service = GenreEnrichmentService(httpClient: _okClient(goodJson));
      final stale = '{"g":"Old","t":0}'; // epoch -> never fresh
      final result = await service.enrichIfNeeded(
        rowId: 3,
        title: 'Song',
        artist: 'Artist',
        existingGenre: null,
        readCache: (_) async => stale,
        writeCache: (_, value) async {
          writeCalled = true;
          expect(value, contains('"g":"Alternative Rock"'));
        },
      );
      expect(result, 'Alternative Rock');
      expect(writeCalled, isTrue);
    },
  );

  test('enrichIfNeeded returns null offline and does not throw', () async {
    final service = GenreEnrichmentService(httpClient: _failClient());
    final result = await service.enrichIfNeeded(
      rowId: 4,
      title: 'Song',
      artist: 'Artist',
      existingGenre: null,
      readCache: (_) async => null,
      writeCache: (_, __) async {},
    );
    expect(result, isNull);
  });

  test('invalidateCache writes a stale sentinel', () async {
    final service = GenreEnrichmentService();
    var capturedKey = '';
    var capturedValue = '';
    await GenreEnrichmentService.invalidateCache(
      rowId: 5,
      writeCache: (key, value) async {
        capturedKey = key;
        capturedValue = value;
      },
    );
    expect(capturedKey, GenreEnrichmentService.cacheKeyForRow(5));
    expect(
      GenreEnrichmentService.isCacheFresh(capturedValue, DateTime.now()),
      isFalse,
    );
  });
}

http.Client _okClient(String body) {
  return MockClient((_) async => http.Response(body, 200));
}

http.Client _failClient() {
  return MockClient((_) async => http.Response('nope', 500));
}

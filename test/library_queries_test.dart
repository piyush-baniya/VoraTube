import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/features/library/data/library_models.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';

IngestTrack _track(
  int id, {
  String title = 'Song',
  String? artist,
  String? album,
  String genre = '',
  int dateAddedSec = 100,
  int durationMs = 60000,
}) {
  // Stable pseudo-IDs derived from entity names so equal names share one
  // album/artist row, mirroring how real MediaStore IDs behave.
  int stable(String s) => s.hashCode.abs() % 900000 + 7;
  final albumMsId = album == null ? null : stable(album);
  final artistMsId = artist == null ? null : stable(artist);
  return IngestTrack(
    source: IngestSource.mediastore,
    mediaStoreId: id,
    albumMediaStoreId: albumMsId,
    artistMediaStoreId: artistMsId,
    albumKey: albumMsId == null ? null : 'ms:$albumMsId',
    artistKey: artistMsId == null ? null : 'ms:$artistMsId',
    contentUri: 'content://media/external/audio/media/$id',
    path: '/storage/x/$id.mp3',
    title: '$title $id',
    artist: artist,
    album: album,
    genre: genre.isEmpty ? null : genre,
    durationMs: durationMs,
    dateModifiedSec: dateAddedSec,
    dateAddedSec: dateAddedSec,
  );
}

void main() {
  late AppDatabase db;
  late LibraryRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = LibraryRepository(db);
  });

  tearDown(() async => db.close());

  group('songsPage', () {
    test('paginates with nextOffset cursor', () async {
      await repository.syncTracks(List.generate(7, (i) => _track(i + 1)));

      final page0 = await repository.songsPage(limit: 5, offset: 0);
      expect(page0.songs, hasLength(5));
      expect(page0.hasMore, isTrue);

      final page1 = await repository.songsPage(
        limit: 5,
        offset: page0.nextOffset,
      );
      expect(page1.songs, hasLength(2));
      expect(page1.hasMore, isFalse);
    });

    test('sorts by recently added desc by default', () async {
      await repository.syncTracks([
        _track(1, dateAddedSec: 10),
        _track(2, dateAddedSec: 30),
        _track(3, dateAddedSec: 20),
      ]);
      final page = await repository.songsPage(limit: 10);
      expect(page.songs.map((t) => t.song.mediaStoreId), [2, 3, 1]);
    });

    test('sorts by title asc', () async {
      await repository.syncTracks([
        _track(1, title: 'Beta'),
        _track(2, title: 'Alpha'),
        _track(3, title: 'Gamma'),
      ]);
      final page = await repository.songsPage(limit: 10, sort: SongSort.title);
      expect(page.songs.map((t) => t.song.title), [
        'Alpha 2',
        'Beta 1',
        'Gamma 3',
      ]);
    });

    test('favorites filter reflects toggles', () async {
      await repository.syncTracks([_track(1), _track(2)]);

      await repository.toggleFavorite(1);
      var favs = await repository.songsPage(limit: 10, favoritesOnly: true);
      expect(favs.songs.map((t) => t.song.mediaStoreId).toSet(), {1});

      await repository.toggleFavorite(2);
      favs = await repository.songsPage(limit: 10, favoritesOnly: true);
      expect(favs.songs.map((t) => t.song.mediaStoreId).toSet(), {1, 2});

      await repository.toggleFavorite(1);
      favs = await repository.songsPage(limit: 10, favoritesOnly: true);
      expect(favs.songs.map((t) => t.song.mediaStoreId).toSet(), {2});
    });
  });

  group('overviews', () {
    setUp(() async {
      await repository.syncTracks([
        _track(1, artist: 'Ari', album: 'One', genre: 'Rock'),
        _track(2, artist: 'Ari', album: 'One', genre: 'Rock'),
        _track(3, artist: 'Bo', album: 'Two', genre: 'Jazz'),
      ]);
    });

    test('albumOverview groups songs per album', () async {
      final albums = await repository.albumOverview();
      expect(albums, hasLength(2));
      final one = albums.firstWhere((a) => a.name == 'One');
      expect(one.songCount, 2);
      expect(one.key, startsWith('ms:'));
    });

    test('artistOverview counts songs per artist', () async {
      final artists = await repository.artistOverview();
      final ari = artists.firstWhere((a) => a.name == 'Ari');
      expect(ari.songCount, 2);
    });

    test('genreOverview derives distinct genres with counts', () async {
      final genres = await repository.genreOverview();
      expect(genres.map((g) => g.genre).toSet(), {'Rock', 'Jazz'});
      expect(genres.firstWhere((g) => g.genre == 'Rock').songCount, 2);
    });
  });

  group('searchAll', () {
    setUp(() async {
      await repository.syncTracks([
        _track(1, title: 'Midnight City', artist: 'M83', album: 'Hurry'),
        _track(2, title: 'Daylight', artist: 'Ari', album: 'Midnight Sun'),
      ]);
      await db
          .into(db.playlists)
          .insert(PlaylistsCompanion.insert(name: 'Chill Mix'));
    });

    test('finds songs by normalized title substring', () async {
      final r = await repository.searchAll('midnight');
      expect(r.songs.map((t) => t.song.title), contains('Midnight City 1'));
      expect(r.albums.map((a) => a.name), contains('Midnight Sun'));
    });

    test('case-insensitive across fields and sections', () async {
      final r = await repository.searchAll('ARI');
      expect(r.artists.map((a) => a.name), contains('Ari'));
      expect(r.songs.map((t) => t.song.artist), contains('Ari'));
    });

    test('matches playlists by name', () async {
      final r = await repository.searchAll('chill');
      expect(r.playlists.map((p) => p.name), contains('Chill Mix'));
    });

    test('empty query returns empty result set without querying', () async {
      final r = await repository.searchAll('   ');
      expect(r.isEmpty, isTrue);
    });
  });
}

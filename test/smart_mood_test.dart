import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/smart_music/data/mood_engine.dart';
import 'package:vora_tube/features/smart_music/data/smart_mix_service.dart';

IngestTrack _track({
  required String title,
  String artist = 'Artist',
  String album = 'Album',
  String? genre,
  int? year,
  int durationMs = 240000,
  int id = 1,
}) {
  return IngestTrack(
    source: IngestSource.mediastore,
    mediaStoreId: id,
    albumMediaStoreId: 100 + id,
    artistMediaStoreId: 200 + id,
    albumKey: 'ms:${100 + id}',
    artistKey: 'ms:${200 + id}',
    contentUri: 'content://media/external/audio/media/$id',
    path: '/storage/emulated/0/Music/song_$id.mp3',
    title: title,
    artist: artist,
    album: album,
    genre: genre,
    year: year,
    durationMs: durationMs,
    dateModifiedSec: 100 + id,
    trackNumber: id,
    sizeBytes: 5000 + id,
    dateAddedSec: 90 + id,
  );
}

MoodEngine _engine() => MoodEngine();

MoodClassification _classify({
  String title = 'Anything',
  String? artist,
  String? album,
  String? genre,
  int? year,
  int durationMs = 240000,
  String? userMood,
}) {
  return _engine().classify(
    title: title,
    artist: artist,
    album: album,
    genre: genre,
    year: year,
    durationMs: durationMs,
    userMood: userMood,
  );
}

void main() {
  group('MoodEngine classification', () {
    test('classifies happy by title keyword', () {
      final c = _classify(title: 'Happy Summer Party Dance');
      expect(c.primaryMood, SongMood.happy);
      expect(c.confidence, greaterThan(0.0));
    });

    test('classifies sad by title keyword', () {
      final c = _classify(title: 'Tears of Heartbreak');
      expect(c.primaryMood, SongMood.sad);
    });

    test('classifies energetic by title keyword', () {
      final c = _classify(title: 'Pumping Workout Energy');
      expect(c.primaryMood, SongMood.energetic);
    });

    test('classifies chill by title keyword', () {
      final c = _classify(title: 'Lo-Fi Chill Study Beats');
      expect(c.primaryMood, SongMood.chill);
    });

    test('classifies romantic by title keyword', () {
      final c = _classify(title: 'Love Forever Sweetheart');
      expect(c.primaryMood, SongMood.romantic);
    });

    test('classifies focus by title keyword', () {
      final c = _classify(title: 'Deep Work Flow Focus');
      expect(c.primaryMood, SongMood.focus);
    });

    test('returns unknown with zero confidence for evidence-less song', () {
      // No keywords, neutral genre, no duration/year nudges.
      final c = _classify(title: 'a b c d e', durationMs: 240000);
      expect(c.primaryMood, SongMood.unknown);
      expect(c.confidence, 0.0);
    });

    test('genre alone influences classification', () {
      final c = _classify(title: 'Untitled', genre: 'Heavy Metal Punk Rock');
      expect(c.primaryMood, SongMood.energetic);
    });

    test('user mood override wins over title evidence', () {
      final c = _classify(
        title: 'Happy Summer Dance',
        genre: 'Metal',
        userMood: 'sad',
      );
      expect(c.primaryMood, SongMood.sad);
      expect(c.confidence, 1.0);
    });

    test('invalid persisted user mood falls back to algorithm', () {
      final c = _classify(title: 'Happy Summer', userMood: 'not-a-real-mood');
      expect(c.primaryMood, SongMood.happy);
    });

    test('exposes full raw scores map for multi-mood membership', () {
      // Short duration (+energetic) and old year (+chill/+sad).
      final c = _classify(
        title: 'Power Gym Run',
        durationMs: 120000,
        year: 1999,
      );
      expect(c.scores[SongMood.energetic], greaterThan(0.0));
    });
  });

  group('SmartMixService mix generation', () {
    late AppDatabase db;
    late LibraryRepository libraryRepo;
    late SmartMixService service;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      libraryRepo = LibraryRepository(db);
      service = SmartMixService(repository: libraryRepo);
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> _rowIdOfTitle(String title) async {
      final page = await libraryRepo.songsPage(limit: 100);
      return page.songs.firstWhere((s) => s.song.title == title).song.id;
    }

    test('generates empty mixes for an empty library', () async {
      await libraryRepo.syncTracks([]);
      final mixes = await service.generateAllMixes(limit: 10);
      expect(mixes, isNotEmpty);
      for (final mix in mixes) {
        expect(mix.songs, isEmpty);
      }
    });

    test('puts a happy song into the Happy Mix', () async {
      await libraryRepo.syncTracks([
        _track(title: 'Happy Summer Party', id: 1),
      ]);
      final mix = await service.generateMix(SmartMixKind.happyMix, limit: 10);
      expect(mix.kind, SmartMixKind.happyMix);
      expect(
        mix.songs.map((s) => s.song.title),
        contains('Happy Summer Party'),
      );
    });

    test('does not force an energetic song into the chill mix', () async {
      await libraryRepo.syncTracks([
        _track(title: 'Heavy Metal Punk Rage', genre: 'Metal', id: 1),
      ]);
      final mix = await service.generateMix(SmartMixKind.chillMix, limit: 10);
      expect(mix.songs, isEmpty);
    });

    test(
      'a song with genuine evidence for two moods appears in both mixes',
      () async {
        // sad: heartbreak+sad+goodbye = 3.0 (primary); romantic: love+forever = 2.0.
        await libraryRepo.syncTracks([
          _track(title: 'Heartbreak Sad Goodbye Love Forever', id: 1),
        ]);
        final sad = await service.generateMix(SmartMixKind.sadMix, limit: 10);
        final romantic = await service.generateMix(
          SmartMixKind.romanticMix,
          limit: 10,
        );
        expect(
          sad.songs.map((s) => s.song.title),
          contains('Heartbreak Sad Goodbye Love Forever'),
        );
        expect(
          romantic.songs.map((s) => s.song.title),
          contains('Heartbreak Sad Goodbye Love Forever'),
        );
      },
    );

    test('honours an explicit user mood override in generated mixes', () async {
      await libraryRepo.syncTracks([
        _track(title: 'Heavy Metal Rage', genre: 'Metal', id: 1),
      ]);
      // Override the automatic energetic classification to snow it.
      await libraryRepo.setSongMood(
        await _rowIdOfTitle('Heavy Metal Rage'),
        'sad',
      );

      final sad = await service.generateMix(SmartMixKind.sadMix, limit: 10);
      expect(sad.songs.map((s) => s.song.title), contains('Heavy Metal Rage'));

      final happy = await service.generateMix(SmartMixKind.happyMix, limit: 10);
      expect(
        happy.songs.map((s) => s.song.title),
        isNot(contains('Heavy Metal Rage')),
      );
    });

    test(
      'picks up a mood assignment on a fresh generation (refresh)',
      () async {
        await libraryRepo.syncTracks([
          _track(title: 'Untitled Generic', id: 1),
        ]);

        final before = await service.generateMix(
          SmartMixKind.focusMix,
          limit: 10,
        );
        expect(before.songs, isEmpty);

        await libraryRepo.setSongMood(
          await _rowIdOfTitle('Untitled Generic'),
          'focus',
        );
        final after = await service.generateMix(
          SmartMixKind.focusMix,
          limit: 10,
        );
        expect(
          after.songs.map((s) => s.song.title),
          contains('Untitled Generic'),
        );
      },
    );

    test(
      'clearing a user mood returns the song to automatic classification',
      () async {
        await libraryRepo.syncTracks([
          _track(title: 'Happy Summer Party', id: 1),
        ]);
        final rowId = await _rowIdOfTitle('Happy Summer Party');

        await libraryRepo.setSongMood(rowId, 'chill');
        final chill = await service.generateMix(
          SmartMixKind.chillMix,
          limit: 10,
        );
        expect(
          chill.songs.map((s) => s.song.title),
          contains('Happy Summer Party'),
        );

        // Clear the manual mood; automatic happy classification applies again.
        await libraryRepo.setSongMood(rowId, '');
        final happy = await service.generateMix(
          SmartMixKind.happyMix,
          limit: 10,
        );
        expect(
          happy.songs.map((s) => s.song.title),
          contains('Happy Summer Party'),
        );
      },
    );
  });
}

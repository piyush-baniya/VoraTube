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

    test('duration alone never produces a mood (no false certainty)', () {
      final short = _classify(title: 'a b c', durationMs: 120000);
      expect(short.primaryMood, SongMood.unknown);
      expect(short.confidence, 0.0);
      expect(short.scores, isEmpty);

      final long = _classify(title: 'a b c', durationMs: 480000);
      expect(long.primaryMood, SongMood.unknown);
      expect(long.confidence, 0.0);
    });

    test('year alone never produces a mood (no false certainty)', () {
      final old = _classify(title: 'a b c', year: 1990, durationMs: 240000);
      expect(old.primaryMood, SongMood.unknown);
      expect(old.confidence, 0.0);

      final recent = _classify(title: 'a b c', year: 2026, durationMs: 240000);
      expect(recent.primaryMood, SongMood.unknown);
    });

    test('supporting nudges cannot outrank clear strong evidence', () {
      // One clear happy signal plus a long-duration chill nudge.
      final c = _classify(title: 'Happy Sunrise', durationMs: 480000);
      expect(c.primaryMood, SongMood.happy);
      expect(c.confidence, inInclusiveRange(0.0, 1.0));
      // The chill nudge stays strictly below the confident happy evidence.
      expect(
        (c.scores[SongMood.chill] ?? 0.0),
        lessThan(c.scores[SongMood.happy] ?? 0.0),
      );
    });

    test('confidence drops when genuine evidence is split across moods', () {
      final c = _classify(title: 'Happy Sad', durationMs: 240000);
      expect(c.primaryMood, isNot(SongMood.unknown));
      expect(c.confidence, lessThan(1.0));
      // The second strongest mood is carried as genuine secondary evidence.
      expect(c.secondaryMoods, isNotEmpty);
      expect(c.scores.containsKey(c.primaryMood), isTrue);
    });

    test('strong genre signal drives classification', () {
      final c = _classify(title: 'Track One', genre: 'Classical Ambient');
      // ambient maps to both chill and focus with equal strength.
      expect(
        c.primaryMood,
        predicate((m) => m == SongMood.chill || m == SongMood.focus),
      );
    });

    test('combines title, artist and album evidence for multi-mood', () {
      final c = _classify(
        title: 'Heartbreak',
        artist: 'Some Artist',
        album: 'Love Letters',
      );
      expect(c.primaryMood, SongMood.sad);
      expect(c.secondaryMoods.containsKey(SongMood.romantic), isTrue);
    });

    test('incomplete metadata still uses whatever signal exists', () {
      final c = _classify(
        title: 'Dance Party',
        artist: null,
        album: null,
        genre: null,
        year: null,
        durationMs: 240000,
      );
      expect(c.primaryMood, isNot(SongMood.unknown));
      expect(c.primaryMood, SongMood.happy);
      expect(c.confidence, greaterThan(0.0));
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

    test('carefully falls back to strongest weak evidence, never to random', () async {
      // Sad-primary, but its long duration gives a genuine (weak) chill signal.
      await libraryRepo.syncTracks([
        _track(title: 'Sad Hearts', durationMs: 480000, id: 1),
      ]);
      final chill = await service.generateMix(SmartMixKind.chillMix, limit: 10);
      expect(chill.songs.map((s) => s.song.title), contains('Sad Hearts'));
    });

    test('does not manufacture songs for a mood with zero evidence', () async {
      await libraryRepo.syncTracks([
        _track(title: 'Sunshine Smile', id: 1),
        _track(title: 'Gentle Rain', id: 2),
      ]);
      final romantic = await service.generateMix(
        SmartMixKind.romanticMix,
        limit: 10,
      );
      expect(romantic.songs, isEmpty);
    });

    test('ranks mood relevance first, then personalization', () async {
      await libraryRepo.syncTracks([
        _track(title: 'Sunshine Smile Party', id: 1), // happy evidence 3
        _track(title: 'Sunshine', id: 2), // happy evidence 1, but favorite
      ]);
      // Make the weaker-happy track a favorite: personalization must not let it
      // outrank the strongly-happy track.
      await libraryRepo.toggleFavorite(2);

      final mix = await service.generateMix(SmartMixKind.happyMix, limit: 10);
      final titles = mix.songs.map((s) => s.song.title).toList();
      expect(
        titles.indexOf('Sunshine Smile Party'),
        lessThan(titles.indexOf('Sunshine')),
      );
    });

    test(
      'mood mixes consider the full library beyond the old 2000-song cap',
      () async {
        // 2100 neutral tracks plus one happy track at the lowest id (the last
        // position in recently-added order, which the old 2000 cap missed).
        final tracks = <IngestTrack>[
          for (var i = 2; i <= 2100; i++) _track(title: 'Track $i', id: i),
        ];
        tracks.insert(0, _track(title: 'Happy Sunshine Party', id: 1));
        await libraryRepo.syncTracks(tracks);

        final mix = await service.generateMix(SmartMixKind.happyMix, limit: 10);
        expect(
          mix.songs.map((s) => s.song.title),
          contains('Happy Sunshine Party'),
        );
      },
    );
  });
}

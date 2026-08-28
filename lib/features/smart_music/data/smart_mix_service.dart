import 'dart:math';

import 'package:meta/meta.dart';

import '../../../core/db/app_database.dart';
import '../../../features/library/data/library_models.dart';
import '../../../features/library/data/library_repository.dart';
import 'mood_engine.dart';

enum SmartMixKind {
  dailyMix,
  favoritesMix,
  chillMix,
  energyMix,
  focusMix,
  happyMix,
  sadMix,
  romanticMix,
  throwbackMix,
  discoverMix,
}

@immutable
class SmartMix {
  const SmartMix({
    required this.kind,
    required this.title,
    required this.description,
    required this.songs,
    required this.generatedAt,
    this.artworkPaths = const [],
  });

  final SmartMixKind kind;
  final String title;
  final String description;
  final List<SongTileData> songs;
  final DateTime generatedAt;
  final List<String> artworkPaths;
}

class SmartMixService {
  SmartMixService({
    required LibraryRepository repository,
    MoodEngine? moodEngine,
  }) : _repository = repository,
       _moodEngine = moodEngine ?? MoodEngine();

  final LibraryRepository _repository;
  final MoodEngine _moodEngine;
  final Random _random = Random();

  Future<SmartMix> generateMix(SmartMixKind kind, {int limit = 50}) async {
    switch (kind) {
      case SmartMixKind.dailyMix:
        return _generateDailyMix(limit);
      case SmartMixKind.favoritesMix:
        return _generateFavoritesMix(limit);
      case SmartMixKind.chillMix:
        return _generateMoodMix(
          SongMood.chill,
          'Chill Mix',
          'Relax and unwind',
          limit,
        );
      case SmartMixKind.energyMix:
        return _generateMoodMix(
          SongMood.energetic,
          'Energy Mix',
          'High energy tracks',
          limit,
        );
      case SmartMixKind.focusMix:
        return _generateMoodMix(
          SongMood.focus,
          'Focus Mix',
          'Music for deep work',
          limit,
        );
      case SmartMixKind.happyMix:
        return _generateMoodMix(
          SongMood.happy,
          'Happy Mix',
          'Feel-good, upbeat tracks',
          limit,
        );
      case SmartMixKind.sadMix:
        return _generateMoodMix(
          SongMood.sad,
          'Sad Mix',
          'Melancholic and reflective',
          limit,
        );
      case SmartMixKind.romanticMix:
        return _generateMoodMix(
          SongMood.romantic,
          'Romantic Mix',
          'Love songs to set the mood',
          limit,
        );
      case SmartMixKind.throwbackMix:
        return _generateThrowbackMix(limit);
      case SmartMixKind.discoverMix:
        return _generateDiscoverMix(limit);
    }
  }

  Future<List<SmartMix>> generateAllMixes({int limit = 50}) async {
    // Load the library and classify every song exactly once, then reuse that
    // single pass to build all six mood mixes. This avoids the previous
    // behaviour of re-fetching and re-classifying the whole library for each
    // mood (which scaled as O(moods × songs)).
    final moodCache = await _loadMoodClassificationCache();

    final nonMoodMixes = await Future.wait([
      _generateDailyMix(limit),
      _generateFavoritesMix(limit),
      _generateThrowbackMix(limit),
      _generateDiscoverMix(limit),
    ]);

    final moodMixes = await Future.wait([
      _generateMoodMix(
        SongMood.happy,
        'Happy Mix',
        'Feel-good, upbeat tracks',
        limit,
        cache: moodCache,
      ),
      _generateMoodMix(
        SongMood.chill,
        'Chill Mix',
        'Relax and unwind',
        limit,
        cache: moodCache,
      ),
      _generateMoodMix(
        SongMood.energetic,
        'Energy Mix',
        'High energy tracks',
        limit,
        cache: moodCache,
      ),
      _generateMoodMix(
        SongMood.sad,
        'Sad Mix',
        'Melancholic and reflective',
        limit,
        cache: moodCache,
      ),
      _generateMoodMix(
        SongMood.romantic,
        'Romantic Mix',
        'Love songs to set the mood',
        limit,
        cache: moodCache,
      ),
      _generateMoodMix(
        SongMood.focus,
        'Focus Mix',
        'Music for deep work',
        limit,
        cache: moodCache,
      ),
    ]);

    return [...nonMoodMixes, ...moodMixes];
  }

  Future<SmartMix> _generateDailyMix(int limit) async {
    final stats = await _repository.currentCounts();
    if (stats.songs == 0) {
      return SmartMix(
        kind: SmartMixKind.dailyMix,
        title: 'Daily Mix',
        description: 'Your daily personalized mix',
        songs: const [],
        generatedAt: DateTime.now(),
      );
    }

    final favorites = await _repository.collectionSongs(
      CollectionKind.favorites,
      limit: limit ~/ 2,
    );
    final recentlyPlayed = await _repository.collectionSongs(
      CollectionKind.recentlyPlayed,
      limit: limit ~/ 3,
    );
    final mostPlayed = await _repository.collectionSongs(
      CollectionKind.mostPlayed,
      limit: limit ~/ 4,
    );

    final combined = <SongTileData>[];
    combined.addAll(favorites);
    combined.addAll(recentlyPlayed);
    combined.addAll(mostPlayed);

    final uniqueSongs = _deduplicateByIdentityKey(combined);
    _shuffleWithVariety(uniqueSongs);

    final selected = uniqueSongs.take(limit).toList();
    final artwork = _extractArtworkPaths(selected);

    return SmartMix(
      kind: SmartMixKind.dailyMix,
      title: 'Daily Mix',
      description: 'Personalized mix based on your listening habits',
      songs: selected,
      generatedAt: DateTime.now(),
      artworkPaths: artwork,
    );
  }

  Future<SmartMix> _generateFavoritesMix(int limit) async {
    final favorites = await _repository.collectionSongs(
      CollectionKind.favorites,
      limit: limit * 2,
    );

    if (favorites.isEmpty) {
      return SmartMix(
        kind: SmartMixKind.favoritesMix,
        title: 'Favorites Mix',
        description: 'Your favorite tracks',
        songs: const [],
        generatedAt: DateTime.now(),
      );
    }

    final shuffled = List<SongTileData>.from(favorites)..shuffle(_random);
    final selected = shuffled.take(limit).toList();
    final artwork = _extractArtworkPaths(selected);

    return SmartMix(
      kind: SmartMixKind.favoritesMix,
      title: 'Favorites Mix',
      description: 'All your favorited tracks, shuffled',
      songs: selected,
      generatedAt: DateTime.now(),
      artworkPaths: artwork,
    );
  }

  Future<SmartMix> _generateMoodMix(
    SongMood mood,
    String title,
    String description,
    int limit, {
    _MoodClassificationCache? cache,
  }) async {
    final kind = _moodMixKind(mood);
    final classificationCache = cache ?? await _loadMoodClassificationCache();
    final allSongs = classificationCache.songs;

    if (allSongs.isEmpty) {
      return SmartMix(
        kind: kind,
        title: title,
        description: description,
        songs: const [],
        generatedAt: DateTime.now(),
      );
    }

    final classifications = classificationCache.classifications;

    final classified = <SongTileData>[
      for (final song in allSongs)
        if (_matchesMood(classifications[song.song.id], mood)) song,
    ];

    if (classified.isEmpty) {
      return SmartMix(
        kind: kind,
        title: title,
        description: description,
        songs: const [],
        generatedAt: DateTime.now(),
      );
    }

    // Order by strength of evidence for this specific mood (stable, no
    // re-classification needed because the score was cached once above).
    final scored = [
      for (final song in classified)
        (
          song: song,
          score:
              (classifications[song.song.id]?.scores[mood] ?? 0.0) +
              ((classifications[song.song.id]?.primaryMood == mood)
                  ? 3.0
                  : 0.0),
        ),
    ]..sort((a, b) => b.score.compareTo(a.score));

    final selected = [for (final s in scored) s.song].take(limit).toList();

    // Interleave the selection so the strongest evidence still shows variety
    // and its own artist doesn't cluster consecutively.
    _shuffleWithVariety(selected);

    final artwork = _extractArtworkPaths(selected);

    return SmartMix(
      kind: kind,
      title: title,
      description: description,
      songs: selected,
      generatedAt: DateTime.now(),
      artworkPaths: artwork,
    );
  }

  /// A song belongs to a mood's mix when that mood is its best fit, or when it
  /// carries genuine, non-trivial evidence for that mood beyond a weak
  /// duration/year nudge (>= 1.5 of keyword/genre evidence).
  bool _matchesMood(MoodClassification? classification, SongMood mood) {
    if (classification == null) return false;
    if (mood == SongMood.unknown) return false;
    if (classification.primaryMood == mood) return true;
    return (classification.scores[mood] ?? 0.0) >= 1.5;
  }

  Future<_MoodClassificationCache> _loadMoodClassificationCache() async {
    final allSongs = await _repository.songsPage(
      limit: 2000,
      favoritesOnly: false,
    );
    final stats = await _dbSongStatsForSongs(allSongs.songs);
    final classifications = <int, MoodClassification>{};
    for (final song in allSongs.songs) {
      classifications[song.song.id] = _moodEngine.classify(
        title: song.song.title,
        artist: song.song.artist,
        album: song.song.albumName,
        genre: song.song.genre,
        year: song.song.year,
        durationMs: song.song.durationMs,
        userMood: stats[song.song.id]?.mood,
      );
    }
    return _MoodClassificationCache(
      songs: allSongs.songs,
      classifications: classifications,
    );
  }

  Future<SmartMix> _generateThrowbackMix(int limit) async {
    final cutoffYear = DateTime.now().year - 10;
    final allSongs = await _repository.songsPage(
      limit: 5000,
      favoritesOnly: false,
    );

    final oldSongs = allSongs.songs.where((s) {
      final year = s.song.year;
      return year != null && year < cutoffYear;
    }).toList();

    if (oldSongs.isEmpty) {
      return SmartMix(
        kind: SmartMixKind.throwbackMix,
        title: 'Throwback Mix',
        description: 'Tracks from 10+ years ago',
        songs: const [],
        generatedAt: DateTime.now(),
      );
    }

    final stats = await _dbSongStatsForSongs(oldSongs);
    oldSongs.sort((a, b) {
      final aStats = stats[a.song.id];
      final bStats = stats[b.song.id];
      final aPlayed = aStats?.playCount ?? 0;
      final bPlayed = bStats?.playCount ?? 0;
      return bPlayed.compareTo(aPlayed);
    });

    final topPlayed = oldSongs.take(limit * 2).toList();
    _shuffleWithVariety(topPlayed);

    final selected = topPlayed.take(limit).toList();
    final artwork = _extractArtworkPaths(selected);

    return SmartMix(
      kind: SmartMixKind.throwbackMix,
      title: 'Throwback Mix',
      description: 'Your most-played tracks from 10+ years ago',
      songs: selected,
      generatedAt: DateTime.now(),
      artworkPaths: artwork,
    );
  }

  Future<SmartMix> _generateDiscoverMix(int limit) async {
    final allSongs = await _repository.songsPage(
      limit: 5000,
      favoritesOnly: false,
    );

    final stats = await _dbSongStatsForSongs(allSongs.songs);
    final unplayed = allSongs.songs.where((s) {
      final stat = stats[s.song.id];
      return stat == null || stat.playCount == 0;
    }).toList();

    final lowPlayed = allSongs.songs.where((s) {
      final stat = stats[s.song.id];
      return stat != null && stat.playCount > 0 && stat.playCount <= 2;
    }).toList();

    final candidates = <SongTileData>[];
    candidates.addAll(unplayed);
    candidates.addAll(lowPlayed);

    if (candidates.isEmpty) {
      return SmartMix(
        kind: SmartMixKind.discoverMix,
        title: 'Discover Mix',
        description: 'Tracks you haven\'t heard much',
        songs: const [],
        generatedAt: DateTime.now(),
      );
    }

    candidates.shuffle(_random);
    final selected = candidates.take(limit).toList();
    final artwork = _extractArtworkPaths(selected);

    return SmartMix(
      kind: SmartMixKind.discoverMix,
      title: 'Discover Mix',
      description: 'Hidden gems from your library',
      songs: selected,
      generatedAt: DateTime.now(),
      artworkPaths: artwork,
    );
  }

  Future<Map<int, SongStat>> _dbSongStatsForSongs(
    List<SongTileData> songs,
  ) async {
    if (songs.isEmpty) return {};
    final songIds = songs.map((s) => s.song.id).toSet();
    return _repository.getSongStatsForSongs(songIds);
  }

  List<SongTileData> _deduplicateByIdentityKey(List<SongTileData> songs) {
    final seen = <String>{};
    final unique = <SongTileData>[];
    for (final song in songs) {
      final key = song.song.source == 'mediastore'
          ? 'ms:${song.song.mediaStoreId}'
          : 'h:${song.song.contentHash}';
      if (seen.add(key)) {
        unique.add(song);
      }
    }
    return unique;
  }

  void _shuffleWithVariety(List<SongTileData> songs) {
    final byArtist = <String, List<SongTileData>>{};
    for (final song in songs) {
      final artist = song.song.artist ?? 'Unknown';
      byArtist.putIfAbsent(artist, () => []).add(song);
    }

    final artists = byArtist.keys.toList()..shuffle(_random);
    final result = <SongTileData>[];
    final artistIndices = <String, int>{};

    while (result.length < songs.length && artists.isNotEmpty) {
      for (final artist in artists) {
        final list = byArtist[artist]!;
        final index = artistIndices[artist] ?? 0;
        if (index < list.length) {
          result.add(list[index]);
          artistIndices[artist] = index + 1;
        }
        if (result.length >= songs.length) break;
      }
      artists.removeWhere(
        (a) => (artistIndices[a] ?? 0) >= (byArtist[a]?.length ?? 0),
      );
    }

    songs.clear();
    songs.addAll(result);
  }

  List<String> _extractArtworkPaths(List<SongTileData> songs) {
    final paths = <String>[];
    for (final song in songs) {
      if (song.artPath != null && song.artPath!.isNotEmpty) {
        paths.add(song.artPath!);
        if (paths.length >= 4) break;
      }
    }
    return paths;
  }

  String mixKindToString(SmartMixKind kind) {
    switch (kind) {
      case SmartMixKind.dailyMix:
        return 'Daily Mix';
      case SmartMixKind.favoritesMix:
        return 'Favorites Mix';
      case SmartMixKind.chillMix:
        return 'Chill Mix';
      case SmartMixKind.energyMix:
        return 'Energy Mix';
      case SmartMixKind.focusMix:
        return 'Focus Mix';
      case SmartMixKind.happyMix:
        return 'Happy Mix';
      case SmartMixKind.sadMix:
        return 'Sad Mix';
      case SmartMixKind.romanticMix:
        return 'Romantic Mix';
      case SmartMixKind.throwbackMix:
        return 'Throwback Mix';
      case SmartMixKind.discoverMix:
        return 'Discover Mix';
    }
  }

  /// The dedicated mix kind for a mood-based recommendation collection.
  SmartMixKind _moodMixKind(SongMood mood) {
    switch (mood) {
      case SongMood.happy:
        return SmartMixKind.happyMix;
      case SongMood.chill:
        return SmartMixKind.chillMix;
      case SongMood.energetic:
        return SmartMixKind.energyMix;
      case SongMood.sad:
        return SmartMixKind.sadMix;
      case SongMood.romantic:
        return SmartMixKind.romanticMix;
      case SongMood.focus:
        return SmartMixKind.focusMix;
      case SongMood.unknown:
        return SmartMixKind.chillMix;
    }
  }
}

/// Immutable cache of the song library plus its per-song mood classification,
/// shared across all mood-mix generations so a song is classified exactly once.
@immutable
class _MoodClassificationCache {
  const _MoodClassificationCache({
    required this.songs,
    required this.classifications,
  });

  final List<SongTileData> songs;
  final Map<int, MoodClassification> classifications;
}

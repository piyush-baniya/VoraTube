import 'dart:math';

import 'package:meta/meta.dart';

import '../../../core/db/app_database.dart';
import '../../../core/player/player_controller.dart';
import '../../../features/library/data/library_models.dart';
import '../../../features/library/data/library_repository.dart';
import 'mood_engine.dart';

enum SmartMixKind {
  dailyMix,
  favoritesMix,
  chillMix,
  energyMix,
  focusMix,
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
      case SmartMixKind.throwbackMix:
        return _generateThrowbackMix(limit);
      case SmartMixKind.discoverMix:
        return _generateDiscoverMix(limit);
    }
  }

  Future<List<SmartMix>> generateAllMixes({int limit = 50}) async {
    final futures = SmartMixKind.values.map(
      (kind) => generateMix(kind, limit: limit),
    );
    return Future.wait(futures);
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
    int limit,
  ) async {
    final allSongs = await _repository.songsPage(
      limit: 2000,
      favoritesOnly: false,
    );

    if (allSongs.songs.isEmpty) {
      return SmartMix(
        kind: SmartMixKind.chillMix,
        title: title,
        description: description,
        songs: const [],
        generatedAt: DateTime.now(),
      );
    }

    final classified = <SongTileData>[];
    for (final song in allSongs.songs) {
      final classification = _moodEngine.classify(
        title: song.song.title,
        artist: song.song.artist,
        album: song.song.albumName,
        genre: song.song.genre,
        year: song.song.year,
        durationMs: song.song.durationMs,
      );
      if (classification.primaryMood == mood &&
          classification.confidence > 0.3) {
        classified.add(song);
      }
    }

    if (classified.isEmpty) {
      return SmartMix(
        kind: SmartMixKind.chillMix,
        title: title,
        description: description,
        songs: const [],
        generatedAt: DateTime.now(),
      );
    }

    classified.sort((a, b) {
      final ca = _moodEngine.classify(
        title: a.song.title,
        artist: a.song.artist,
        album: a.song.albumName,
        genre: a.song.genre,
        year: a.song.year,
        durationMs: a.song.durationMs,
      );
      final cb = _moodEngine.classify(
        title: b.song.title,
        artist: b.song.artist,
        album: b.song.albumName,
        genre: b.song.genre,
        year: b.song.year,
        durationMs: b.song.durationMs,
      );
      return cb.confidence.compareTo(ca.confidence);
    });

    _shuffleWithVariety(classified);

    final selected = classified.take(limit).toList();
    final artwork = _extractArtworkPaths(selected);

    SmartMixKind kind;
    switch (mood) {
      case SongMood.chill:
        kind = SmartMixKind.chillMix;
        break;
      case SongMood.energetic:
        kind = SmartMixKind.energyMix;
        break;
      case SongMood.focus:
        kind = SmartMixKind.focusMix;
        break;
      default:
        kind = SmartMixKind.chillMix;
    }

    return SmartMix(
      kind: kind,
      title: title,
      description: description,
      songs: selected,
      generatedAt: DateTime.now(),
      artworkPaths: artwork,
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
    final stats =
        await (_repository as dynamic)._db.select(
            (_repository as dynamic)._db.songStats,
          )
          ..where((tbl) => tbl.songId.isIn(songIds));
    final rows = await stats.get();
    return {for (final r in rows) r.songId: r};
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
      case SmartMixKind.throwbackMix:
        return 'Throwback Mix';
      case SmartMixKind.discoverMix:
        return 'Discover Mix';
    }
  }
}

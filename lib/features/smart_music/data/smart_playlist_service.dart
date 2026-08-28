import 'package:meta/meta.dart';

import '../../../features/library/data/library_models.dart';
import '../../../features/library/data/library_repository.dart';
import 'mood_engine.dart';

enum SmartPlaylistRuleType {
  genre,
  artist,
  yearRange,
  playCount,
  favorite,
  mood,
  duration,
  dateAdded,
}

@immutable
class SmartPlaylistRule {
  const SmartPlaylistRule({
    required this.type,
    required this.operator,
    required this.value,
  });

  final SmartPlaylistRuleType type;
  final String operator;
  final String value;
}

@immutable
class SmartPlaylistTemplate {
  const SmartPlaylistTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.rules,
    required this.limit,
  });

  final String id;
  final String name;
  final String description;
  final List<SmartPlaylistRule> rules;
  final int limit;
}

class SmartPlaylistService {
  SmartPlaylistService({
    required LibraryRepository repository,
    MoodEngine? moodEngine,
  }) : _repository = repository,
       _moodEngine = moodEngine ?? MoodEngine();

  final LibraryRepository _repository;
  final MoodEngine _moodEngine;

  static const List<SmartPlaylistTemplate> builtInTemplates = [
    SmartPlaylistTemplate(
      id: 'recent_favorites',
      name: 'Recent Favorites',
      description: 'Favorites added in the last 30 days',
      rules: [
        SmartPlaylistRule(
          type: SmartPlaylistRuleType.favorite,
          operator: 'equals',
          value: 'true',
        ),
        SmartPlaylistRule(
          type: SmartPlaylistRuleType.dateAdded,
          operator: 'after',
          value: '30 days ago',
        ),
      ],
      limit: 50,
    ),
    SmartPlaylistTemplate(
      id: 'top_rated',
      name: 'Top Rated',
      description: 'Most played tracks (5+ plays)',
      rules: [
        SmartPlaylistRule(
          type: SmartPlaylistRuleType.playCount,
          operator: '>=',
          value: '5',
        ),
      ],
      limit: 50,
    ),
    SmartPlaylistTemplate(
      id: 'unheard_gems',
      name: 'Unheard Gems',
      description: 'Tracks with 0 plays',
      rules: [
        SmartPlaylistRule(
          type: SmartPlaylistRuleType.playCount,
          operator: 'equals',
          value: '0',
        ),
      ],
      limit: 50,
    ),
    SmartPlaylistTemplate(
      id: 'short_tracks',
      name: 'Short & Sweet',
      description: 'Tracks under 3 minutes',
      rules: [
        SmartPlaylistRule(
          type: SmartPlaylistRuleType.duration,
          operator: '<',
          value: '180000',
        ),
      ],
      limit: 50,
    ),
    SmartPlaylistTemplate(
      id: 'epic_tracks',
      name: 'Epic Tracks',
      description: 'Tracks over 7 minutes',
      rules: [
        SmartPlaylistRule(
          type: SmartPlaylistRuleType.duration,
          operator: '>',
          value: '420000',
        ),
      ],
      limit: 30,
    ),
    SmartPlaylistTemplate(
      id: 'throwback_90s',
      name: '90s Throwback',
      description: 'Tracks from the 1990s',
      rules: [
        SmartPlaylistRule(
          type: SmartPlaylistRuleType.yearRange,
          operator: 'between',
          value: '1990-1999',
        ),
      ],
      limit: 50,
    ),
    SmartPlaylistTemplate(
      id: 'throwback_00s',
      name: '2000s Throwback',
      description: 'Tracks from the 2000s',
      rules: [
        SmartPlaylistRule(
          type: SmartPlaylistRuleType.yearRange,
          operator: 'between',
          value: '2000-2009',
        ),
      ],
      limit: 50,
    ),
    SmartPlaylistTemplate(
      id: 'chill_mood',
      name: 'Chill Vibes',
      description: 'Tracks classified as chill mood',
      rules: [
        SmartPlaylistRule(
          type: SmartPlaylistRuleType.mood,
          operator: 'equals',
          value: 'chill',
        ),
      ],
      limit: 50,
    ),
    SmartPlaylistTemplate(
      id: 'energy_boost',
      name: 'Energy Boost',
      description: 'High energy tracks for workouts',
      rules: [
        SmartPlaylistRule(
          type: SmartPlaylistRuleType.mood,
          operator: 'equals',
          value: 'energetic',
        ),
      ],
      limit: 50,
    ),
    SmartPlaylistTemplate(
      id: 'focus_session',
      name: 'Focus Session',
      description: 'Instrumental and ambient tracks for concentration',
      rules: [
        SmartPlaylistRule(
          type: SmartPlaylistRuleType.mood,
          operator: 'equals',
          value: 'focus',
        ),
      ],
      limit: 50,
    ),
  ];

  Future<List<SongTileData>> generatePlaylist(
    SmartPlaylistTemplate template, {
    int? limit,
  }) async {
    final effectiveLimit = limit ?? template.limit;
    final allSongs = await _repository.songsPage(
      limit: 5000,
      favoritesOnly: false,
    );

    var candidates = allSongs.songs;

    for (final rule in template.rules) {
      candidates = await _applyRule(candidates, rule);
      if (candidates.isEmpty) break;
    }

    candidates.shuffle();
    final selected = candidates.take(effectiveLimit).toList();

    return selected;
  }

  Future<List<SongTileData>> _applyRule(
    List<SongTileData> songs,
    SmartPlaylistRule rule,
  ) async {
    final filtered = <SongTileData>[];
    for (final song in songs) {
      if (await _matchesRule(song, rule)) {
        filtered.add(song);
      }
    }
    return filtered;
  }

  Future<bool> _matchesRule(SongTileData song, SmartPlaylistRule rule) async {
    switch (rule.type) {
      case SmartPlaylistRuleType.genre:
        return _matchGenre(song, rule);
      case SmartPlaylistRuleType.artist:
        return _matchArtist(song, rule);
      case SmartPlaylistRuleType.yearRange:
        return _matchYearRange(song, rule);
      case SmartPlaylistRuleType.playCount:
        return await _matchPlayCount(song, rule);
      case SmartPlaylistRuleType.favorite:
        return await _matchFavorite(song, rule);
      case SmartPlaylistRuleType.mood:
        return _matchMood(song, rule);
      case SmartPlaylistRuleType.duration:
        return _matchDuration(song, rule);
      case SmartPlaylistRuleType.dateAdded:
        return _matchDateAdded(song, rule);
    }
  }

  bool _matchGenre(SongTileData song, SmartPlaylistRule rule) {
    final genre = song.song.genre?.toLowerCase() ?? '';
    final value = rule.value.toLowerCase();
    switch (rule.operator) {
      case 'equals':
        return genre == value;
      case 'contains':
        return genre.contains(value);
      case 'not_equals':
        return genre != value;
      default:
        return false;
    }
  }

  bool _matchArtist(SongTileData song, SmartPlaylistRule rule) {
    final artist = song.song.artist?.toLowerCase() ?? '';
    final value = rule.value.toLowerCase();
    switch (rule.operator) {
      case 'equals':
        return artist == value;
      case 'contains':
        return artist.contains(value);
      case 'not_equals':
        return artist != value;
      default:
        return false;
    }
  }

  bool _matchYearRange(SongTileData song, SmartPlaylistRule rule) {
    final year = song.song.year;
    if (year == null) return false;

    final parts = rule.value.split('-');
    if (parts.length != 2) return false;

    final start = int.tryParse(parts[0]);
    final end = int.tryParse(parts[1]);
    if (start == null || end == null) return false;

    return year >= start && year <= end;
  }

  Future<bool> _matchPlayCount(
    SongTileData song,
    SmartPlaylistRule rule,
  ) async {
    final stats = await _repository.getSongStatsForSongs({song.song.id});
    final playCount = stats[song.song.id]?.playCount ?? 0;

    final value = int.tryParse(rule.value) ?? 0;
    switch (rule.operator) {
      case 'equals':
        return playCount == value;
      case '>=':
        return playCount >= value;
      case '<=':
        return playCount <= value;
      case '>':
        return playCount > value;
      case '<':
        return playCount < value;
      case 'not_equals':
        return playCount != value;
      default:
        return false;
    }
  }

  Future<bool> _matchFavorite(SongTileData song, SmartPlaylistRule rule) async {
    final stats = await _repository.getSongStatsForSongs({song.song.id});
    final isFav = stats[song.song.id]?.isFavorite ?? false;

    return rule.value.toLowerCase() == 'true' ? isFav : !isFav;
  }

  bool _matchMood(SongTileData song, SmartPlaylistRule rule) {
    final classification = _moodEngine.classify(
      title: song.song.title,
      artist: song.song.artist,
      album: song.song.albumName,
      genre: song.song.genre,
      year: song.song.year,
      durationMs: song.song.durationMs,
    );

    final targetMood = _parseMood(rule.value);
    if (targetMood == null) return false;

    return classification.primaryMood == targetMood &&
        classification.confidence > 0.3;
  }

  bool _matchDuration(SongTileData song, SmartPlaylistRule rule) {
    final duration = song.song.durationMs;
    final value = int.tryParse(rule.value) ?? 0;

    switch (rule.operator) {
      case '>=':
        return duration >= value;
      case '<=':
        return duration <= value;
      case '>':
        return duration > value;
      case '<':
        return duration < value;
      case 'equals':
        return duration == value;
      default:
        return false;
    }
  }

  bool _matchDateAdded(SongTileData song, SmartPlaylistRule rule) {
    final dateAdded = song.song.dateAddedSec;
    if (dateAdded == null) return false;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    int cutoff = 0;

    if (rule.value.contains('days ago')) {
      final days =
          int.tryParse(rule.value.replaceAll('days ago', '').trim()) ?? 30;
      cutoff = now - (days * 86400);
    } else if (rule.value.contains('weeks ago')) {
      final weeks =
          int.tryParse(rule.value.replaceAll('weeks ago', '').trim()) ?? 4;
      cutoff = now - (weeks * 7 * 86400);
    } else if (rule.value.contains('months ago')) {
      final months =
          int.tryParse(rule.value.replaceAll('months ago', '').trim()) ?? 1;
      cutoff = now - (months * 30 * 86400);
    }

    switch (rule.operator) {
      case 'after':
        return dateAdded >= cutoff;
      case 'before':
        return dateAdded <= cutoff;
      default:
        return false;
    }
  }

  SongMood? _parseMood(String value) {
    switch (value.toLowerCase()) {
      case 'happy':
        return SongMood.happy;
      case 'chill':
        return SongMood.chill;
      case 'energetic':
        return SongMood.energetic;
      case 'sad':
        return SongMood.sad;
      case 'romantic':
        return SongMood.romantic;
      case 'focus':
        return SongMood.focus;
      default:
        return null;
    }
  }

  Future<List<SongTileData>> generateFromTemplate(
    String templateId, {
    int? limit,
  }) async {
    final template = builtInTemplates.firstWhere(
      (t) => t.id == templateId,
      orElse: () => builtInTemplates.first,
    );
    return generatePlaylist(template, limit: limit);
  }

  List<SmartPlaylistTemplate> getAllTemplates() {
    return builtInTemplates;
  }
}

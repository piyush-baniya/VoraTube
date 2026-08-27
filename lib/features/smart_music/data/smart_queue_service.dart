import 'dart:math';

import '../../../core/player/player_controller.dart';
import 'mood_engine.dart';
import 'smart_mix_service.dart';

class SmartQueueService {
  SmartQueueService({MoodEngine? moodEngine})
    : _moodEngine = moodEngine ?? MoodEngine();

  final MoodEngine _moodEngine;
  final Random _random = Random();

  List<SongRef> reorderForVariety(
    List<SongRef> queue, {
    int maxConsecutiveSameArtist = 2,
    bool preferAlternatingMoods = true,
  }) {
    if (queue.length <= 2) return queue;

    final result = List<SongRef>.from(queue);
    final currentPlaying = result.isNotEmpty ? result.first : null;
    final remaining = currentPlaying != null ? result.sublist(1) : result;

    final groupedByArtist = _groupByArtist(remaining);
    final artists = groupedByArtist.keys.toList()..shuffle(_random);

    final reordered = <SongRef>[];
    final artistIndices = <String, int>{};

    while (reordered.length < remaining.length && artists.isNotEmpty) {
      for (final artist in artists) {
        final list = groupedByArtist[artist]!;
        final index = artistIndices[artist] ?? 0;
        if (index < list.length) {
          if (_wouldExceedConsecutiveLimit(
            reordered,
            artist,
            maxConsecutiveSameArtist,
          )) {
            continue;
          }
          reordered.add(list[index]);
          artistIndices[artist] = index + 1;
        }
        if (reordered.length >= remaining.length) break;
      }
      artists.removeWhere(
        (a) => (artistIndices[a] ?? 0) >= (groupedByArtist[a]?.length ?? 0),
      );
    }

    if (currentPlaying != null) {
      return [currentPlaying, ...reordered];
    }
    return reordered;
  }

  List<SongRef> reorderByMoodFlow(List<SongRef> queue) {
    if (queue.length <= 2) return queue;

    final withMoods = queue.map((song) {
      final mood = _estimateMoodFromSongRef(song);
      return _MoodSongRef(song: song, mood: mood);
    }).toList();

    withMoods.sort((a, b) => _moodDistance(a.mood, b.mood));

    return withMoods.map((m) => m.song).toList();
  }

  List<SongRef> smartShuffle(
    List<SongRef> queue, {
    double artistVarietyWeight = 0.7,
    double moodFlowWeight = 0.3,
  }) {
    if (queue.length <= 3) {
      final shuffled = List<SongRef>.from(queue)..shuffle(_random);
      return shuffled;
    }

    final varietyOrdered = reorderForVariety(queue);
    final moodOrdered = reorderByMoodFlow(varietyOrdered);

    return _blendOrders(varietyOrdered, moodOrdered, artistVarietyWeight);
  }

  List<SongRef> createSmartQueueFromMix(
    SmartMix mix, {
    SongRef? startFrom,
    bool shuffle = true,
  }) {
    final songs = mix.songs
        .map(
          (t) => SongRef(
            identityKey: t.song.source == 'mediastore'
                ? 'ms:${t.song.mediaStoreId}'
                : 'h:${t.song.contentHash}',
            uri: t.song.contentUri,
            title: t.song.title,
            artist: t.song.artist,
            album: t.song.albumName,
            artPath: t.artPath,
            durationMs: t.song.durationMs,
          ),
        )
        .toList();

    if (shuffle) {
      return smartShuffle(songs);
    }

    if (startFrom != null) {
      final startIndex = songs.indexWhere(
        (s) => s.identityKey == startFrom.identityKey,
      );
      if (startIndex >= 0) {
        return [...songs.sublist(startIndex), ...songs.sublist(0, startIndex)];
      }
    }

    return songs;
  }

  List<SongRef> getRecommendations(
    List<SongRef> currentQueue,
    List<SongRef> library, {
    int count = 10,
    bool avoidCurrentArtists = true,
  }) {
    final currentArtists = avoidCurrentArtists
        ? currentQueue
              .map((s) => s.artist?.toLowerCase() ?? '')
              .where((a) => a.isNotEmpty)
              .toSet()
        : <String>{};

    final candidates = library.where((song) {
      if (avoidCurrentArtists) {
        final artist = song.artist?.toLowerCase() ?? '';
        if (currentArtists.contains(artist)) return false;
      }
      return !currentQueue.any((q) => q.identityKey == song.identityKey);
    }).toList();

    candidates.shuffle(_random);

    final recommendations = <SongRef>[];
    final usedArtists = <String>{};

    for (final song in candidates) {
      if (recommendations.length >= count) break;

      final artist = song.artist?.toLowerCase() ?? '';
      if (usedArtists.contains(artist)) continue;

      recommendations.add(song);
      usedArtists.add(artist);
    }

    return recommendations;
  }

  Map<String, List<SongRef>> _groupByArtist(List<SongRef> songs) {
    final groups = <String, List<SongRef>>{};
    for (final song in songs) {
      final artist = song.artist?.toLowerCase() ?? 'unknown';
      groups.putIfAbsent(artist, () => []).add(song);
    }
    return groups;
  }

  bool _wouldExceedConsecutiveLimit(
    List<SongRef> current,
    String artist,
    int maxConsecutive,
  ) {
    if (current.length < maxConsecutive) return false;

    int consecutive = 0;
    for (var i = current.length - 1; i >= 0; i--) {
      final currentArtist = current[i].artist?.toLowerCase() ?? 'unknown';
      if (currentArtist == artist) {
        consecutive++;
      } else {
        break;
      }
    }
    return consecutive >= maxConsecutive;
  }

  SongMood _estimateMoodFromSongRef(SongRef song) {
    return SongMood.unknown;
  }

  int _moodDistance(SongMood a, SongMood b) {
    if (a == b) return 0;
    if (a == SongMood.unknown || b == SongMood.unknown) return 100;

    const moodOrder = [
      SongMood.energetic,
      SongMood.happy,
      SongMood.romantic,
      SongMood.chill,
      SongMood.focus,
      SongMood.sad,
    ];

    final aIndex = moodOrder.indexOf(a);
    final bIndex = moodOrder.indexOf(b);

    if (aIndex == -1 || bIndex == -1) return 50;

    return (aIndex - bIndex).abs();
  }

  List<SongRef> _blendOrders(
    List<SongRef> order1,
    List<SongRef> order2,
    double weight1,
  ) {
    final result = <SongRef>[];
    final used = <String>{};

    final i1 = 0;
    final i2 = 0;
    var idx1 = 0;
    var idx2 = 0;

    while (result.length < order1.length &&
        (idx1 < order1.length || idx2 < order2.length)) {
      final useOrder1 = _random.nextDouble() < weight1;

      if (useOrder1 && idx1 < order1.length) {
        final song = order1[idx1++];
        if (used.add(song.identityKey)) {
          result.add(song);
        }
      } else if (idx2 < order2.length) {
        final song = order2[idx2++];
        if (used.add(song.identityKey)) {
          result.add(song);
        }
      } else if (idx1 < order1.length) {
        final song = order1[idx1++];
        if (used.add(song.identityKey)) {
          result.add(song);
        }
      }
    }

    for (final song in order1) {
      if (result.length >= order1.length) break;
      if (used.add(song.identityKey)) {
        result.add(song);
      }
    }

    return result;
  }
}

class _MoodSongRef {
  const _MoodSongRef({required this.song, required this.mood});

  final SongRef song;
  final SongMood mood;
}

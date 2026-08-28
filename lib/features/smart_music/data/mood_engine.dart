import 'package:meta/meta.dart';

enum SongMood { happy, chill, energetic, sad, romantic, focus, unknown }

@immutable
class MoodClassification {
  const MoodClassification({
    required this.primaryMood,
    required this.confidence,
    required this.secondaryMoods,
    this.scores = const {},
    this.membershipScores = const {},
  });

  final SongMood primaryMood;
  final double confidence;

  /// The same secondary evidence as [secondaryMoods], kept for convenience by
  /// callers that already have the full map. Retained for source compatibility.
  final Map<SongMood, double> secondaryMoods;

  /// Raw positive evidence score per mood (0 for moods with no evidence).
  ///
  /// The value is the sum of a mood's strong (keyword/genre) evidence plus its
  /// supporting (duration/year) nudges. This is the source of truth for
  /// multi-mood membership: a song may belong to more than one mood mix when
  /// several moods carry genuine positive evidence, without forcing it into
  /// every mood. Because duration/year nudges are small, they rarely meet the
  /// [MoodEngine.primaryEvidenceThreshold] and so do not create false secondary
  /// membership on their own.
  final Map<SongMood, double> scores;

  /// Evidence eligible for weak-fallback mix membership: strong (keyword/genre)
  /// evidence plus the duration nudge, but explicitly excluding the weak year
  /// proxy.
  ///
  /// The year nudge is a coarse era heuristic (old releases get a small sad/chill
  /// bump, recent ones a happy/energetic bump) that is useful for ranking but
  /// must not, on its own, place a song into a mood mix — otherwise an old happy
  /// song leaks into the Sad mix purely from its release year. Duration is kept
  /// because track length is a genuine audio signal (long tracks really are more
  /// often chill/focus).
  final Map<SongMood, double> membershipScores;
}

class MoodEngine {
  static const Map<SongMood, List<String>> _moodKeywords = {
    SongMood.happy: [
      'happy',
      'joy',
      'celebrate',
      'party',
      'dance',
      'fun',
      'upbeat',
      'cheerful',
      'sunshine',
      'smile',
      'laugh',
      'good vibes',
      'feel good',
      'summer',
      'beach',
      'festival',
      'groove',
      'swing',
      'bounce',
    ],
    SongMood.chill: [
      'chill',
      'relax',
      'ambient',
      'downtempo',
      'lo-fi',
      'lofi',
      'study',
      'focus',
      'calm',
      'peaceful',
      'serene',
      'mellow',
      'laid back',
      'easy listening',
      'background',
      'atmospheric',
      'dreamy',
      'soft',
      'gentle',
      'slow',
      'quiet',
      'meditation',
      'yoga',
      'sleep',
    ],
    SongMood.energetic: [
      'energetic',
      'energy',
      'power',
      'intense',
      'hard',
      'heavy',
      'fast',
      'driving',
      'pumping',
      'adrenaline',
      'workout',
      'gym',
      'run',
      'sprint',
      'high energy',
      'explosive',
      'aggressive',
      'fierce',
      'strong',
      'powerful',
      'dynamic',
      'upbeat',
      'tempo',
      'bpm',
    ],
    SongMood.sad: [
      'sad',
      'melancholy',
      'depressing',
      'heartbreak',
      'breakup',
      'lonely',
      'tears',
      'cry',
      'grief',
      'loss',
      'pain',
      'sorrow',
      'blue',
      'down',
      'emo',
      'emotional',
      'heartbroken',
      'miss you',
      'gone',
      'farewell',
      'goodbye',
      'regret',
      'nostalgic',
      'memory',
    ],
    SongMood.romantic: [
      'romantic',
      'love',
      'lover',
      'darling',
      'sweetheart',
      'beloved',
      'passion',
      'kiss',
      'embrace',
      'tender',
      'intimate',
      'devotion',
      'anniversary',
      'wedding',
      'marry',
      'forever',
      'eternal',
      'soulmate',
      'crush',
      'adore',
      'cherish',
      'affection',
      'romance',
      'valentine',
    ],
    SongMood.focus: [
      'focus',
      'concentration',
      'study',
      'work',
      'productivity',
      'deep work',
      'flow',
      'mindful',
      'attention',
      'cognitive',
      'mental',
      'brain',
      'instrumental',
      'no lyrics',
      'ambient',
      'minimal',
      'repetitive',
      'steady',
      'consistent',
      'rhythmic',
      'pulsing',
      'drone',
    ],
  };

  static const Map<SongMood, List<String>> _genreMoodMap = {
    SongMood.happy: [
      'pop',
      'dance',
      'disco',
      'funk',
      'soul',
      'reggae',
      'ska',
      'tropical',
      'afrobeat',
      'latin pop',
      'k-pop',
      'j-pop',
    ],
    SongMood.chill: [
      'ambient',
      'downtempo',
      'trip hop',
      'lo-fi',
      'chillhop',
      'chillwave',
      'vaporwave',
      'ambient house',
      'deep house',
      'progressive house',
      'post-rock',
      'shoegaze',
      'dream pop',
      'indie folk',
      'acoustic',
    ],
    SongMood.energetic: [
      'rock',
      'metal',
      'punk',
      'hardcore',
      'grunge',
      'alternative rock',
      'electronic',
      'edm',
      'house',
      'techno',
      'trance',
      'dubstep',
      'drum and bass',
      'hardstyle',
      'psytrance',
      'hip hop',
      'rap',
      'trap',
      'drill',
      'phonk',
    ],
    SongMood.sad: [
      'sadcore',
      'slowcore',
      'doom metal',
      'funeral doom',
      'dark ambient',
      'neoclassical',
      'modern classical',
      'minimal piano',
      'emo',
      'post-punk',
      'gothic rock',
      'deathrock',
      'cold wave',
    ],
    SongMood.romantic: [
      'r&b',
      'soul',
      'quiet storm',
      'slow jam',
      'ballad',
      'love song',
      'bolero',
      'bossa nova',
      'jazz vocal',
      'crooner',
      'chanson',
    ],
    SongMood.focus: [
      'ambient',
      'drone',
      'minimal',
      'modern classical',
      'neoclassical',
      'post-rock',
      'electronic',
      'idm',
      'glitch',
      'lowercase',
      'soundtrack',
      'score',
      'film music',
      'video game music',
    ],
  };

  /// Safely parses a persisted mood name back into a [SongMood].
  static SongMood _safeMood(String name) {
    try {
      return SongMood.values.byName(name);
    } catch (_) {
      return SongMood.unknown;
    }
  }

  /// Threshold below which raw supporting (duration/year) evidence is never
  /// allowed to promote a mood on its own. A mood only becomes the primary mood
  /// (and thus drives mix membership) when it carries genuine keyword/genre
  /// evidence of at least this strength.
  static const double primaryEvidenceThreshold = 1.0;

  MoodClassification classify({
    required String title,
    required String? artist,
    required String? album,
    required String? genre,
    required int? year,
    required int durationMs,
    String? userMood,
  }) {
    // A mood explicitly assigned by the user always takes precedence over the
    // algorithmic guess — this is how user suggestions feed the engine.
    if (userMood != null && userMood.isNotEmpty) {
      final mood = _safeMood(userMood);
      if (mood != SongMood.unknown) {
        return MoodClassification(
          primaryMood: mood,
          confidence: 1.0,
          secondaryMoods: const {},
          scores: const {},
          membershipScores: const {},
        );
      }
    }

    // Strong, meaningful evidence: title/artist/album keywords plus a mapped
    // genre. These alone decide whether a song is classifiable at all.
    final strong = <SongMood, double>{};
    for (final mood in SongMood.values) {
      strong[mood] = 0.0;
    }
    _scoreByKeywords(_normalizeText('$title $artist $album'), strong);
    _scoreByGenre(genre, strong);

    // Supporting evidence: duration/year nudges. These refine ranking and
    // confidence but must NEVER, on their own, promote an evidence-less song to
    // a concrete mood (e.g. a 2:50 track is not automatically "energetic", and
    // a 7-minute track is not automatically "chill").
    if (!strong.values.any((v) => v > 0)) {
      return const MoodClassification(
        primaryMood: SongMood.unknown,
        confidence: 0.0,
        secondaryMoods: {},
        scores: {},
        membershipScores: {},
      );
    }

    final support = <SongMood, double>{};
    final durationSupport = <SongMood, double>{};
    for (final mood in SongMood.values) {
      support[mood] = 0.0;
      durationSupport[mood] = 0.0;
    }
    _scoreByDuration(durationMs, durationSupport);
    _scoreByYear(year, support);
    // The combined support map keeps both nudges for ranking, but the year proxy
    // is tracked separately from the duration nudge so the latter — a genuine
    // audio signal — can still drive weak-fallback membership on its own.
    for (final mood in SongMood.values) {
      support[mood] = (support[mood] ?? 0.0) + (durationSupport[mood] ?? 0.0);
    }

    // The primary mood comes from the strongest genuine (strong) evidence.
    final primaryMood = strong.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
    final primaryStrong = strong[primaryMood]!;
    final totalStrong = strong.values.reduce((a, b) => a + b);
    // Confidence reflects how dominant the primary mood is within the *strong*
    // evidence, so a single weak nudge can never imply false certainty.
    final confidence = totalStrong > 0
        ? (primaryStrong / totalStrong).clamp(0.0, 1.0)
        : 0.0;

    // Secondary moods = other moods with genuine strong evidence, strongest
    // first (bounded to the clearest three). These are what multi-mood mix
    // membership is based on.
    final secondaryMoods = <SongMood, double>{};
    final secondaryEntries =
        strong.entries
            .where((e) => e.key != primaryMood && e.value > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    for (var i = 0; i < secondaryEntries.length && i < 3; i++) {
      secondaryMoods[secondaryEntries[i].key] = secondaryEntries[i].value;
    }

    // Combined raw positive evidence (strong + supporting). Supporting nudges
    // are included here so ranking can break ties, but they are almost always
    // far below [primaryEvidenceThreshold], so they do not create secondary
    // mix membership on their own.
    final scores = <SongMood, double>{};
    // Membership-eligible evidence: strong + duration nudge, but NOT the weak
    // year proxy. This is the map weak-fallback mix membership keys off of, so a
    // song cannot leak into a mood mix from its release year alone.
    final membershipScores = <SongMood, double>{};
    for (final mood in SongMood.values) {
      scores[mood] = (strong[mood] ?? 0.0) + (support[mood] ?? 0.0);
      membershipScores[mood] =
          (strong[mood] ?? 0.0) + (durationSupport[mood] ?? 0.0);
    }

    return MoodClassification(
      primaryMood: primaryMood,
      confidence: confidence,
      secondaryMoods: secondaryMoods,
      scores: Map.unmodifiable(scores),
      membershipScores: Map.unmodifiable(membershipScores),
    );
  }

  void _scoreByKeywords(String text, Map<SongMood, double> scores) {
    for (final entry in _moodKeywords.entries) {
      for (final keyword in entry.value) {
        if (text.contains(keyword)) {
          scores[entry.key] = (scores[entry.key] ?? 0) + 1.0;
        }
      }
    }
  }

  void _scoreByGenre(String? genre, Map<SongMood, double> scores) {
    if (genre == null) return;
    final genreLower = genre.toLowerCase();

    for (final entry in _genreMoodMap.entries) {
      for (final genreKeyword in entry.value) {
        if (genreLower.contains(genreKeyword)) {
          scores[entry.key] = (scores[entry.key] ?? 0) + 2.0;
        }
      }
    }
  }

  void _scoreByDuration(int? durationMs, Map<SongMood, double> scores) {
    if (durationMs == null) return;
    final minutes = durationMs / 60000;

    if (minutes < 3) {
      scores[SongMood.energetic] = (scores[SongMood.energetic] ?? 0) + 0.5;
    } else if (minutes > 6) {
      scores[SongMood.chill] = (scores[SongMood.chill] ?? 0) + 0.5;
      scores[SongMood.focus] = (scores[SongMood.focus] ?? 0) + 0.5;
    }
  }

  void _scoreByYear(int? year, Map<SongMood, double> scores) {
    if (year == null) return;
    final currentYear = DateTime.now().year;

    if (currentYear - year > 20) {
      scores[SongMood.chill] = (scores[SongMood.chill] ?? 0) + 0.3;
      scores[SongMood.sad] = (scores[SongMood.sad] ?? 0) + 0.2;
    } else if (currentYear - year < 3) {
      scores[SongMood.energetic] = (scores[SongMood.energetic] ?? 0) + 0.3;
      scores[SongMood.happy] = (scores[SongMood.happy] ?? 0) + 0.2;
    }
  }

  String _normalizeText(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<SongMood> getAllMoods() {
    return SongMood.values.where((m) => m != SongMood.unknown).toList();
  }

  String moodToString(SongMood mood) {
    switch (mood) {
      case SongMood.happy:
        return 'Happy';
      case SongMood.chill:
        return 'Chill';
      case SongMood.energetic:
        return 'Energetic';
      case SongMood.sad:
        return 'Sad';
      case SongMood.romantic:
        return 'Romantic';
      case SongMood.focus:
        return 'Focus';
      case SongMood.unknown:
        return 'Unknown';
    }
  }

  String moodToEmoji(SongMood mood) {
    switch (mood) {
      case SongMood.happy:
        return '😊';
      case SongMood.chill:
        return '😌';
      case SongMood.energetic:
        return '⚡';
      case SongMood.sad:
        return '😢';
      case SongMood.romantic:
        return '❤️';
      case SongMood.focus:
        return '🎯';
      case SongMood.unknown:
        return '❓';
    }
  }
}

extension SongMoodExtension on SongMood {
  String get label {
    switch (this) {
      case SongMood.happy:
        return 'Happy';
      case SongMood.chill:
        return 'Chill';
      case SongMood.energetic:
        return 'Energetic';
      case SongMood.sad:
        return 'Sad';
      case SongMood.romantic:
        return 'Romantic';
      case SongMood.focus:
        return 'Focus';
      case SongMood.unknown:
        return 'Unknown';
    }
  }

  String get emoji {
    switch (this) {
      case SongMood.happy:
        return '😊';
      case SongMood.chill:
        return '😌';
      case SongMood.energetic:
        return '⚡';
      case SongMood.sad:
        return '😢';
      case SongMood.romantic:
        return '❤️';
      case SongMood.focus:
        return '🎯';
      case SongMood.unknown:
        return '❓';
    }
  }
}

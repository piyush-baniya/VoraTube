import 'dart:convert';

import 'backup_format.dart';

/// Portable song reference stored in a backup.
///
/// Deliberately never trusts a MediaStore/Drift/primary key: those are device-
/// and install-specific. Matching is done against the fields below, strongest
/// signal first.
class BackupSongRef {
  const BackupSongRef({
    required this.index,
    this.identityKey = '',
    this.relativePath = '',
    this.fileName = '',
    this.title = '',
    this.artist = '',
    this.album = '',
    this.durationMs = 0,
    this.sizeBytes = 0,
  });

  /// Position of this track in the payload's `songs` list. Every other domain
  /// refers to songs through it, so no database id is ever persisted.
  final int index;
  final String identityKey;
  final String relativePath;
  final String fileName;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final int sizeBytes;

  Map<String, dynamic> toJson() => {
    'k': identityKey,
    if (relativePath.isNotEmpty) 'p': relativePath,
    if (fileName.isNotEmpty) 'f': fileName,
    if (title.isNotEmpty) 't': title,
    if (artist.isNotEmpty) 'a': artist,
    if (album.isNotEmpty) 'b': album,
    if (durationMs > 0) 'd': durationMs,
    if (sizeBytes > 0) 's': sizeBytes,
  };

  static BackupSongRef? tryFromJson(Object? raw, int index) {
    if (raw is! Map) return null;
    String str(Object? v) => v is String ? v : '';
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    final ref = BackupSongRef(
      index: index,
      identityKey: str(raw['k']),
      relativePath: str(raw['p']),
      fileName: str(raw['f']),
      title: str(raw['t']),
      artist: str(raw['a']),
      album: str(raw['b']),
      durationMs: asInt(raw['d']),
      sizeBytes: asInt(raw['s']),
    );
    final identifiable =
        ref.identityKey.isNotEmpty ||
        ref.relativePath.isNotEmpty ||
        ref.fileName.isNotEmpty ||
        (ref.title.isNotEmpty && ref.artist.isNotEmpty && ref.durationMs > 0);
    return identifiable ? ref : null;
  }
}

class BackupPlaylist {
  const BackupPlaylist({
    required this.name,
    this.pinned = false,
    this.songIndexes = const [],
  });

  final String name;
  final bool pinned;

  /// Playlist order is user state, so song order is preserved. Song indexes
  /// that cannot be remapped are dropped rather than failing the restore.
  final List<int> songIndexes;

  Map<String, dynamic> toJson() => {
    'n': name,
    if (pinned) 'pin': true,
    if (songIndexes.isNotEmpty) 's': songIndexes,
  };

  static BackupPlaylist? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['n'];
    if (name is! String || name.trim().isEmpty) return null;
    final songs = <int>[];
    final rawSongs = raw['s'];
    if (rawSongs is List) {
      for (final entry in rawSongs) {
        if (entry is num && entry.toInt() >= 0) songs.add(entry.toInt());
      }
    }
    return BackupPlaylist(
      name: name,
      pinned: raw['pin'] == true,
      songIndexes: songs,
    );
  }
}

/// Per-song `song_stats` row: favorites, play counts, last play and the
/// user-assigned mood. Stored by song index so it survives reinstalls.
class BackupSongStats {
  const BackupSongStats({
    required this.songIndex,
    this.playCount = 0,
    this.skipCount = 0,
    this.lastPlayedAtMs,
    this.isFavorite = false,
    this.mood = '',
  });

  final int songIndex;
  final int playCount;
  final int skipCount;
  final int? lastPlayedAtMs;
  final bool isFavorite;
  final String mood;

  Map<String, dynamic> toJson() => {
    'i': songIndex,
    if (isFavorite) 'fav': true,
    if (playCount > 0) 'pc': playCount,
    if (skipCount > 0) 'sc': skipCount,
    if (lastPlayedAtMs != null) 'lp': lastPlayedAtMs,
    if (mood.isNotEmpty) 'mo': mood,
  };

  static BackupSongStats? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final index = raw['i'];
    if (index is! num || index.toInt() < 0) return null;
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    return BackupSongStats(
      songIndex: index.toInt(),
      playCount: asInt(raw['pc']),
      skipCount: asInt(raw['sc']),
      lastPlayedAtMs: raw['lp'] is num ? (raw['lp'] as num).toInt() : null,
      isFavorite: raw['fav'] == true,
      mood: raw['mo'] is String ? raw['mo'] as String : '',
    );
  }
}

/// Per-song `song_extras` flags that belong to the user: a hidden song and a
/// song whose tags the user edited by hand. Artwork paths in that same table
/// are app-private cache paths and are never backed up.
class BackupSongExtras {
  const BackupSongExtras({
    required this.songIndex,
    this.isHidden = false,
    this.userEdited = false,
    this.skipCount = 0,
    this.totalMsPlayed = 0,
  });

  final int songIndex;
  final bool isHidden;
  final bool userEdited;
  final int skipCount;
  final int totalMsPlayed;

  Map<String, dynamic> toJson() => {
    'i': songIndex,
    if (isHidden) 'hid': true,
    if (userEdited) 'ue': true,
    'sk': skipCount,
    'ms': totalMsPlayed,
  };

  static BackupSongExtras? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final index = raw['i'];
    if (index is! num || index.toInt() < 0) return null;
    final entry = BackupSongExtras(
      songIndex: index.toInt(),
      isHidden: raw['hid'] == true,
      userEdited: raw['ue'] == true,
      skipCount: raw['sk'] as int? ?? 0,
      totalMsPlayed: raw['ms'] as int? ?? 0,
    );
    return entry;
  }
}

class BackupHistoryEntry {
  const BackupHistoryEntry({
    required this.songIndex,
    required this.playedAtMs,
    this.msPlayed = 0,
  });

  final int songIndex;
  final int playedAtMs;
  final int msPlayed;

  Map<String, dynamic> toJson() => {
    'i': songIndex,
    'at': playedAtMs,
    if (msPlayed > 0) 'm': msPlayed,
  };

  static BackupHistoryEntry? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final index = raw['i'];
    final at = raw['at'];
    if (index is! num || at is! num || index.toInt() < 0) return null;
    return BackupHistoryEntry(
      songIndex: index.toInt(),
      playedAtMs: at.toInt(),
      msPlayed: raw['m'] is num ? (raw['m'] as num).toInt() : 0,
    );
  }
}

/// User-owned lyric text (LRC uploaded, pasted or edited by hand). Disposable
/// network lyric cache is never backed up. Keyed by the song portable identity
/// key so it can be remapped through the matched song.
class BackupLrc {
  const BackupLrc({
    required this.identityKey,
    required this.lrc,
    this.songIndex,
    this.fileName = '',
  });

  final String identityKey;
  final String lrc;
  final int? songIndex;
  final String fileName;

  Map<String, dynamic> toJson() => {
    'k': identityKey,
    'lrc': lrc,
    if (songIndex != null) 'i': songIndex,
    if (fileName.isNotEmpty) 'fn': fileName,
  };

  static BackupLrc? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['k'];
    final lrc = raw['lrc'];
    if (key is! String || key.isEmpty || lrc is! String || lrc.isEmpty) {
      return null;
    }
    final index = raw['i'];
    return BackupLrc(
      identityKey: key,
      lrc: lrc,
      songIndex: index is num && index.toInt() >= 0 ? index.toInt() : null,
      fileName: raw['fn'] is String ? raw['fn'] as String : '',
    );
  }
}

/// A whitelisted settings entry. Keys are filtered at backup time, so
/// install-specific internals are never included.
class BackupKvEntry {
  const BackupKvEntry({required this.key, required this.value});

  final String key;
  final String value;

  Map<String, dynamic> toJson() => {'k': key, 'v': value};

  static BackupKvEntry? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['k'];
    final value = raw['v'];
    if (key is! String || key.isEmpty || value is! String) return null;
    return BackupKvEntry(key: key, value: value);
  }
}

/// The portable user-state payload of a `.vtb` backup.
///
/// Every domain here is user-owned state. Disposable runtime data (artwork and
/// palette caches, thumbnails, temp files, network caches, ads, analytics,
/// logs, build internals) is excluded by construction: it is never serialized.
class BackupPayload {
  BackupPayload({
    required this.createdAt,
    this.appVersion = '',
    this.librarySongCount = 0,
    this.songs = const [],
    this.playlists = const [],
    this.stats = const [],
    this.extras = const [],
    this.history = const [],
    this.lrc = const [],
    this.kv = const [],
    this.songData = const [],
    this.queue,
  });

  /// Filled in from the container header when the file is parsed.
  int formatVersion = backupFormatVersion;
  final DateTime createdAt;
  final String appVersion;
  final int librarySongCount;
  final List<BackupSongRef> songs;
  final List<BackupPlaylist> playlists;
  final List<BackupSongStats> stats;
  final List<BackupSongExtras> extras;
  final List<BackupHistoryEntry> history;
  final List<BackupLrc> lrc;
  final List<BackupKvEntry> kv;
  final List<Map<String, dynamic>> songData;
  final Map<String, dynamic>? queue;

  int get favoritesCount => stats.where((s) => s.isFavorite).length;

  Map<String, dynamic> toJson() => {
    'v': formatVersion,
    'at': createdAt.millisecondsSinceEpoch,
    'app': appVersion,
    'lib': librarySongCount,
    'counts': {
      'songs': songs.length,
      'playlists': playlists.length,
      'favorites': favoritesCount,
      'history': history.length,
    },
    'songs': [for (final s in songs) s.toJson()],
    'playlists': [for (final p in playlists) p.toJson()],
    'stats': [for (final s in stats) s.toJson()],
    'extras': [for (final e in extras) e.toJson()],
    'history': [for (final h in history) h.toJson()],
    'lrc': [for (final l in lrc) l.toJson()],
    'kv': [for (final e in kv) e.toJson()],
    'songData': songData,
    'queue': queue,
  };

  /// Structural parse. Required fields must be present and well typed; a
  /// single unreadable song reference rejects the whole file, because song
  /// indexes position all the other domains and a dropped entry would silently
  /// shift every reference after it.
  static BackupPayload? tryFromJson(Map<String, dynamic> json) {
    validateBackupStructure(json);
    final version = json['v'];
    final at = json['at'];
    if (version is! int || version < 1) return null;
    if (at is! num || at <= 0) return null;
    final rawSongs = json['songs'];
    if (rawSongs is! List) return null;
    final songs = <BackupSongRef>[];
    for (var i = 0; i < rawSongs.length; i++) {
      final ref = BackupSongRef.tryFromJson(rawSongs[i], i);
      if (ref == null) return null;
      songs.add(ref);
    }
    final rawLibraryCount = json['lib'];
    final payload = BackupPayload(
      createdAt: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      appVersion: json['app'] is String ? json['app'] as String : '',
      librarySongCount: rawLibraryCount is num ? rawLibraryCount.toInt() : 0,
      songs: songs,
      playlists: _parseList(json['playlists'], BackupPlaylist.tryFromJson),
      stats: _parseList(json['stats'], BackupSongStats.tryFromJson),
      extras: _parseList(json['extras'], BackupSongExtras.tryFromJson),
      history: _parseList(json['history'], BackupHistoryEntry.tryFromJson),
      lrc: _parseList(json['lrc'], BackupLrc.tryFromJson),
      kv: _parseList(json['kv'], BackupKvEntry.tryFromJson),
      songData: (json['songData'] as List).cast<Map<String, dynamic>>(),
      queue: json['queue'] as Map<String, dynamic>?,
    );
    payload.formatVersion = version;
    return payload;
  }

  /// Referential-integrity pass: song references must exist and text domains
  /// must be non-empty. Runs before any app state is touched.
  void validate() {
    void checkIndexes(String domain, List<int> indexes) {
      for (final index in indexes) {
        if (index < 0 || index >= songs.length) {
          throw BackupFormatException('$domain refers to a missing song');
        }
      }
    }

    for (final playlist in playlists) {
      checkIndexes('A playlist', playlist.songIndexes);
    }
    checkIndexes('Song stats', [for (final s in stats) s.songIndex]);
    checkIndexes('Hidden songs', [for (final e in extras) e.songIndex]);
    checkIndexes('History', [for (final h in history) h.songIndex]);
    checkIndexes('Lyrics', [
      for (final entry in lrc)
        if (entry.songIndex != null) entry.songIndex!,
    ]);
    for (final entry in lrc) {
      if (_hasInvalidControlChars(entry.lrc)) {
        throw BackupFormatException('Lyrics entry is malformed');
      }
    }
    for (final playlist in playlists) {
      if (playlist.name.trim().isEmpty || playlist.name.length > 200) {
        throw BackupFormatException('A playlist name is invalid');
      }
    }
  }

  static List<T> _parseList<T>(Object? raw, T? Function(Object?) parse) {
    if (raw is! List) throw BackupFormatException('Missing backup section');
    final out = <T>[];
    for (final entry in raw) {
      final parsed = parse(entry);
      if (parsed == null) throw BackupFormatException('Invalid backup entry');
      out.add(parsed);
    }
    return out;
  }
}

bool _hasInvalidControlChars(String value) {
  for (final code in value.codeUnits) {
    if (code < 0x20 && code != 0x0A && code != 0x0D && code != 0x09) {
      return true;
    }
  }
  return false;
}

/// Settings keys that this app version writes and therefore captures into a
/// fresh backup. `settings.uiLayout.v1` belongs to a removed customization
/// feature and must never be written again.
const capturedPortableSettingKeys = {
  'settings.audio',
  'settings.library',
  'settings.appearance',
  'settings.equalizer',
  'settings.librarySection',
  'sleepTimer.schedule.v1',
};

/// Every settings key a `.vtb` payload is allowed to carry. Older backups made
/// by app versions that still wrote `settings.uiLayout.v1` must parse cleanly
/// (their obsolete customization data is tolerated on read and dropped on
/// restore — it is never resurrected).
const acceptedPortableSettingKeys = {
  ...capturedPortableSettingKeys,
  'settings.uiLayout.v1',
};

void validateBackupStructure(Map<String, dynamic> json) {
  Never invalid() => throw BackupFormatException('Backup structure is invalid');
  if (json['v'] != 1 ||
      json['at'] is! int ||
      json['at'] <= 0 ||
      json['app'] is! String ||
      json['lib'] is! int ||
      json['lib'] < 0) {
    invalid();
  }
  final schemas = <String, Map<String, String>>{
    'songs': {
      'k': 's',
      'p': 's',
      'f': 's',
      't': 's',
      'a': 's',
      'b': 's',
      'd': 'n',
      's': 'n',
    },
    'playlists': {'n': 's', 'pin': 'b', 's': 'l'},
    'stats': {'i': 'n', 'fav': 'b', 'pc': 'n', 'sc': 'n', 'lp': 'n', 'mo': 's'},
    'extras': {'i': 'n', 'hid': 'b', 'ue': 'b', 'sk': 'n', 'ms': 'n'},
    'history': {'i': 'n', 'at': 'n', 'm': 'n'},
    'lrc': {'k': 's', 'lrc': 's', 'i': 'n', 'fn': 's'},
    'kv': {'k': 's', 'v': 's'},
    'songData': {
      'i': 'n',
      'title': 's',
      'artist': 's',
      'album': 's',
      'genre': 's',
      'year': 'n',
      'track': 'n',
      'disc': 'n',
      'gain': 's',
    },
  };
  for (final section in schemas.entries) {
    final rows = json[section.key];
    if (rows is! List) invalid();
    for (final row in rows) {
      if (row is! Map<String, dynamic>) invalid();
      for (final entry in row.entries) {
        final type = section.value[entry.key];
        final value = entry.value;
        if (type == null ||
            !(switch (type) {
              's' => value is String,
              'b' => value is bool,
              'n' => value is int && value >= 0,
              'l' => value is List && value.every((v) => v is int && v >= 0),
              _ => false,
            })) {
          invalid();
        }
      }
      if (['stats', 'extras', 'history', 'songData'].contains(section.key) &&
          row['i'] is! int) {
        invalid();
      }
    }
  }
  final count = (json['songs'] as List).length;
  for (final section in ['stats', 'extras', 'history', 'songData', 'lrc']) {
    final seen = <int>{};
    for (final row in json[section] as List) {
      final index = row['i'];
      if (index != null &&
          (index >= count || (section != 'history' && !seen.add(index as int)))) {
        invalid();
      }
    }
  }
  final names = <String>{};
  for (final p in json['playlists'] as List) {
    if (p['n'] is! String || !names.add(p['n'] as String)) invalid();
    for (final i in (p['s'] as List? ?? const [])) {
      if (i >= count) invalid();
    }
  }
  final keys = <String>{};
  for (final e in json['kv'] as List) {
    if (!acceptedPortableSettingKeys.contains(e['k']) ||
        e['v'] is! String ||
        !keys.add(e['k'] as String)) {
      invalid();
    }
    validatePortableSetting(e['k'] as String, e['v'] as String);
  }
  final counts = json['counts'];
  if (counts is! Map ||
      counts['songs'] != count ||
      counts['playlists'] != (json['playlists'] as List).length ||
      counts['history'] != (json['history'] as List).length ||
      counts['favorites'] !=
          (json['stats'] as List).where((s) => s['fav'] == true).length) {
    invalid();
  }
  final queue = json['queue'];
  if (queue != null) {
    if (queue is! Map ||
        queue['songs'] is! List ||
        queue['index'] is! int ||
        queue['posMs'] is! int ||
        queue['posMs'] < 0 ||
        queue['shuffle'] is! bool ||
        !['off', 'all', 'one'].contains(queue['repeat'])) {
      invalid();
    }
    for (final i in queue['songs'] as List) {
      if (i is! int || i < 0 || i >= count) invalid();
    }
  }
}

void validatePortableSetting(String key, String value) {
  Never invalid() => throw BackupFormatException('Invalid $key settings');
  if (key == 'settings.librarySection') {
    if (!['songs', 'albums', 'artists', 'genres'].contains(value)) invalid();
    return;
  }
  if (key == 'sleepTimer.schedule.v1' && value.isEmpty) return;
  final data = jsonDecode(value);
  if (data is! Map<String, dynamic>) invalid();
  final types = <String, String>{
    'replayGain': 's',
    'preampDb': 'n',
    'eqEnabled': 'b',
    'eqPreset': 's',
    'eqCustomLevels': 'l',
    'playbackSpeed': 'n',
    'transitionMode': 's',
    'crossfadeSeconds': 'n',
    'audioBalance': 'n',
    'cleanMissingFilesOnStart': 'b',
    'scanOverWiFiOnly': 'b',
    'themeMode': 's',
    'themePreset': 's',
  };
  for (final entry in data.entries) {
    final type = types[entry.key];
    if (type == null) continue;
    final v = entry.value;
    if (!(switch (type) {
      's' => v is String,
      'n' => v is num && v.isFinite,
      'b' => v is bool,
      'l' => v is List && v.every((n) => n is num && n.isFinite),
      _ => false,
    })) {
      invalid();
    }
  }
  if (key == 'settings.equalizer') {
    if (data['v'] != 1 || data['presets'] is! List) invalid();
    final ids = <String>{};
    for (final p in data['presets'] as List) {
      if (p is! Map ||
          p['id'] is! String ||
          p['name'] is! String ||
          !ids.add(p['id'] as String) ||
          p['levels'] is! List ||
          !(p['levels'] as List).every((n) => n is num && n.isFinite)) {
        invalid();
      }
    }
  }
  if (key == 'settings.uiLayout.v1') {
    if (data['v'] is! int ||
        data['v'] < 1 ||
        data['v'] > 3 ||
        data['layouts'] is! List) {
      invalid();
    }
  }
}
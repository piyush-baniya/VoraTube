import 'dart:async';

import 'dart:convert';

import '../../../core/ingest/ingest_service.dart';

enum RepeatMode { off, all, one }

enum PlayerStatus { idle, loading, ready }

enum ReplayGainMode { off, track, album }

/// Computes the clamped target position for a relative seek.
///
/// [position] is the current position, [offset] the signed amount to move, and
/// [duration] the track length (nullable when unknown). The result is clamped
/// to `[0, duration]`. Exposed for unit testing the rewind/forward controls.
Duration clampSeekBy(Duration position, Duration offset, Duration? duration) {
  var target = position + offset;
  if (target < Duration.zero) {
    target = Duration.zero;
  } else if (duration != null && target > duration) {
    target = duration;
  }
  return target;
}

/// Minimal track reference handed to the player.
///
/// Deliberately free of database and platform-engine types so feature code
/// can talk about songs without depending on drift rows or just_audio.
final class SongRef {
  const SongRef({
    required this.identityKey,
    required this.uri,
    required this.title,
    this.artist,
    this.album,
    this.artPath,
    this.durationMs = 0,
    this.replayGain,
  });

  final String identityKey;
  final String uri;
  final String title;
  final String? artist;
  final String? album;
  final String? artPath;
  final int durationMs;
  final ReplayGainInfo? replayGain;
}

/// Coarse playback state. Emitted only when something meaningful changes;
/// high-frequency positions travel separately via [PlayerController.positions].
final class PlayerSnapshot {
  const PlayerSnapshot({
    required this.status,
    required this.isPlaying,
    required this.repeatMode,
    required this.shuffleEnabled,
    required this.queueLength,
    required this.currentIndex,
    required this.durationMs,
    this.current,
  });

  static const PlayerSnapshot initial = PlayerSnapshot(
    status: PlayerStatus.idle,
    isPlaying: false,
    repeatMode: RepeatMode.off,
    shuffleEnabled: false,
    queueLength: 0,
    currentIndex: -1,
    durationMs: 0,
  );

  final PlayerStatus status;
  final bool isPlaying;
  final RepeatMode repeatMode;
  final bool shuffleEnabled;
  final int queueLength;
  final int currentIndex;
  final int durationMs;
  final SongRef? current;

  bool get hasTrack => current != null;

  PlayerSnapshot copyWith({
    PlayerStatus? status,
    bool? isPlaying,
    RepeatMode? repeatMode,
    bool? shuffleEnabled,
    int? queueLength,
    int? currentIndex,
    int? durationMs,
    SongRef? current,
    bool clearCurrent = false,
  }) {
    return PlayerSnapshot(
      status: status ?? this.status,
      isPlaying: isPlaying ?? this.isPlaying,
      repeatMode: repeatMode ?? this.repeatMode,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      queueLength: queueLength ?? this.queueLength,
      currentIndex: currentIndex ?? this.currentIndex,
      durationMs: durationMs ?? this.durationMs,
      current: clearCurrent ? null : (current ?? this.current),
    );
  }
}

/// Persisted playback session used to restore queue and position.
final class QueueSnapshot {
  const QueueSnapshot({
    required this.identityKeys,
    required this.index,
    required this.positionMs,
    required this.shuffleEnabled,
    required this.repeatMode,
  });

  factory QueueSnapshot.fromJson(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const QueueSnapshot.empty();
    }
    if (decoded is! Map<Object?, Object?>) {
      return const QueueSnapshot.empty();
    }
    final map = decoded;
    final version = (map['v'] as num?)?.toInt() ?? 1;
    if (version != 1 || map['keys'] is! List<Object?>) {
      return const QueueSnapshot.empty();
    }
    return QueueSnapshot(
      identityKeys: (map['keys'] as List<Object?>).whereType<String>().toList(),
      index: (map['index'] as num?)?.toInt() ?? 0,
      positionMs: (map['posMs'] as num?)?.toInt() ?? 0,
      shuffleEnabled: map['shuffle'] == true,
      repeatMode: switch (map['repeat']) {
        'all' => RepeatMode.all,
        'one' => RepeatMode.one,
        _ => RepeatMode.off,
      },
    );
  }

  const QueueSnapshot.empty()
    : identityKeys = const [],
      index = -1,
      positionMs = 0,
      shuffleEnabled = false,
      repeatMode = RepeatMode.off;

  final List<String> identityKeys;
  final int index;
  final int positionMs;
  final bool shuffleEnabled;
  final RepeatMode repeatMode;

  bool get isEmpty => identityKeys.isEmpty;

  String toJson() {
    final map = <String, Object?>{
      'v': 1,
      'keys': identityKeys,
      'index': index,
      'posMs': positionMs,
      'shuffle': shuffleEnabled,
      'repeat': switch (repeatMode) {
        RepeatMode.all => 'all',
        RepeatMode.one => 'one',
        RepeatMode.off => 'off',
      },
    };
    return jsonEncode(map);
  }
}

abstract interface class PlayerPersistence {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

/// Fired by the engine whenever a distinct track starts playing.
///
/// The payload is the [SongRef.identityKey] — deliberately storage-free so
/// `core/player` never depends on Drift. The host app adapts keys to
/// whatever persistence it wants (VoraTube records play-count stats).
typedef PlaybackStatsSink = void Function(String identityKey);

/// VoraTube's public playback contract.
///
/// Feature/UI code depends ONLY on this interface — never on just_audio,
/// audio_service or any other engine type. The engine lives entirely
/// behind implementations of this class.
abstract class PlayerController {
  Stream<PlayerSnapshot> get snapshot;

  /// High-frequency position updates. Isolated on purpose: only widgets
  /// that render progress should ever listen.
  Stream<Duration> get positions;

  PlayerSnapshot get current;

  Future<void> playQueue(List<SongRef> songs, {int startIndex});

  Future<void> togglePlay();

  Future<void> pause();

  Future<void> seek(Duration position);

  /// Seeks relative to the current position by [offset], clamped to the
  /// track's [0, duration] range. Used for rewind/forward controls.
  Future<void> seekBy(Duration offset);

  Future<void> next();

  Future<void> previous();

  Future<void> jumpTo(int index);

  Future<void> enqueue(SongRef song);

  /// Inserts [song] immediately after the currently playing track.
  Future<void> playNext(SongRef song);

  Future<void> removeAt(int index);

  Future<void> move(int fromIndex, int toIndex);

  /// Moves a queue item from one position to another (alias for move).
  Future<void> moveQueueItem(int fromIndex, int toIndex);

  /// Clears the entire queue except the currently playing track.
  Future<void> clearQueue();

  Future<void> setShuffle(bool enabled);

  Future<void> setRepeat(RepeatMode mode);

  /// Sets the ReplayGain normalization mode.
  ///
  /// - [ReplayGainMode.off]: No normalization (default)
  /// - [ReplayGainMode.track]: Normalize per track using track gain
  /// - [ReplayGainMode.album]: Normalize per album using album gain
  Future<void> setReplayGainMode(ReplayGainMode mode);

  /// Current ReplayGain normalization mode.
  ReplayGainMode get replayGainMode;

  /// A snapshot copy of the current queue. Safe to call from UI; returns
  /// a new list each time so callers never hold a mutable reference to
  /// the engine's internal list.
  List<SongRef> get currentQueue;

  Future<void> dispose();
}

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

/// Maps a Volume Booster multiplier (1.0..2.0) to a millibel gain value for the
/// platform's loudness enhancer.
///
/// This is the authoritative gain command sent to the native audio backend.
/// It scales linearly from 0 mB at 100% (no change) to +6 dB at 200% (2×
/// linear), and is strictly monotonic so 150% always sits between 100% and
/// 200%. Returning the *engine* gain (not the multiplier) keeps this the real
/// integration boundary: it is the exact number handed to the audio FX chain.
///
/// Equalizer/loudness enhancers cannot represent negative gain, so values
/// below 100% (already not reachable from the UI which is clamped 100–200%)
/// collapse to 0 mB.
int volumeBoostMillibel(double multiplier) {
  final m = multiplier.clamp(1.0, 2.0);
  if (m <= 1.0) return 0;
  final percent = (m - 1.0) * 100.0; // 0..100
  // 6 mB per 1% ⇒ 0 dB @ 100%, +3 dB @ 150%, +6 dB @ 200%.
  return (percent * 6.0).round();
}

/// Maps a Preamp setting (in dB) to the millibel gain it contributes to the
/// platform's loudness enhancer.
///
/// The enhancer only *raises* gain (0 mB = no change); it cannot attenuate. So
/// only positive Preamp values appear here — a +dB Preamp is real gain that
/// the clamped base volume (0..1) would otherwise swallow, and 1 dB = 100 mB.
/// Negative and zero Preamp return 0 mB; they attenuate through the clamped
/// base volume instead (which can go below 1.0), so the full −12..+12 range
/// stays meaningful. Returning engine gain (not the UI number) keeps this the
/// real integration boundary fed to the audio FX chain.
int preampBoostMillibel(double preampDb) {
  final db = preampDb.clamp(0.0, 12.0);
  return (db * 100.0).round(); // 1 dB = 100 mB
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongRef &&
          runtimeType == other.runtimeType &&
          identityKey == other.identityKey &&
          uri == other.uri &&
          title == other.title &&
          artist == other.artist &&
          album == other.album &&
          artPath == other.artPath &&
          durationMs == other.durationMs &&
          replayGain == other.replayGain;

  @override
  int get hashCode => Object.hash(
    identityKey,
    uri,
    title,
    artist,
    album,
    artPath,
    durationMs,
    replayGain,
  );
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
    this.queueRevision = 0,
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

  /// Monotonic counter bumped on every queue mutation (insert, remove, move,
  /// replace). A pure reorder leaves every other field equal, so this is what
  /// lets the engine broadcast a reordered queue past snapshot deduplication.
  final int queueRevision;

  final SongRef? current;

  bool get hasTrack => current != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerSnapshot &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          isPlaying == other.isPlaying &&
          repeatMode == other.repeatMode &&
          shuffleEnabled == other.shuffleEnabled &&
          queueLength == other.queueLength &&
          currentIndex == other.currentIndex &&
          durationMs == other.durationMs &&
          queueRevision == other.queueRevision &&
          current == other.current;

  @override
  int get hashCode => Object.hash(
    status,
    isPlaying,
    repeatMode,
    shuffleEnabled,
    queueLength,
    currentIndex,
    durationMs,
    queueRevision,
    current,
  );

  PlayerSnapshot copyWith({
    PlayerStatus? status,
    bool? isPlaying,
    RepeatMode? repeatMode,
    bool? shuffleEnabled,
    int? queueLength,
    int? currentIndex,
    int? durationMs,
    int? queueRevision,
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
      queueRevision: queueRevision ?? this.queueRevision,
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

/// Fired by the engine for a distinct track-start (the identity key) together
/// with the milliseconds the engine actually heard for that track up to that
/// point. `listenedMs` is 0 on a fresh start; a later call with the same key
/// and a positive value credits the just-ended playback with real listening
/// time. Deliberately storage-free so `core/player` never depends on Drift.
typedef PlaybackStatsSink = void Function(String identityKey, int listenedMs);

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

  /// Stops playback and clears the current track and queue, so the player
  /// returns to a fully idle state (e.g. dismissing the Mini Player).
  Future<void> stop();

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
  ///
  /// [preampDb] (typically -12..+12) offsets the applied gain in dB.
  Future<void> setReplayGainMode(ReplayGainMode mode, {double preampDb = 0});

  /// Current ReplayGain normalization mode.
  ReplayGainMode get replayGainMode;

  /// Sets the player's output multiplier (0.0..1.0 as the engine accepts;
  /// larger values are clamped). Combined with ReplayGain and ducking, this is
  /// the single, authoritative volume control on the engine.
  Future<void> setVolume(double volume);

  /// Sets the output boost multiplier (1.0 = normal, up to 2.0 = boosted).
  ///
  /// This is part of the same authoritative volume chain as [setVolume],
  /// ReplayGain/preamp and ducking. Platform players clamp engine volume to
  /// 0..1, so the boost raises playback toward native maximum faster but cannot
  /// exceed the engine's physical ceiling — it is therefore distortion-safe.
  Future<void> setVolumeBoost(double multiplier);

  /// A snapshot copy of the current queue. Safe to call from UI; returns
  /// a new list each time so callers never hold a mutable reference to
  /// the engine's internal list.
  List<SongRef> get currentQueue;

  Future<void> dispose();
}

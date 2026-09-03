import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/player/player_controller.dart';
import '../../../library/data/library_repository.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../../../library/presentation/providers/library_view_providers.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../../settings/data/settings_models.dart';

/// The app's single [PlayerController], created during bootstrap in
/// `main()` and injected here via override.
final playerProvider = Provider<PlayerController>(
  (ref) => throw UnimplementedError(
    'playerProvider must be overridden at bootstrap',
  ),
);

/// Coarse playback state: play/pause, current track, queue info, modes.
///
/// The engine's snapshot stream is a plain broadcast stream with no replay, so
/// a listener that subscribes *between* two emissions would otherwise wait
/// indefinitely for the next change. Seeding with the controller's synchronous
/// [PlayerController.current] makes a restored queue visible immediately
/// instead of leaving the UI stuck in [AsyncLoading].
final playbackSnapshotProvider = StreamProvider<PlayerSnapshot>((ref) async* {
  final player = ref.watch(playerProvider);
  yield player.current;
  yield* player.snapshot;
});

/// Coarse playback state as a plain, always-available value.
///
/// Prefer this over [playbackSnapshotProvider] in widgets: it collapses the
/// [AsyncValue] wrapper by falling back to [PlayerController.current], so the
/// very first frame after a cold start renders real state rather than a
/// loading placeholder. Watching it never forces a rebuild that watching the
/// stream would not have caused.
final playbackStateProvider = Provider<PlayerSnapshot>((ref) {
  final asyncSnapshot = ref.watch(playbackSnapshotProvider);
  final seeded = asyncSnapshot.valueOrNull;
  if (seeded != null) return seeded;
  return ref.watch(playerProvider).current;
});

/// High-frequency position stream. ONLY progress-rendering widgets should
/// watch this — it fires many times per second by design.
final playbackPositionProvider = StreamProvider<Duration>(
  (ref) => ref.watch(playerProvider).positions,
);

/// Identity of the currently loaded track, or null when nothing is loaded.
///
/// Deliberately narrow. [PlayerSnapshot] has no value equality, so every
/// coarse emission (play/pause, buffering, duration discovery) looks like a
/// change to Riverpod. Consumers that only care about *which* song is loaded
/// — lyrics, metadata lookups — must watch this instead of the whole
/// snapshot, otherwise they re-run their work on every pause and resume.
final currentTrackIdentityProvider = Provider<String?>((ref) {
  final snapshot = ref.watch(playbackStateProvider);
  if (!snapshot.hasTrack) return null;
  return snapshot.current!.identityKey;
});

/// Whether the engine is currently playing, as a plain narrowing of
/// [playbackStateProvider].
///
/// List tiles that only render a playing indicator should watch this (plus
/// [currentTrackIdentityProvider]) instead of the whole snapshot. The snapshot
/// re-emits on buffering, duration discovery, seeks and queue changes — none of
/// which should rebuild every visible song row. Gate on this boolean only, so
/// a play/pause flip is the sole reason those rows rebuild.
final playbackIsPlayingProvider = Provider<bool>((ref) {
  return ref.watch(playbackStateProvider).isPlaying;
});

/// The currently loaded track, or null when nothing is loaded.
///
/// Rebuilds only when the track identity changes, so widgets that render song
/// metadata do not rebuild on every play/pause emission.
final currentTrackProvider = Provider<SongRef?>((ref) {
  final identityKey = ref.watch(currentTrackIdentityProvider);
  if (identityKey == null) return null;
  final current = ref.watch(playbackStateProvider).current;
  if (current == null || current.identityKey != identityKey) return null;
  return current;
});

/// Resolves a SongRef identity key to a database song row ID for
/// operations like toggling favorites from the player UI.
final songRowIdProvider = FutureProvider.family<int?, String>((
  ref,
  identityKey,
) async {
  final repo = ref.watch(libraryRepositoryProvider);
  final map = await repo.rowIdsByIdentityKeys({identityKey});
  return map[identityKey];
});

/// Convenience provider that exposes whether the currently playing song
/// is a favorite, derived from [currentTrackIdentityProvider] +
/// [favoriteIdsProvider].
final currentSongIsFavoriteProvider = Provider<bool>((ref) {
  final key = ref.watch(currentTrackIdentityProvider);
  if (key == null) return false;

  final rowIdAsync = ref.watch(songRowIdProvider(key));
  return rowIdAsync.when(
    data: (rowId) {
      if (rowId == null) return false;
      return ref.watch(favoriteIdsProvider).contains(rowId);
    },
    loading: () => false,
    error: (_, __) => false,
  );
});

final class DriftPlayerPersistence implements PlayerPersistence {
  const DriftPlayerPersistence(this._repository);

  final LibraryRepository _repository;

  static const snapshotKey = 'playback.snapshot.v1';

  @override
  Future<String?> read(String key) => _repository.kvGet(key);

  @override
  Future<void> write(String key, String value) => _repository.kvSet(key, value);
}

/// Buffers engine playback events and flushes them into
/// [LibraryRepository.recordPlayback] (fresh starts) and
/// [LibraryRepository.addPlaybackListenedMs] (real listening time) in batches,
/// so rapid skipping never hammers SQLite with single-row writes.
class PlaybackStatsBuffer {
  PlaybackStatsBuffer(
    this._repository, {
    int flushThreshold = 20,
    Duration flushInterval = const Duration(seconds: 5),
    this.onFlushed,
  }) : _flushThreshold = flushThreshold,
       _flushInterval = flushInterval;

  final LibraryRepository _repository;
  final int _flushThreshold;
  final Duration _flushInterval;

  /// Invoked after a successful write so callers can signal "statistics data
  /// changed" (e.g. bump a refresh tick). Only called when rows were actually
  /// written.
  void Function()? onFlushed;

  final Set<String> _pendingStarts = {};
  final Map<String, int> _pendingHeard = {};
  Timer? _timer;

  int get pendingCount => _pendingStarts.length;

  /// Records one engine event. A `listenedMs == 0` event is a fresh distinct
  /// start (counts a play and appends a history row); a positive `listenedMs`
  /// credits real listening time to that song's most recent history row
  /// without double-counting a new play.
  void add(String identityKey, int listenedMs) {
    if (listenedMs > 0) {
      _pendingHeard.update(
        identityKey,
        (v) => v + listenedMs,
        ifAbsent: () => listenedMs,
      );
    } else if (_pendingStarts.add(identityKey)) {
      // fall through to scheduling below
    } else {
      return;
    }
    if (_pendingStarts.length + _pendingHeard.length >= _flushThreshold) {
      unawaited(flush());
      return;
    }
    _timer ??= Timer(_flushInterval, () => unawaited(flush()));
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_pendingStarts.isEmpty && _pendingHeard.isEmpty) {
      return;
    }
    final starts = Set<String>.from(_pendingStarts);
    final heard = Map<String, int>.from(_pendingHeard);
    _pendingStarts.clear();
    _pendingHeard.clear();
    try {
      final keys = {...starts, ...heard.keys};
      final keyToRow = await _repository.rowIdsByIdentityKeys(keys);
      if (starts.isNotEmpty) {
        final rowIds = [
          for (final k in starts)
            if (keyToRow[k] != null) keyToRow[k]!,
        ];
        if (rowIds.isNotEmpty) {
          await _repository.recordPlayback(rowIds, DateTime.now());
        }
      }
      for (final e in heard.entries) {
        final rowId = keyToRow[e.key];
        if (rowId == null || e.value <= 0) continue;
        await _repository.addPlaybackListenedMs(
          songRowId: rowId,
          listenedMs: e.value,
          at: DateTime.now(),
        );
      }
    } catch (_) {
      // Stats are best-effort; failures must never surface to playback.
      return;
    }
    // Only signal after the whole batch committed, so listeners never run
    // while the writes they would re-read are still in flight.
    onFlushed?.call();
  }
}

Future<void> startPlaybackOfWholeLibrary(WidgetRef ref) async {
  final repository = ref.read(libraryRepositoryProvider);
  final songs = await repository.allSongRefs();
  if (songs.isEmpty) {
    return;
  }
  await ref.read(playerProvider).playQueue(songs);
}

/// Bridges persisted audio settings (ReplayGain mode + preamp) to the player.
///
/// The settings UI saves to [audioSettingsProvider], but nothing was forwarding
/// those values to the player's volume chain — so Preamp appeared to do
/// nothing. This provider watches the settings and pushes every change to the
/// player. It also applies the stored values once at startup so the player and
/// settings agree after a cold launch.
final audioSettingsBridgeProvider = Provider((ref) {
  final player = ref.watch(playerProvider);
  void push(AudioSettings settings) {
    final mode = switch (settings.replayGain) {
      ReplayGainPreference.off => ReplayGainMode.off,
      ReplayGainPreference.track => ReplayGainMode.track,
      ReplayGainPreference.album => ReplayGainMode.album,
    };
    player.setReplayGainMode(mode, preampDb: settings.preampDb);
  }

  ref.listen<AudioSettings>(
    audioSettingsProvider,
    (_, settings) => push(settings),
  );
  // Apply current stored settings immediately so startup state is correct.
  push(ref.read(audioSettingsProvider));
});

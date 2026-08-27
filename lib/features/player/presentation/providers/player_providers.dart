import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/player/player_controller.dart';
import '../../../library/data/library_repository.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../../../library/presentation/providers/library_view_providers.dart';

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

/// Buffers engine track-start events and flushes them into
/// [LibraryRepository.recordPlayback] in batches, so rapid skipping never
/// hammers SQLite with single-row writes.
class PlaybackStatsBuffer {
  PlaybackStatsBuffer(
    this._repository, {
    int flushThreshold = 20,
    Duration flushInterval = const Duration(seconds: 5),
  }) : _flushThreshold = flushThreshold,
       _flushInterval = flushInterval;

  final LibraryRepository _repository;
  final int _flushThreshold;
  final Duration _flushInterval;

  final Set<String> _pending = {};
  Timer? _timer;

  int get pendingCount => _pending.length;

  void add(String identityKey) {
    if (!_pending.add(identityKey)) {
      return;
    }
    if (_pending.length >= _flushThreshold) {
      unawaited(flush());
      return;
    }
    _timer ??= Timer(_flushInterval, () => unawaited(flush()));
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) {
      return;
    }
    final keys = Set<String>.from(_pending);
    _pending.clear();
    try {
      final keyToRow = await _repository.rowIdsByIdentityKeys(keys);
      final rowIds = keyToRow.values.toList(growable: false);
      if (rowIds.isNotEmpty) {
        await _repository.recordPlayback(rowIds, DateTime.now());
      }
    } catch (_) {
      // Stats are best-effort; failures must never surface to playback.
    }
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

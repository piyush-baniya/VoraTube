import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/player/player_controller.dart';
import '../../../library/data/library_repository.dart';
import '../../../library/presentation/providers/library_providers.dart';

/// The app's single [PlayerController], created during bootstrap in
/// `main()` and injected here via override.
final playerProvider = Provider<PlayerController>(
  (ref) => throw UnimplementedError(
    'playerProvider must be overridden at bootstrap',
  ),
);

/// Coarse playback state: play/pause, current track, queue info, modes.
final playbackSnapshotProvider = StreamProvider<PlayerSnapshot>(
  (ref) => ref.watch(playerProvider).snapshot,
);

/// High-frequency position stream. ONLY progress-rendering widgets should
/// watch this — it fires many times per second by design.
final playbackPositionProvider = StreamProvider<Duration>(
  (ref) => ref.watch(playerProvider).positions,
);

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

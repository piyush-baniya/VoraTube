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
/// Emits only on meaningful changes.
final playbackSnapshotProvider = StreamProvider<PlayerSnapshot>(
  (ref) => ref.watch(playerProvider).snapshot,
);

/// High-frequency position stream. ONLY progress-rendering widgets should
/// watch this â€” it fires many times per second by design.
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

Future<void> startPlaybackOfWholeLibrary(WidgetRef ref) async {
  final repository = ref.read(libraryRepositoryProvider);
  final songs = await repository.allSongRefs();
  if (songs.isEmpty) {
    return;
  }
  await ref.read(playerProvider).playQueue(songs);
}

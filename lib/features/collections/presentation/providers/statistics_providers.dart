import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../library/data/library_models.dart';
import '../../../library/data/library_repository.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../../../library/presentation/providers/library_view_providers.dart';

/// Top-played songs by play count (bounded, newest-first tie-break).
final topPlayedSongsProvider = FutureProvider.autoDispose<List<SongTileData>>((
  ref,
) async {
  ref.watch(libraryRefreshTickProvider);
  return ref.watch(libraryRepositoryProvider).topPlayedSongs(limit: 20);
});

/// Most recently played songs (bounded).
final recentlyPlayedSongsProvider =
    FutureProvider.autoDispose<List<SongTileData>>((ref) async {
      ref.watch(libraryRefreshTickProvider);
      return ref
          .watch(libraryRepositoryProvider)
          .recentlyPlayedSongs(limit: 20);
    });

/// Aggregate listening breakdown built from real play-history data.
///
/// Supplies all-time totals, peak day, weekly and yearly reports. Computed
/// once per screen open (from a single DB aggregation) rather than on every
/// frame, so it stays cheap even with large libraries.
final listeningBreakdownProvider =
    FutureProvider.autoDispose<ListeningBreakdown>((ref) async {
      ref.watch(libraryRefreshTickProvider);
      return ref.watch(libraryRepositoryProvider).listeningBreakdown();
    });

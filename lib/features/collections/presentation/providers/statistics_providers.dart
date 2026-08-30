import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../library/data/library_models.dart';
import '../../../library/data/library_repository.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../../../library/presentation/providers/library_view_providers.dart';

/// Top-played songs by play count (max 5, newest-first tie-break).
///
/// Watches both ticks: [libraryRefreshTickProvider] for scans/imports and
/// [statsRefreshTickProvider] for live play-count changes.
final topPlayedSongsProvider = FutureProvider.autoDispose<List<SongTileData>>((
  ref,
) async {
  ref.watch(libraryRefreshTickProvider);
  ref.watch(statsRefreshTickProvider);
  return ref.watch(libraryRepositoryProvider).topPlayedSongs(limit: 5);
});

/// Most recently played songs (max 5, newest history timestamp first).
final recentlyPlayedSongsProvider =
    FutureProvider.autoDispose<List<SongTileData>>((ref) async {
      ref.watch(libraryRefreshTickProvider);
      ref.watch(statsRefreshTickProvider);
      return ref.watch(libraryRepositoryProvider).recentlyPlayedSongs(limit: 5);
    });

/// Aggregate listening breakdown built from real play-history data.
///
/// Supplies all-time totals, peak day, weekly and yearly reports. Computed
/// once per screen open (from a single DB aggregation) rather than on every
/// frame, so it stays cheap even with large libraries.
final listeningBreakdownProvider =
    FutureProvider.autoDispose<ListeningBreakdown>((ref) async {
      ref.watch(libraryRefreshTickProvider);
      ref.watch(statsRefreshTickProvider);
      return ref.watch(libraryRepositoryProvider).listeningBreakdown();
    });

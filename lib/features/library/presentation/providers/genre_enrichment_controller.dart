import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/genre/genre_enrichment_service.dart';
import '../../../../core/genre/genre_providers.dart';
import '../../data/library_repository.dart';
import 'library_providers.dart';
import 'library_view_providers.dart';

/// Number of songs processed by the most recent enrichment run.
class GenreEnrichmentState {
  const GenreEnrichmentState({this.inFlight = false, this.songsUpdated = 0});

  final bool inFlight;
  final int songsUpdated;

  GenreEnrichmentState copyWith({bool? inFlight, int? songsUpdated}) =>
      GenreEnrichmentState(
        inFlight: inFlight ?? this.inFlight,
        songsUpdated: songsUpdated ?? this.songsUpdated,
      );
}

/// Background genre enrichment for songs missing a local genre tag.
///
/// Runs off the UI path (never from `build()`). For each candidate it resolves
/// the genre through the existing [GenreEnrichmentService] — local metadata
/// first, then the KV cache, then a best-effort online lookup — and persists a
/// successful result into `songs.genre` where the existing MoodEngine and Smart
/// Mix generation pick it up. Failed lookups are recorded as suppression
/// sentinels so they are not retried aggressively, and playback/browsing is
/// never blocked. When at least one genre landed, the library tick is bumped so
/// Smart Mood recommendations recompute.
class GenreEnrichmentController extends Notifier<GenreEnrichmentState> {
  @override
  GenreEnrichmentState build() => const GenreEnrichmentState();

  Future<int> enrichPending({int limit = 15}) async {
    if (state.inFlight) return 0;
    final repo = ref.read(libraryRepositoryProvider);
    final service = ref.read(genreEnrichmentServiceProvider);

    state = state.copyWith(inFlight: true);
    var updated = 0;
    try {
      final candidates = await repo.songsMissingGenre(limit: limit);
      for (final song in candidates) {
        final genre = await service.enrichIfNeeded(
          rowId: song.id,
          title: song.title,
          artist: song.artist,
          existingGenre: song.genre,
          readCache: repo.kvGet,
          writeCache: repo.kvSet,
        );
        if (genre != null && genre.isNotEmpty) {
          await repo.setSongGenre(song.id, genre);
          updated++;
        } else {
          // Remember the failed lookup so we don't retry it every launch.
          await GenreEnrichmentService.suppressLookup(
            rowId: song.id,
            writeCache: repo.kvSet,
          );
        }
      }
    } finally {
      state = state.copyWith(
        inFlight: false,
        songsUpdated: state.songsUpdated + updated,
      );
    }
    if (updated > 0) {
      notifyLibraryChanged(ref);
    }
    return updated;
  }
}

/// Exposes [GenreEnrichmentController]. Non-autoDispose so an early background
/// run isn't cancelled when the initiating widget leaves the tree.
final genreEnrichmentControllerProvider =
    NotifierProvider<GenreEnrichmentController, GenreEnrichmentState>(
      GenreEnrichmentController.new,
    );

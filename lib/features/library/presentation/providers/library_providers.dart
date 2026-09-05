import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/ingest/android/android_ingest_service.dart';
import '../../../../core/ingest/artwork/artwork_file_cache.dart';
import '../../../../core/ingest/artwork/local_artwork_store.dart';
import '../../../../core/ingest/ingest_service.dart';
import '../../../../core/ingest/ios/ios_ingest_service.dart';
import '../../../../core/permissions/permission_service.dart';
import '../../data/library_repository.dart';
import '../../data/library_scanner.dart';
import 'genre_enrichment_controller.dart';

import 'library_view_providers.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(driftDatabase(name: 'voratube'));
  ref.onDispose(db.close);
  return db;
});

final permissionServiceProvider = Provider<PermissionService>(
  (ref) => const PermissionService(),
);

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(ref.watch(appDatabaseProvider)),
);

final libraryScannerProvider = Provider<LibraryScanner>(
  (ref) => LibraryScanner(
    ingest: ref.watch(ingestServiceProvider),
    repository: ref.watch(libraryRepositoryProvider),
  ),
);

final ingestServiceProvider = Provider<IngestService>((ref) {
  if (Platform.isIOS) {
    return const IosIngestService();
  }
  return AndroidIngestService();
});

// ---------------------------------------------------------------------------
// Android MediaStore scan state
// ---------------------------------------------------------------------------

sealed class ScanUiState {
  const ScanUiState();
}

final class ScanPermissionNeeded extends ScanUiState {
  const ScanPermissionNeeded({required this.permanentlyDenied});

  final bool permanentlyDenied;
}

final class ScanReady extends ScanUiState {
  const ScanReady();
}

final class ScanRunning extends ScanUiState {
  const ScanRunning({
    required this.phase,
    required this.processedCount,
    required this.addedCount,
    this.totalHint,
  });

  final ScanPhase phase;
  final int processedCount;
  final int addedCount;
  final int? totalHint;
}

final class ScanComplete extends ScanUiState {
  const ScanComplete({required this.summary});

  final ScanSummary summary;
}

final class ScanFailure extends ScanUiState {
  const ScanFailure({required this.message});

  final String message;
}

class ScanController extends Notifier<ScanUiState> {
  @override
  ScanUiState build() => const ScanReady();

  Future<void> refreshPermission() async {
    try {
      final status = await ref.read(permissionServiceProvider).audioStatus();
      _logPermission(status);
      state = switch (status) {
        MediaPermissionStatus.granted => const ScanReady(),
        MediaPermissionStatus.permanentlyDenied => const ScanPermissionNeeded(
          permanentlyDenied: true,
        ),
        MediaPermissionStatus.denied => const ScanPermissionNeeded(
          permanentlyDenied: false,
        ),
      };
    } catch (_) {
      state = const ScanPermissionNeeded(permanentlyDenied: false);
    }
  }

  Future<void> requestPermission() async {
    try {
      final service = ref.read(permissionServiceProvider);
      final status = await service.requestAudio();
      _logPermission(status);
      state = switch (status) {
        MediaPermissionStatus.granted => const ScanReady(),
        MediaPermissionStatus.permanentlyDenied => const ScanPermissionNeeded(
          permanentlyDenied: true,
        ),
        MediaPermissionStatus.denied => const ScanPermissionNeeded(
          permanentlyDenied: false,
        ),
      };
    } catch (_) {
      state = const ScanPermissionNeeded(permanentlyDenied: true);
    }
  }

  Future<void> openSettings() async {
    await ref.read(permissionServiceProvider).openAppSettingsPage();
  }

  Future<void> startScan() async {
    final currentState = state;
    // A failed scan leaves the controller stuck in [ScanFailure]; unless we
    // also allow restarting from there, "Rescan Library" silently does nothing
    // (and shows no snackbar) until the app is restarted.
    if (currentState is! ScanReady &&
        currentState is! ScanComplete &&
        currentState is! ScanFailure) {
      return;
    }
    state = const ScanRunning(
      phase: ScanPhase.reading,
      processedCount: 0,
      addedCount: 0,
    );
    _scanLog('SCAN_STARTED');
    try {
      final summary = await ref
          .read(libraryScannerProvider)
          .scan(
            onProgress: (progress) {
              if (progress.phase == ScanPhase.artwork) {
                // Artwork files are being written right now, and the render
                // path remembers which paths did not exist. Clearing as we go
                // means the refresh below sees the new files instead of the
                // answers cached before they were written.
                //
                // Deliberately not bumping the refresh tick here: that rebuilds
                // the paged song list from page zero, which would throw away
                // accumulated pages under a user who is scrolling.
                ArtworkFileCache.invalidate();
              }
              if (state is ScanRunning) {
                state = ScanRunning(
                  phase: progress.phase,
                  processedCount: progress.processedCount,
                  addedCount: progress.addedCount,
                  totalHint: progress.totalHint,
                );
              }
            },
          );
      debugPrint(
        'VoraTube scan complete: ${summary.totalSongs} songs '
        '(+${summary.addedSongs}, ~${summary.updatedSongs}, '
        '-${summary.removedSongs}), art: ${summary.artworksResolved}/'
        '${summary.artworkAttempts}',
      );
      _scanLog('SCAN_COMPLETE total=${summary.totalSongs}');
      state = ScanComplete(summary: summary);
      // Without this the scan writes rows that nothing ever reads back. Every
      // library, collection and playlist query watches the refresh tick, and
      // until now no code path incremented it — so a completed scan left the
      // UI showing whatever it had loaded first (usually the empty state) until
      // the app was restarted.
      _publishLibraryChange();
      // Trigger non-blocking genre enrichment for the freshly scanned library.
      // Newly added songs likely carried no genre tag; resolving one feeds the
      // Smart Mood engine. This is fire-and-forget — failures/suppressions keep
      // it from retrying aggressively, and it never blocks the UI thread.
      ref.read(genreEnrichmentControllerProvider.notifier).enrichPending();
    } catch (error) {
      debugPrint('VoraTube scan failed: $error');
      _scanLog('SCAN_FAILED exception=$error');
      state = const ScanFailure(
        message:
            'The scan could not be completed. Your existing library is safe.',
      );
      // A scan that fails halfway has still committed the batches it finished,
      // so surface that partial progress rather than hiding it.
      _publishLibraryChange();
    }
  }

  /// Makes committed library writes visible to the read side.
  void _publishLibraryChange() {
    ArtworkFileCache.invalidate();
    notifyLibraryChanged(ref);
  }

  /// Raw permission state at the moment it is read. Lets a developer watching
  /// adb logcat confirm the gate saw the OS permission before a scan ran, and
  /// is a debug-only instrumentation (no-op in release builds).
  void _logPermission(MediaPermissionStatus status) {
    _scanLog('PERMISSION_${status.name.toUpperCase()}');
  }

  /// Scan diagnostic line, emitted only in debug builds.
  ///
  /// These lines are the field instrumentation that distinguishes a successful
  /// but empty scan (SCAN_STARTED → QUERY_SUCCESS count=0 → SCAN_COMPLETE
  /// total=0) from a genuine scan failure (QUERY_FAILED / SCAN_FAILED). They
  /// are silenced in release so they add no noise or cost to shipping builds.
  void _scanLog(String message) {
    if (kDebugMode) {
      debugPrint('VoraTube scan: $message');
    }
  }
}

final scanControllerProvider = NotifierProvider<ScanController, ScanUiState>(
  ScanController.new,
);

// ---------------------------------------------------------------------------
// IOS import state
// ---------------------------------------------------------------------------

sealed class ImportUiState {
  const ImportUiState();
}

final class ImportReady extends ImportUiState {
  const ImportReady();
}

final class Importing extends ImportUiState {
  const Importing({
    required this.phase,
    required this.processedCount,
    required this.totalCount,
    this.importedCount = 0,
    this.skippedCount = 0,
    this.failedCount = 0,
  });

  final ImportPhase phase;
  final int processedCount;
  final int totalCount;
  final int importedCount;
  final int skippedCount;
  final int failedCount;
}

final class ImportComplete extends ImportUiState {
  const ImportComplete({required this.summary});

  final ImportSummary summary;
}

final class ImportFailure extends ImportUiState {
  const ImportFailure({required this.message});

  final String message;
}

class ImportController extends Notifier<ImportUiState> {
  @override
  ImportUiState build() => const ImportReady();

  Future<void> startImport() async {
    final current = state;
    if (current is! ImportReady && current is! ImportComplete) {
      return;
    }

    final ingest = ref.read(ingestServiceProvider);
    final repository = ref.read(libraryRepositoryProvider);

    List<PickedImportFile> files;
    try {
      files = await ingest.pickImportFiles();
    } catch (_) {
      state = const ImportFailure(message: 'The file picker could not open.');
      return;
    }
    if (files.isEmpty) {
      return;
    }

    try {
      final existing = await repository.existingSongIndex();
      final seenKeys = <String>{...existing.keys};
      final failures = <FailedImport>[];
      final pendingTracks = <IngestTrack>[];
      final artworkJobs = <({IngestTrack track, Uint8List bytes})>[];
      var imported = 0;
      var skipped = 0;

      void emit(ImportPhase phase, int processed) {
        state = Importing(
          phase: phase,
          processedCount: processed,
          totalCount: files.length,
          importedCount: imported,
          skippedCount: skipped,
          failedCount: failures.length,
        );
      }

      emit(ImportPhase.copying, 0);

      for (var i = 0; i < files.length; i++) {
        try {
          final processed = await ingest.processImportFile(files[i]);
          final key = processed.track.identityKey;
          if (seenKeys.contains(key)) {
            skipped++;
          } else {
            seenKeys.add(key);
            pendingTracks.add(processed.track);
            imported++;
            final art = processed.artworkBytes;
            if (art != null && art.isNotEmpty) {
              artworkJobs.add((track: processed.track, bytes: art));
            }
          }
        } on ImportProcessingException catch (e) {
          failures.add(
            FailedImport(fileName: files[i].fileName, reason: e.reason),
          );
        } catch (_) {
          failures.add(
            FailedImport(
              fileName: files[i].fileName,
              reason: 'Unexpected error',
            ),
          );
        }
        emit(ImportPhase.copying, i + 1);

        if (pendingTracks.length >= 12) {
          await repository.syncTracks(List.of(pendingTracks));
          pendingTracks.clear();
        }
      }

      if (pendingTracks.isNotEmpty) {
        await repository.syncTracks(List.of(pendingTracks));
        pendingTracks.clear();
      }

      if (artworkJobs.isNotEmpty) {
        emit(ImportPhase.artwork, files.length);
        final root = await ingest.importedFilesRoot();
        if (root != null) {
          final store = LocalArtworkStore('${root.path}/art');
          final savedByKey = <String, SavedArtwork?>{};
          final resolvedByKey = <String, ResolvedArtwork?>{};
          for (final job in artworkJobs) {
            final artKey = LocalArtworkStore.keyFor(job.bytes);
            SavedArtwork? saved;
            if (savedByKey.containsKey(artKey)) {
              saved = savedByKey[artKey];
            } else {
              saved = await store.save(job.bytes);
              savedByKey[artKey] = saved;
            }
            final albumKey = job.track.albumKey;
            if (albumKey != null && albumKey.isNotEmpty) {
              resolvedByKey[albumKey] = saved?.asResolved;
            } else {
              // An import with no album still has cover art worth keeping.
              // Routing it to the song row is the only place it can live, and
              // was previously dropped on the floor.
              final songKey =
                  '${ArtworkTarget.songKeyPrefix}${job.track.identityKey}';
              resolvedByKey[songKey] = saved?.asResolved;
            }
          }
          await repository.attachArtwork(resolvedByKey);
        }
      }

      emit(ImportPhase.finalizing, files.length);

      state = ImportComplete(
        summary: ImportSummary(
          totalSelected: files.length,
          importedSongs: imported,
          skippedDuplicates: skipped,
          failures: List.unmodifiable(failures),
          completedAt: DateTime.now(),
        ),
      );
      _publishLibraryChange();
    } catch (error) {
      debugPrint('VoraTube import failed: $error');
      state = const ImportFailure(
        message:
            'The import could not be completed. Already-imported songs are '
            'safe.',
      );
      // Imports commit in batches of twelve, so a failure part-way through has
      // still added songs the user should be able to see.
      _publishLibraryChange();
    }
  }

  /// Removes database entries whose imported file vanished from VoraTube's
  /// own storage. Returns the number of removed entries.
  Future<int> reconcileMissingFiles() async {
    final ingest = ref.read(ingestServiceProvider);
    final repository = ref.read(libraryRepositoryProvider);

    final root = await ingest.importedFilesRoot();
    if (root == null) {
      return 0;
    }
    final rows = await repository.importedSongsForReconciliation();
    final missing = <int>{
      for (final row in rows)
        if (!File(row.path).existsSync()) row.rowId,
    };
    final removed = await repository.deleteSongsByRowIds(missing);
    if (removed > 0) {
      _publishLibraryChange();
    }
    return removed;
  }

  /// Makes committed library writes visible to the read side.
  void _publishLibraryChange() {
    ArtworkFileCache.invalidate();
    notifyLibraryChanged(ref);
  }
}

final importControllerProvider =
    NotifierProvider<ImportController, ImportUiState>(ImportController.new);

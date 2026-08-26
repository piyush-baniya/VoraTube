import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/ingest/android/android_ingest_service.dart';
import '../../../../core/ingest/ingest_service.dart';
import '../../../../core/permissions/permission_service.dart';
import '../../data/library_repository.dart';
import '../../data/library_scanner.dart';

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
  if (!Platform.isAndroid) {
    throw UnsupportedError('iOS ingestion arrives in Phase 2');
  }
  return AndroidIngestService();
});

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
    if (currentState is! ScanReady && currentState is! ScanComplete) {
      return;
    }
    state = const ScanRunning(
      phase: ScanPhase.reading,
      processedCount: 0,
      addedCount: 0,
    );
    try {
      final summary = await ref
          .read(libraryScannerProvider)
          .scan(
            onProgress: (progress) {
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
      state = ScanComplete(summary: summary);
    } catch (error) {
      debugPrint('VoraTube scan failed: $error');
      state = const ScanFailure(
        message:
            'The scan could not be completed. Your existing library is '
            'safe.',
      );
    }
  }
}

final scanControllerProvider = NotifierProvider<ScanController, ScanUiState>(
  ScanController.new,
);

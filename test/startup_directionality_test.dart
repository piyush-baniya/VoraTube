import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/app/app.dart';
import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/core/permissions/permission_service.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/settings/presentation/providers/settings_providers.dart';

import 'fakes/fake_player.dart';

class _FakeIngestService implements IngestService {
  const _FakeIngestService();

  @override
  IngestCapabilities get capabilities =>
      const IngestCapabilities({IngestCapability.scan});

  @override
  Future<void> prepareScan() async {}

  @override
  Future<List<IngestTrack>> getAudioBatch({
    required int afterId,
    required int limit,
  }) async => [];

  @override
  Future<Map<String, ResolvedArtwork?>> resolveArtwork(
    List<ArtworkTarget> targets,
  ) async => {};

  @override
  Future<List<PickedImportFile>> pickImportFiles() async => [];

  @override
  Future<ProcessedImport> processImportFile(PickedImportFile file) async =>
      throw UnsupportedError('Not supported in test');

  @override
  Future<Directory?> importedFilesRoot() async => null;
}

class _GrantedPermissionService extends PermissionService {
  const _GrantedPermissionService();

  @override
  Future<MediaPermissionStatus> audioStatus() async =>
      MediaPermissionStatus.granted;

  @override
  Future<MediaPermissionStatus> requestAudio() async =>
      MediaPermissionStatus.granted;
}

void main() {
  testWidgets(
    'startup root renders the splash Scaffold with a Material/Directionality '
    'ancestor (regression: no "No Directionality widget found")',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final container = ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          libraryRepositoryProvider.overrideWithValue(LibraryRepository(db)),
          playerProvider.overrideWithValue(FakePlayerController()),
          ingestServiceProvider.overrideWithValue(const _FakeIngestService()),
          permissionServiceProvider.overrideWithValue(
            const _GrantedPermissionService(),
          ),
          storageInfoProvider.overrideWith(
            (ref) => const StorageInfo(
              databaseSizeBytes: 0,
              artworkCacheSizeBytes: 0,
              importedMusicSizeBytes: 0,
              totalSizeBytes: 0,
            ),
          ),
        ],
        child: const VoraTubeApp(),
      );

      // First frame: the SplashGate is showing its splash. This must build a
      // Scaffold inside the MaterialApp (with Directionality/Theme ancestors)
      // rather than throwing "No Directionality widget found".
      await tester.pumpWidget(container);
      await tester.pump(const Duration(milliseconds: 16));

      expect(tester.takeException(), isNull);
      expect(find.byType(Scaffold), findsWidgets);
      expect(find.text('VoraTube'), findsOneWidget);

      // Let the splash timer (800ms) fire so the shell below is reachable.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    },
  );
}

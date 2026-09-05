import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/app/app.dart';
import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/core/permissions/permission_service.dart';
import 'package:vora_tube/features/library/data/library_models.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/library/presentation/providers/library_view_providers.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/settings/data/settings_models.dart';
import 'package:vora_tube/features/settings/presentation/providers/settings_providers.dart';

import 'fakes/fake_player.dart';

class _GrantedPermissionService extends PermissionService {
  const _GrantedPermissionService();

  @override
  Future<MediaPermissionStatus> audioStatus() async =>
      MediaPermissionStatus.granted;

  @override
  Future<MediaPermissionStatus> requestAudio() async =>
      MediaPermissionStatus.granted;
}

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
Future<void> _buildApp(
  WidgetTester tester, {
  required AppDatabase db,
}) async {
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

  final size = tester.view.physicalSize;
  final dpr = tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 2400);

  await tester.pumpWidget(container);
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle(const Duration(seconds: 5));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  addTearDown(() {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = dpr;
  });
}

Future<void> _tapTab(
  WidgetTester tester,
  IconData outlined,
  IconData selected,
) {
  return tester.tap(
    find.byWidgetPredicate(
      (w) => w is Icon && (w.icon == outlined || w.icon == selected),
    ),
  );
}

void main() {
  group('Library section persistence', () {
    test('controller persists the section to KV and restores it', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LibraryRepository(db);

      final controller = LibrarySectionController(repo);
      addTearDown(controller.dispose);
      expect(controller.state, LibrarySection.songs);

      controller.state = LibrarySection.albums;
      // Let the fire-and-forget KV write flush.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await repo.kvGet(SettingsKeys.librarySection), 'albums');

      // A fresh controller over the same storage restores Albums.
      final restored = LibrarySectionController(repo);
      addTearDown(restored.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(restored.state, LibrarySection.albums);
    });

    testWidgets('selection survives an in-session tab switch',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _buildApp(tester, db: db);

      await _tapTab(tester, Icons.library_music_outlined, Icons.library_music);
      await tester.pumpAndSettle();

      // Switch the Library section to Albums (empty DB shows its empty state).
      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();
      expect(find.text('No albums yet'), findsOneWidget);

      // Leave to Home, then return to Library.
      await _tapTab(tester, Icons.home_outlined, Icons.home);
      await tester.pumpAndSettle();
      await _tapTab(tester, Icons.library_music_outlined, Icons.library_music);
      await tester.pumpAndSettle();

      // Albums must stay active — not reset to Songs.
      expect(find.text('No albums yet'), findsOneWidget);
      expect(find.text('No songs yet'), findsNothing);
    });
  });

  group('Search field persistence', () {
    testWidgets('query survives a tab switch away and back', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _buildApp(tester, db: db);

      await _tapTab(tester, Icons.search_outlined, Icons.search);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pumpAndSettle();

      await _tapTab(tester, Icons.library_music_outlined, Icons.library_music);
      await tester.pumpAndSettle();
      await _tapTab(tester, Icons.search_outlined, Icons.search);
      await tester.pumpAndSettle();

      expect(
        find.text('hello'),
        findsWidgets,
        reason: 'Search field must keep its query after switching tabs',
      );
    });

    testWidgets('query survives re-tapping the active search tab',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _buildApp(tester, db: db);

      await _tapTab(tester, Icons.search_outlined, Icons.search);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pumpAndSettle();

      // Re-tap the already-active Search tab.
      await _tapTab(tester, Icons.search_outlined, Icons.search);
      await tester.pumpAndSettle();

      expect(
        find.text('hello'),
        findsWidgets,
        reason: 'Re-tapping the active Search tab must not clear the query',
      );
    });
  });
}
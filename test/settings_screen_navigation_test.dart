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
import 'package:vora_tube/features/settings/presentation/screens/faq_screen.dart';
import 'package:vora_tube/features/settings/presentation/screens/privacy_policy_screen.dart';
import 'package:vora_tube/features/settings/presentation/screens/terms_screen.dart';

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

Future<void> _buildApp(WidgetTester tester) async {
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

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Settings shows support and legal entries, no standalone Privacy',
      (tester) async {
    await _buildApp(tester);
    await _openSettings(tester);

    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms of Use'), findsOneWidget);
    expect(find.text('FAQ'), findsOneWidget);
    expect(find.text('Feedback'), findsOneWidget);

    expect(
      find.text('Privacy'),
      findsNothing,
      reason: 'The redundant standalone "Privacy" entry must be removed',
    );
  });

  testWidgets('tapping Privacy Policy opens the in-app privacy policy screen',
      (tester) async {
    await _buildApp(tester);
    await _openSettings(tester);

    await tester.tap(find.text('Privacy Policy').first);
    await tester.pumpAndSettle();

    expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
    expect(find.textContaining('The short version'), findsOneWidget);
  });

  testWidgets('tapping Terms of Use opens the in-app terms screen',
      (tester) async {
    await _buildApp(tester);
    await _openSettings(tester);

    await tester.tap(find.text('Terms of Use').first);
    await tester.pumpAndSettle();

    expect(find.byType(TermsScreen), findsOneWidget);
    expect(find.text('Acceptance of Terms'), findsOneWidget);
  });

  testWidgets('tapping FAQ opens the in-app FAQ screen', (tester) async {
    await _buildApp(tester);
    await _openSettings(tester);

    await tester.tap(find.text('FAQ').first);
    await tester.pumpAndSettle();

    expect(find.byType(FaqScreen), findsOneWidget);
    expect(find.text(FaqScreen.entries.first.question), findsOneWidget);
  });
}

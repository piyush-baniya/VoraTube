import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/app/app.dart';
import 'package:vora_tube/app/home_shell.dart';
import 'package:vora_tube/app/widgets/glass_nav_bar.dart';
import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/core/permissions/permission_service.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/player/presentation/widgets/mini_player.dart';
import 'package:vora_tube/features/settings/presentation/providers/settings_providers.dart';

import 'fakes/fake_player.dart';

/// A [PermissionService] that always reports access is granted so the shell
/// can render in tests without reaching the real platform channel.
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

void main() {
  ProviderScope buildApp() {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return ProviderScope(
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
  }

  Future<void> settleShell(WidgetTester tester) async {
    // Let the 800ms splash timer fire and the crossfade settle, then let
    // settings + the empty ingest scan complete.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  testWidgets('detail routes render under the persistent shell (nested '
      'navigator) and system back pops only the detail route', (tester) async {
    await tester.pumpWidget(buildApp());
    await settleShell(tester);

    expect(find.byType(GlassNavBar), findsOneWidget);
    expect(find.byType(MiniPlayer), findsOneWidget);

    // The nested navigator hosting the tabs sits inside HomeShell. The root
    // MaterialApp navigator is an ancestor, so this finds only the nested one.
    final nestedNav = tester.state<NavigatorState>(
      find.descendant(
        of: find.byType(HomeShell),
        matching: find.byType(Navigator),
      ),
    );

    // A drilled-down route (e.g. a playlist detail / statistics screen).
    nestedNav.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('detail'))),
      ),
    );
    await tester.pumpAndSettle();

    // The detail route renders inside the shell: the bottom bar and MiniPlayer
    // remain visible beneath it rather than being covered by a root route.
    expect(find.text('detail'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GlassNavBar),
        matching: find.text('Home'),
      ),
      findsOneWidget,
    );
    expect(find.byType(GlassNavBar), findsOneWidget);
    expect(find.byType(MiniPlayer), findsOneWidget);

    // Simulate the Android system back button.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Only the detail route was popped; the shell is intact.
    expect(find.text('detail'), findsNothing);
    expect(find.byType(GlassNavBar), findsOneWidget);
    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GlassNavBar),
        matching: find.text('Home'),
      ),
      findsOneWidget,
    );
  });
}

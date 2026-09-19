import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/app/app.dart';
import 'package:vora_tube/app/home_shell.dart';
import 'package:vora_tube/app/widgets/glass_nav_bar.dart';
import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/core/permissions/permission_service.dart';
import 'package:vora_tube/features/ads/premium_providers.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/player/presentation/widgets/mini_player.dart';
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

SongRef _song(int id) {
  return SongRef(
    identityKey: 'ms:$id',
    uri: 'content://media/external/audio/media/$id',
    title: 'Test Song $id',
    artist: 'Test Artist',
    album: 'Test Album',
    durationMs: 200000,
  );
}

/// Records which transport actions the shell's MiniPlayer dispatches.
class _RecordingPlayer extends FakePlayerController {
  _RecordingPlayer({super.initial, super.queue});

  final List<String> calls = [];

  @override
  Future<void> next() async => calls.add('next');

  @override
  Future<void> previous() async => calls.add('previous');

  @override
  Future<void> clearSession() async {
    calls.add('clearSession');
    await super.clearSession();
  }
}

void main() {
  ProviderScope buildApp({FakePlayerController? player}) {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        libraryRepositoryProvider.overrideWithValue(LibraryRepository(db)),
        playerProvider.overrideWithValue(
          player ?? FakePlayerController(),
        ),
        ingestServiceProvider.overrideWithValue(const _FakeIngestService()),
        permissionServiceProvider.overrideWithValue(
          const _GrantedPermissionService(),
        ),
        // Premium on: collapses every banner (and suppresses interstitial
        // loads) so widget tests never touch the ad SDK.
        isPremiumProvider.overrideWithValue(true),
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
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  int currentTabIndex(WidgetTester tester) {
    final pageView = tester.widget<PageView>(
      find
          .descendant(
            of: find.byType(HomeShell),
            matching: find.byType(PageView),
          )
          .first,
    );
    return pageView.controller?.page?.round() ?? -1;
  }

  int navCurrentIndex(WidgetTester tester) =>
      tester.widget<GlassNavBar>(find.byType(GlassNavBar)).currentIndex;

  /// A point in the fixed header of whichever tab is on screen: headers are
  /// plainly laid out above every tab's scrollable content, so a horizontal
  /// drag here belongs to the PageView, never to a nested carousel.
  Offset swipeStart(WidgetTester tester) =>
      tester.getTopLeft(find.byType(PageView)) + const Offset(400, 24);

  Future<void> swipe(WidgetTester tester, Offset offset) async {
    await tester.dragFrom(swipeStart(tester), offset);
    await tester.pumpAndSettle();
  }

  testWidgets('a horizontal swipe from Home opens Library and the nav follows',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await settleShell(tester);

    expect(currentTabIndex(tester), 0);
    expect(navCurrentIndex(tester), 0);

    await swipe(tester, const Offset(-450, 0));

    expect(currentTabIndex(tester), 1);
    expect(navCurrentIndex(tester), 1);
  });

  testWidgets('a horizontal swipe on Library returns to Home', (tester) async {
    await tester.pumpWidget(buildApp());
    await settleShell(tester);

    await swipe(tester, const Offset(-450, 0));
    expect(currentTabIndex(tester), 1);

    await swipe(tester, const Offset(450, 0));

    expect(currentTabIndex(tester), 0);
    expect(navCurrentIndex(tester), 0);
  });

  testWidgets('successive swipes reach every screen, home to settings', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await settleShell(tester);

    for (var i = 1; i < 5; i++) {
      await swipe(tester, const Offset(-450, 0));
      expect(currentTabIndex(tester), i);
      expect(navCurrentIndex(tester), i);
    }

    // And every screen back.
    for (var i = 3; i >= 0; i--) {
      await swipe(tester, const Offset(450, 0));
      expect(currentTabIndex(tester), i);
      expect(navCurrentIndex(tester), i);
    }
  });

  testWidgets('swiping right on the first screen does not leave it', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await settleShell(tester);

    await swipe(tester, const Offset(450, 0));

    expect(currentTabIndex(tester), 0);
    expect(navCurrentIndex(tester), 0);
  });

  testWidgets('vertical scrolling inside a tab does not switch tabs', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await settleShell(tester);

    final rect = tester.getRect(find.byType(PageView));
    final start =
        tester.getTopLeft(find.byType(PageView)) +
        Offset(400, rect.height * 0.6);
    await tester.dragFrom(start, const Offset(0, -150));
    await tester.pumpAndSettle();

    expect(currentTabIndex(tester), 0);
    expect(navCurrentIndex(tester), 0);
  });

  testWidgets(
    'a horizontal swipe on the MiniPlayer skips a track without switching '
    'tabs',
    (tester) async {
      final player = _RecordingPlayer(
        initial: PlayerSnapshot(
          status: PlayerStatus.ready,
          isPlaying: false,
          repeatMode: RepeatMode.off,
          shuffleEnabled: false,
          queueLength: 2,
          currentIndex: 0,
          durationMs: 200000,
          current: _song(1),
        ),
        queue: [_song(1), _song(2)],
      );
      await tester.pumpWidget(buildApp(player: player));
      await settleShell(tester);

      expect(find.byType(MiniPlayer), findsOneWidget);

      await tester.fling(
        find.byType(MiniPlayer),
        const Offset(200, 0),
        1500,
      );
      await tester.pumpAndSettle();

      expect(player.calls, contains('next'));
      expect(currentTabIndex(tester), 0);
      expect(navCurrentIndex(tester), 0);
    },
  );
}
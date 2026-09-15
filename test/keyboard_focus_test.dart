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
import 'package:vora_tube/features/library/presentation/widgets/song_tile.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
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

IngestTrack _msTrack(int id, {String? title}) {
  return IngestTrack(
    source: IngestSource.mediastore,
    mediaStoreId: id,
    albumMediaStoreId: 100 + id,
    artistMediaStoreId: 200 + id,
    albumKey: 'ms:${100 + id}',
    artistKey: 'ms:${200 + id}',
    contentUri: 'content://media/external/audio/media/$id',
    path: '/storage/emulated/0/Music/song_$id.mp3',
    title: title ?? 'Song $id',
    artist: 'Artist ${id % 3}',
    album: 'Album ${id % 2}',
    durationMs: 180000 + id,
    dateModifiedSec: 100 + id,
    year: 2020,
    trackNumber: id,
    sizeBytes: 5000 + id,
    dateAddedSec: 90 + id,
  );
}

Future<void> _buildApp(WidgetTester tester, {required AppDatabase db}) async {
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
    find.descendant(
      of: find.byType(GlassNavBar),
      matching: find.byWidgetPredicate(
        (w) => w is Icon && (w.icon == outlined || w.icon == selected),
      ),
    ),
  );
}

int _currentTabIndex(WidgetTester tester) {
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

/// The one [PageView] that hosts the five tab bodies (Home, Library, Search,
/// Playlists, Settings).
Finder _tabsPageView() {
  return find
      .descendant(
        of: find.byType(HomeShell),
        matching: find.byType(PageView),
      )
      .first;
}

/// Asserts no text input is attached, i.e. the soft keyboard would not be
/// showing on a device.
void _expectKeyboardHidden(WidgetTester tester, String reason) {
  expect(
    tester.testTextInput.hasAnyClients,
    isFalse,
    reason: reason,
  );
}

/// The Search screen's field is the shell's only TextField once visited.
TextField _searchField(WidgetTester tester) {
  return tester.widget<TextField>(find.byType(TextField));
}

void main() {
  group('keyboard does not auto-appear when switching screens', () {
    testWidgets('Test 1: Home → Library never opens the keyboard', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _buildApp(tester, db: db);

      _expectKeyboardHidden(tester, 'app start must not focus the keyboard');
      expect(_currentTabIndex(tester), 0);
      expect(find.byType(TextField), findsNothing);

      await _tapTab(tester, Icons.library_music_outlined, Icons.library_music);
      await tester.pumpAndSettle();

      expect(_currentTabIndex(tester), 1);
      _expectKeyboardHidden(tester, 'Home → Library must not open the keyboard');
    });

    testWidgets('Test 2: Library → Search does not auto-focus or auto-open '
        'the keyboard', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _buildApp(tester, db: db);

      await _tapTab(tester, Icons.search_outlined, Icons.search);
      await tester.pumpAndSettle();

      expect(_currentTabIndex(tester), 2);
      _expectKeyboardHidden(
        tester,
        'arriving on Search via the tab bar must not auto-focus the field',
      );
      expect(_searchField(tester).focusNode?.hasFocus, isFalse,
          reason: 'Search field must not grab focus on tab arrival');
    });

    testWidgets('Test 3: Search → Library → Home → Stats → Settings keeps '
        'the keyboard hidden', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LibraryRepository(db);
      await repo.syncTracks([_msTrack(1)]);
      final page = await repo.songsPage(limit: 10);
      await repo.recordPlayback([page.songs.first.song.id], DateTime.now());
      await _buildApp(tester, db: db);

      await _tapTab(tester, Icons.search_outlined, Icons.search);
      await tester.pumpAndSettle();
      _expectKeyboardHidden(tester, 'Search tab must not open the keyboard');

      await _tapTab(tester, Icons.library_music_outlined, Icons.library_music);
      await tester.pumpAndSettle();
      expect(_currentTabIndex(tester), 1);
      _expectKeyboardHidden(tester, 'leaving Search must keep keyboard hidden');

      await _tapTab(tester, Icons.home_outlined, Icons.home);
      await tester.pumpAndSettle();
      expect(_currentTabIndex(tester), 0);
      _expectKeyboardHidden(tester, 'Home must not open the keyboard');

      // Statistics is a pushed detail route reachable from Home.
      await tester.tap(find.text('View Stats'));
      await tester.pumpAndSettle();
      expect(find.text('Statistics'), findsOneWidget);
      _expectKeyboardHidden(tester, 'pushed Statistics route must stay quiet');

      await _tapTab(tester, Icons.settings_outlined, Icons.settings);
      await tester.pumpAndSettle();
      expect(find.text('Statistics'), findsNothing);
      expect(_currentTabIndex(tester), 4);
      _expectKeyboardHidden(tester, 'Settings must not open the keyboard');
    });

    testWidgets('Test 4: tapping the search field intentionally opens the '
        'keyboard', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _buildApp(tester, db: db);

      await _tapTab(tester, Icons.search_outlined, Icons.search);
      await tester.pumpAndSettle();
      _expectKeyboardHidden(tester, 'Search tab must not open the keyboard');

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(tester.testTextInput.hasAnyClients, isTrue,
          reason: 'tapping the field must open the keyboard');
      expect(_searchField(tester).focusNode?.hasFocus, isTrue,
          reason: 'tapping the field must focus it');
    });

    testWidgets('Test 5: typing in Search then switching away closes the '
        'keyboard and preserves the query', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LibraryRepository(db);
      await repo.syncTracks([_msTrack(1, title: 'Hello Song')]);
      await _buildApp(tester, db: db);

      await _tapTab(tester, Icons.search_outlined, Icons.search);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(tester.testTextInput.hasAnyClients, isTrue,
          reason: 'typing must keep the keyboard open');
      // Search titles are rendered as highlighted RichText, so assert through
      // the shared result tile instead of a plain Text match.
      expect(find.byType(SongTile), findsNWidgets(1));
      final fieldSnapshot = _searchField(tester).controller?.text;

      await _tapTab(tester, Icons.library_music_outlined, Icons.library_music);
      await tester.pumpAndSettle();
      _expectKeyboardHidden(
        tester,
        'switching away from Search must close the keyboard',
      );

      await _tapTab(tester, Icons.search_outlined, Icons.search);
      await tester.pumpAndSettle();
      _expectKeyboardHidden(
        tester,
        'returning to Search must not reopen the keyboard',
      );
      expect(_searchField(tester).controller?.text, fieldSnapshot,
          reason: 'the query must survive the tab switch');
      expect(find.byType(SongTile), findsNWidgets(1));
    });

    testWidgets('Test 6: swiping between screens behaves like bottom-bar '
        'switching (no auto-keyboard, manual tap still opens it)', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _buildApp(tester, db: db);

      // Home → Library by swiping the tab PageView.
      await tester.fling(_tabsPageView(), const Offset(-600, 0), 1500);
      await tester.pumpAndSettle();
      expect(_currentTabIndex(tester), 1);
      _expectKeyboardHidden(tester, 'swipe to Library must stay quiet');

      // Library → Search by swiping.
      await tester.fling(_tabsPageView(), const Offset(-600, 0), 1500);
      await tester.pumpAndSettle();
      expect(_currentTabIndex(tester), 2);
      _expectKeyboardHidden(tester, 'swipe to Search must stay quiet');
      expect(_searchField(tester).focusNode?.hasFocus, isFalse,
          reason: 'swiping onto Search must not focus the field');

      // Intentional tap opens the keyboard…
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.hasAnyClients, isTrue,
          reason: 'tapping the field must open the keyboard');

      // …and swiping away closes it again.
      await tester.fling(_tabsPageView(), const Offset(600, 0), 1500);
      await tester.pumpAndSettle();
      expect(_currentTabIndex(tester), 1);
      _expectKeyboardHidden(
        tester,
        'swiping away from Search must close the keyboard',
      );
    });
  });
}
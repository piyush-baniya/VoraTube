import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/app/app.dart';
import 'package:vora_tube/app/theme/app_theme.dart';
import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/core/permissions/permission_service.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/settings/data/settings_models.dart';
import 'package:vora_tube/features/settings/presentation/providers/settings_providers.dart';
import 'package:vora_tube/features/settings/presentation/screens/settings_screen.dart';
import 'package:vora_tube/features/settings/presentation/widgets/settings_tile.dart';

import 'fakes/fake_player.dart';

// ── Pure unit coverage: presets, theme construction, JSON persistence ────

void main() {
  group('AppThemePreset and palettes', () {
    test('exactly 9 presets with unique identities', () {
      expect(AppPalettes.all, hasLength(9));
      expect(AppThemePreset.values, hasLength(9));
      for (final palette in AppPalettes.all) {
        expect(palette.preset.label, isNotEmpty);
        expect(palette.preset.mood, isNotEmpty);
      }
      // Guards against accidental duplicate palettes in AppPalettes.all.
      expect(
        AppPalettes.all.map((p) => p.preset).toSet(),
        hasLength(9),
      );
    });

    test('first palette is the default Purple identity', () {
      final purple = AppPalettes.all.first;
      expect(purple.preset, AppThemePreset.purple);
      expect(purple.primary, const Color(0xFF7C3AED));
      expect(purple.highlight, const Color(0xFF8B5CF6));
      expect(purple.lightDeep, const Color(0xFF5B21B6));
    });

    test('AppPalette.of resolves every registered preset', () {
      for (final palette in AppPalettes.all) {
        expect(AppPalette.of(palette.preset), same(palette));
      }
    });

    test('default purple uses the shared neutral ramps', () {
      final purple = AppPalette.of(AppThemePreset.purple);
      expect(purple.darkSurfaces, isNull);
      expect(purple.lightSurfaces, isNull);
      expect(purple.darkRamp, same(AppPalettes.darkNeutral));
      expect(purple.lightRamp, same(AppPalettes.lightNeutral));
    });

    test('custom-surface presets carry their own ramps', () {
      expect(
        AppPalette.of(AppThemePreset.midnight).darkRamp.surface,
        const Color(0xFF0B1120),
      );
      expect(
        AppPalette.of(AppThemePreset.oled).darkRamp.surface,
        const Color(0xFF000000),
      );
      expect(
        AppPalette.of(AppThemePreset.sepia).lightRamp.surface,
        const Color(0xFFF5EFE4),
      );
    });
  });

  group('AppTheme construction', () {
    test('all 9 presets build distinct light+dark themes without throwing', () {
      for (final preset in AppThemePreset.values) {
        final themes = AppTheme.of(preset);
        expect(themes.light.colorScheme.primary, isNotNull);
        expect(themes.dark.colorScheme.primary, isNotNull);
        expect(
          themes.light.colorScheme.primary,
          isNot(themes.dark.colorScheme.primary),
          reason: 'light uses the deep accent, dark the vivid one',
        );
      }
    });

    test('theme colors match the palette contract', () {
      for (final palette in AppPalettes.all) {
        final themes = AppTheme.of(palette.preset);
        expect(
          themes.dark.colorScheme.surface,
          palette.darkRamp.surface,
          reason: '${palette.preset.label} dark surface',
        );
        // Brightness-aware: dark primary is the vivid accent; light primary is
        // the deep accent for contrast on pale surfaces.
        expect(themes.dark.colorScheme.primary, palette.primary);
        expect(themes.light.colorScheme.primary, palette.lightDeep);
        // onPrimary stays white for vivid accents (incl. Ember amber).
        expect(themes.light.colorScheme.onPrimary, const Color(0xFFFFFFFF));
      }
    });

    test('OLED produces true black, Sepia produces warm parchment', () {
      final oled = AppTheme.of(AppThemePreset.oled);
      expect(oled.dark.colorScheme.surface, const Color(0xFF000000));
      expect(
        oled.dark.colorScheme.surfaceContainerHighest,
        isNot(const Color(0xFF000000)),
        reason: 'OLED keeps a whisper of elevation so cards stay readable',
      );

      final sepia = AppTheme.of(AppThemePreset.sepia);
      expect(sepia.light.colorScheme.surface, const Color(0xFFF5EFE4));
      expect(sepia.dark.colorScheme.surface, const Color(0xFF141210));
    });

    test('themes are memoized per preset', () {
      expect(AppTheme.of(AppThemePreset.purple), same(AppTheme.of(AppThemePreset.purple)));
      expect(
        AppTheme.of(AppThemePreset.ocean).dark,
        same(AppTheme.of(AppThemePreset.ocean).dark),
      );
    });

    testWidgets(
        'context.palette and context.surfaces resolve on theme extensions',
        (tester) async {
      AppPalette? seenPalette;
      Color? seenSurface;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppThemePreset.sepia),
          darkTheme: AppTheme.dark(AppThemePreset.sepia),
          themeMode: ThemeMode.dark,
          home: Builder(
            builder: (context) {
              seenPalette = context.palette;
              seenSurface = context.surfaces.surface;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seenPalette, same(AppPalette.of(AppThemePreset.sepia)));
      expect(seenSurface, const Color(0xFF141210));
    });

    testWidgets(
        'context accessors fall back to Purple/neutrals outside the app theme',
        (tester) async {
      AppPalette? seenPalette;
      Color? seenSurface;
      await tester.pumpWidget(
        MaterialApp(
          // A bare theme with no VoraTube extension at all.
          theme: ThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (context) {
              seenPalette = context.palette;
              seenSurface = context.surfaces.surface;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seenPalette, same(AppPalette.of(AppThemePreset.purple)));
      expect(
        seenSurface,
        same(AppPalettes.darkNeutral.surface),
        reason: 'fallback uses the shared neutral ramp for the brightness',
      );
    });
  });

  group('AppearanceSettings persistence', () {
    test('default is Purple + system theme', () {
      const settings = AppearanceSettings();
      expect(settings.themePreset, AppThemePreset.purple);
      expect(settings.themeMode, AppThemeMode.system);
    });

    test('legacy JSON without themePreset migrates to Purple', () {
      final parsed = AppearanceSettingsJson.fromJson(
        '{"themeMode": "dark"}',
      );
      expect(parsed.themeMode, AppThemeMode.dark);
      expect(parsed.themePreset, AppThemePreset.purple);
    });

    test('unknown preset name falls back to Purple', () {
      final parsed = AppearanceSettingsJson.fromJson(
        '{"themePreset": "neon"}',
      );
      expect(parsed.themePreset, AppThemePreset.purple);
    });

    test('appearance JSON round-trips themeMode + themePreset', () {
      const settings = AppearanceSettings(
        themeMode: AppThemeMode.dark,
        themePreset: AppThemePreset.ocean,
      );
      final json = settings.toJson();
      expect(json, contains('"themePreset": "ocean"'));
      final parsed = AppearanceSettingsJson.fromJson(json);
      expect(parsed.themeMode, AppThemeMode.dark);
      expect(parsed.themePreset, AppThemePreset.ocean);
    });

    test('AppSettings JSON round-trips the whole appearance block', () {
      const settings = AppSettings(
        appearance: AppearanceSettings(
          themeMode: AppThemeMode.light,
          themePreset: AppThemePreset.sepia,
        ),
      );
      final json = settings.toJson();
      final parsed = AppSettingsJson.fromJson(json);
      expect(parsed.appearance.themeMode, AppThemeMode.light);
      expect(parsed.appearance.themePreset, AppThemePreset.sepia);
    });
  });

  group('theme preset controller + providers', () {
    Future<LibraryRepository> newRepository() async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      return LibraryRepository(db);
    }

    test('controller defaults to Purple and persists a chosen preset',
        () async {
      final repo = await newRepository();
      final controller = AppearanceSettingsController(repo);
      expect(controller.state.themePreset, AppThemePreset.purple);

      await controller.setThemePreset(AppThemePreset.ocean);
      expect(controller.state.themePreset, AppThemePreset.ocean);

      // A fresh controller over the same KV storage survives a "restart".
      final restored = AppearanceSettingsController(repo);
      await pumpEventQueue();
      expect(restored.state.themePreset, AppThemePreset.ocean);
    });

    test('changing preset never drops the chosen theme mode', () async {
      final repo = await newRepository();
      final controller = AppearanceSettingsController(repo);
      await controller.setThemeMode(AppThemeMode.dark);
      await controller.setThemePreset(AppThemePreset.midnight);

      final restored = AppearanceSettingsController(repo);
      await pumpEventQueue();
      expect(restored.state.themeMode, AppThemeMode.dark);
      expect(restored.state.themePreset, AppThemePreset.midnight);
    });

    test('themeModeProvider and themePresetProvider reflect state', () async {
      final repo = await newRepository();
      final container = ProviderContainer(
        overrides: [
          libraryRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(themePresetProvider), AppThemePreset.purple);
      expect(container.read(themeModeProvider), ThemeMode.system);

      await container
          .read(appearanceSettingsProvider.notifier)
          .setThemePreset(AppThemePreset.rose);
      await pumpEventQueue();
      expect(container.read(themePresetProvider), AppThemePreset.rose);
      expect(container.read(themeModeProvider), ThemeMode.system);
    });
  });

  group('settings UI live switching', () {
    testWidgets('nine presets are listed and tapping one re-themes the app',
        (tester) async {
      // The app runs in ThemeMode.system, so force the platform to dark — the
      // vivid primary and custom surface ramps (OLED true black) only show on
      // the dark side.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await _buildApp(tester);
      await _openSettings(tester);

      for (final palette in AppPalettes.all) {
        expect(
          find.text(palette.preset.label),
          findsOneWidget,
          reason: '${palette.preset.label} preset row must be visible',
        );
      }

      // Default selection is checked on Purple (scoped to its own row
      // because unrelated success checkmarks appear elsewhere on the screen).
      final purpleRow = find.ancestor(
        of: find.text('Purple'),
        matching: find.byType(SettingsTile),
      );
      expect(
        find.descendant(of: purpleRow, matching: find.byType(Icon)),
        findsOneWidget,
      );

      // Tap Aurora → the theme is rebuilt instantly (no restart needed).
      await tester.tap(find.text('Aurora'));
      await tester.pumpAndSettle();

      final settingsContext = tester.element(find.byType(SettingsScreen));
      final appliedPrimary = Theme.of(settingsContext).colorScheme.primary;
      expect(appliedPrimary, AppPalette.aurora.primary);

      // Check moved onto Aurora.
      final auroraRow = find.ancestor(
        of: find.text('Aurora'),
        matching: find.byType(SettingsTile),
      );
      expect(
        find.descendant(of: auroraRow, matching: find.byType(Icon)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: purpleRow, matching: find.byType(Icon)),
        findsNothing,
      );

      // Tap OLED → the dark surface flips to true black.
      await tester.tap(find.text('OLED'));
      await tester.pumpAndSettle();
      final oledContext = tester.element(find.byType(SettingsScreen));
      expect(
        Theme.of(oledContext).colorScheme.surface,
        const Color(0xFF000000),
      );

      // Tap Midnight → cyan accent takes over the black canvas.
      await tester.tap(find.text('Midnight'));
      await tester.pumpAndSettle();
      final midnightContext = tester.element(find.byType(SettingsScreen));
      expect(
        Theme.of(midnightContext).colorScheme.primary,
        AppPalette.midnight.primary,
      );

      // Flipping the platform brightness to light re-themes via system mode:
      // the same Midnight preset now uses its light deep accent.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      final lightContext = tester.element(find.byType(SettingsScreen));
      expect(
        Theme.of(lightContext).colorScheme.primary,
        AppPalette.midnight.lightDeep,
        reason: 'the app must follow system brightness inside a preset',
      );
    });

    testWidgets('a persisted preset is applied on app start', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LibraryRepository(db);
      // Simulate a previous session having picked Ember.
      await AppearanceSettingsController(repo).setThemePreset(
        AppThemePreset.ember,
      );

      await _buildApp(tester, database: db, repository: repo);
      await _openSettings(tester);

      final settingsContext = tester.element(find.byType(SettingsScreen));
      expect(
        Theme.of(settingsContext).colorScheme.primary,
        AppPalette.ember.lightDeep,
        reason: 'app must boot into the saved preset without user action',
      );
      final emberRow = find.ancestor(
        of: find.text('Ember'),
        matching: find.byType(SettingsTile),
      );
      expect(
        find.descendant(of: emberRow, matching: find.byType(Icon)),
        findsOneWidget,
        reason: 'the persisted preset row shows the check on launch',
      );
    });
  });
}

// ── App harness (mirrors settings_screen_navigation_test) ────────────────

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
  LibraryRepository? repository,
  AppDatabase? database,
}) async {
  final db = database ?? AppDatabase(NativeDatabase.memory());
  if (database == null) addTearDown(db.close);
  final repo = repository ?? LibraryRepository(db);

  final container = ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      libraryRepositoryProvider.overrideWithValue(repo),
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
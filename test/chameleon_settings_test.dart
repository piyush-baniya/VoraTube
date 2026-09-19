import 'package:drift/native.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/app/theme/app_theme.dart';
import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/settings/data/settings_models.dart';
import 'package:vora_tube/features/settings/presentation/providers/settings_providers.dart';

void main() {
  group('AppThemeMode.chameleon persistence', () {
    test('serializes to "chameleon" and round-trips with the preset', () {
      const settings = AppearanceSettings(
        themeMode: AppThemeMode.chameleon,
        themePreset: AppThemePreset.ocean,
      );
      final json = settings.toJson();
      expect(json, contains('"themeMode": "chameleon"'));
      expect(json, contains('"themePreset": "ocean"'));

      final parsed = AppearanceSettingsJson.fromJson(json);
      expect(parsed.themeMode, AppThemeMode.chameleon);
      expect(parsed.themePreset, AppThemePreset.ocean);
    });

    test('unknown themeMode falls back to system (forward compatible)', () {
      final parsed = AppearanceSettingsJson.fromJson('{"themeMode": "aurora"}');
      expect(parsed.themeMode, AppThemeMode.system);
      expect(parsed.themePreset, AppThemePreset.purple);
    });
  });

  group('chameleon settings providers', () {
    Future<LibraryRepository> newRepository() async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      return LibraryRepository(db);
    }

    test(
      'isChameleonProvider follows the mode; themeModeProvider stays mapped',
      () async {
        final repo = await newRepository();
        final container = ProviderContainer(
          overrides: [libraryRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        expect(container.read(isChameleonProvider), isFalse);
        expect(container.read(themeModeProvider), ThemeMode.system);

        await container
            .read(appearanceSettingsProvider.notifier)
            .setThemeMode(AppThemeMode.chameleon);
        await pumpEventQueue();
        expect(container.read(isChameleonProvider), isTrue);
        // Non-artwork-aware consumers (e.g. the artwork palette fallback) still
        // receive a usable ThemeMode: system maps to platform brightness.
        expect(container.read(themeModeProvider), ThemeMode.system);

        await container
            .read(appearanceSettingsProvider.notifier)
            .setThemeMode(AppThemeMode.dark);
        await pumpEventQueue();
        expect(container.read(isChameleonProvider), isFalse);
        expect(container.read(themeModeProvider), ThemeMode.dark);

        await container
            .read(appearanceSettingsProvider.notifier)
            .setThemeMode(AppThemeMode.light);
        await pumpEventQueue();
        expect(container.read(isChameleonProvider), isFalse);
        expect(container.read(themeModeProvider), ThemeMode.light);
      },
    );

    test(
      'changing the preset while Chameleon preserves the mode and persists',
      () async {
        final repo = await newRepository();
        final controller = AppearanceSettingsController(repo);
        await controller.setThemeMode(AppThemeMode.chameleon);
        await controller.setThemePreset(AppThemePreset.sepia);

        // A fresh controller over the same KV store survives a "restart".
        final restored = AppearanceSettingsController(repo);
        await pumpEventQueue();
        expect(restored.state.themeMode, AppThemeMode.chameleon);
        expect(restored.state.themePreset, AppThemePreset.sepia);

// The preserved preset is still exposed through the preset provider.
      final container = ProviderContainer(
        overrides: [libraryRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      // Touch the provider so the async load starts, then let it finish.
      container.read(isChameleonProvider);
      await pumpEventQueue();
      expect(container.read(isChameleonProvider), isTrue);
      expect(container.read(themePresetProvider), AppThemePreset.sepia);
      },
    );

    test('chameleon is not lost across an appearance JSON round-trip', () {
      const app = AppSettings(
        appearance: AppearanceSettings(
          themeMode: AppThemeMode.chameleon,
          themePreset: AppThemePreset.midnight,
        ),
      );
      final json = app.toJson();
      final parsed = AppSettingsJson.fromJson(json);
      expect(parsed.appearance.themeMode, AppThemeMode.chameleon);
      expect(parsed.appearance.themePreset, AppThemePreset.midnight);
    });
  });
}

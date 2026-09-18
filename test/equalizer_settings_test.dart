import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/audio/audio_effects.dart';
import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/player/data/equalizer_settings.dart';
import 'package:vora_tube/features/player/presentation/providers/equalizer_providers.dart';
import 'package:vora_tube/features/settings/data/settings_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EqualizerUiSettings JSON', () {
    test('round-trips mode, presets and selection', () {
      const settings = EqualizerUiSettings(
        mode: EqMode.advanced,
        selectedPresetId: 'abc',
        presets: [
          EqCustomPreset(
            id: 'abc',
            name: 'Late night',
            levels: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
            pinned: true,
          ),
        ],
      );
      final restored = EqualizerUiSettings.tryDecode(settings.encode());
      expect(restored, settings);
    });

    test('corrupt data falls back to defaults without throwing', () {
      final restored = EqualizerUiSettings.tryDecode('not json');
      expect(restored.mode, EqMode.simple);
      expect(restored.presets, isEmpty);
      expect(restored.selectedPresetId, isNull);
    });

    test('drops presets with duplicate or missing ids', () {
      const source =
          '{"v":1,"mode":"simple","selected":null,"presets":['
          '{"id":"a","name":"A","levels":[0,0,0,0,0,0,0,0,0,0]},'
          '{"id":"a","name":"A again","levels":[0,0,0,0,0,0,0,0,0,0]},'
          '{"name":"No id","levels":[0,0,0,0,0,0,0,0,0,0]}'
          ']}';
      final restored = EqualizerUiSettings.tryDecode(source);
      expect(restored.presets, hasLength(1));
      expect(restored.presets.single.name, 'A');
    });

    test('a selection pointing at a deleted preset is cleared', () {
      const source = '{"v":1,"mode":"simple","selected":"gone","presets":[]}';
      expect(EqualizerUiSettings.tryDecode(source).selectedPresetId, isNull);
    });
  });

  group('EqualizerSettingsController', () {
    late AppDatabase db;
    late LibraryRepository repository;
    late EqualizerSettingsController controller;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repository = LibraryRepository(db);
      controller = EqualizerSettingsController(repository);
    });

    tearDown(() async {
      controller.dispose();
      await db.close();
    });

    test('starts in Simple mode with no saved curves', () {
      expect(controller.state.mode, EqMode.simple);
      expect(controller.state.presets, isEmpty);
    });

    test('saving a curve selects it and stores normalized levels', () {
      final saved = controller.savePreset('  My curve  ', [4.0, -4.0]);
      expect(saved, isNotNull);
      expect(controller.state.presets, hasLength(1));
      expect(controller.state.presets.single.name, 'My curve');
      expect(controller.state.presets.single.levels, hasLength(10));
      expect(controller.state.selectedPresetId, saved!.id);
    });

    test('an empty name is rejected', () {
      expect(controller.savePreset('   ', const []), isNull);
      expect(controller.state.presets, isEmpty);
    });

    test(
      'rename, duplicate, pin and delete operate on the right curve',
      () async {
        final saved = controller.savePreset('A', const [])!;
        await controller.renamePreset(saved.id, 'B');
        expect(controller.state.presets.single.name, 'B');

        await controller.duplicatePreset(saved.id);
        expect(controller.state.presets, hasLength(2));
        expect(controller.state.presets.last.name, 'B copy');
        expect(
          controller.state.selectedPresetId,
          controller.state.presets.last.id,
        );

        await controller.togglePin(saved.id);
        expect(controller.state.presetById(saved.id)!.pinned, true);

        await controller.deletePreset(saved.id);
        expect(controller.state.presets, hasLength(1));
        expect(controller.state.presetById(saved.id), isNull);
      },
    );

    test('reordering moves the curve to the requested slot', () async {
      final a = controller.savePreset('A', const [])!;
      final b = controller.savePreset('B', const [])!;
      final c = controller.savePreset('C', const [])!;
      await controller.reorderPresets(0, 3);
      expect(controller.state.presets.map((p) => p.id), [b.id, c.id, a.id]);
    });

    test('selection clears when the selected curve is deleted', () async {
      final saved = controller.savePreset('A', const [])!;
      expect(controller.state.selectedPresetId, saved.id);
      await controller.deletePreset(saved.id);
      expect(controller.state.selectedPresetId, isNull);
    });

    test('mode changes persist to the equalizer settings key', () async {
      await controller.setMode(EqMode.advanced);
      final stored = await repository.kvGet(SettingsKeys.equalizer);
      expect(stored, isNotNull);
      expect(EqualizerUiSettings.tryDecode(stored!).mode, EqMode.advanced);
    });
  });
}

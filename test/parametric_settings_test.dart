import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/audio/parametric_eq.dart';
import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/player/data/equalizer_settings.dart';
import 'package:vora_tube/features/player/presentation/providers/equalizer_providers.dart';
import 'package:vora_tube/features/settings/data/settings_models.dart';

ParametricEqBand _band({
  String id = 'p1',
  ParametricFilterType type = ParametricFilterType.peaking,
  double f = 1000,
  double g = 0,
  double q = 1,
  bool enabled = true,
}) => ParametricEqBand(
  id: id,
  type: type,
  frequencyHz: f,
  gainDb: g,
  q: q,
  enabled: enabled,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioSettings parametric JSON', () {
    test('eqMode and bands survive a round-trip', () {
      final settings = AudioSettings(
        eqEnabled: true,
        eqMode: EqEngineMode.parametric,
        parametricBands: [
          _band(type: ParametricFilterType.lowShelf, f: 120, g: 4.5, q: 0.8),
          _band(id: 'p2', f: 3200, g: -3.25, q: 2.5, enabled: false),
        ],
      );
      final restored = AudioSettingsJson.fromJson(settings.toJson());

      expect(restored.eqMode, EqEngineMode.parametric);
      expect(restored.parametricBands, hasLength(2));
      final first = restored.parametricBands.first;
      expect(first.id, 'p1');
      expect(first.type, ParametricFilterType.lowShelf);
      expect(first.frequencyHz, 120);
      expect(first.gainDb, 4.5);
      expect(first.q, 0.8);
      expect(restored.parametricBands.last.enabled, false);
      expect(restored.parametricBands.last.gainDb, -3.25);
    });

    test('legacy JSON without the new keys defaults to the graphic engine', () {
      const legacy =
          '{"replayGain": "off", "preampDb": 0.0, "eqEnabled": true}';
      final restored = AudioSettingsJson.fromJson(legacy);
      expect(restored.eqMode, EqEngineMode.graphic);
      expect(restored.parametricBands, isEmpty);
    });

    test('an empty band stack round-trips as empty', () {
      const settings = AudioSettings(eqMode: EqEngineMode.parametric);
      final restored = AudioSettingsJson.fromJson(settings.toJson());
      expect(restored.parametricBands, isEmpty);
      expect(restored.eqMode, EqEngineMode.parametric);
    });
  });

  group('AudioSettings parametric equality', () {
    test('equal band contents compare equal across instances', () {
      final a = AudioSettings(parametricBands: [_band(g: 3)]);
      final b = AudioSettings(parametricBands: [_band(g: 3)]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a band change breaks equality', () {
      final a = AudioSettings(parametricBands: [_band(g: 3)]);
      final b = AudioSettings(parametricBands: [_band(g: 4)]);
      expect(a == b, false);
    });

    test('a mode change breaks equality', () {
      const a = AudioSettings(eqMode: EqEngineMode.graphic);
      const b = AudioSettings(eqMode: EqEngineMode.parametric);
      expect(a == b, false);
    });
  });

  group('tryBandFromJson', () {
    test('parses a well-formed band', () {
      final band = tryBandFromJson({
        'id': 'x',
        'enabled': true,
        'type': 'highShelf',
        'f': 8000,
        'g': -2,
        'q': 1.2,
      });
      expect(band, isNotNull);
      expect(band!.type, ParametricFilterType.highShelf);
      expect(band.frequencyHz, 8000);
    });

    test('rejects a band without an id', () {
      expect(tryBandFromJson({'f': 1000}), isNull);
      expect(tryBandFromJson('not a map'), isNull);
    });

    test('clamps out-of-range values and defaults unknowns', () {
      final band = tryBandFromJson({'id': 'x', 'f': 99999, 'g': 99, 'q': 0});
      expect(band!.frequencyHz, 21600);
      expect(band.gainDb, parametricMaxGainDb);
      expect(band.q, parametricMinQ);
      expect(band.type, ParametricFilterType.peaking);
    });
  });

  group('ParametricEqSavedPreset.tryFromJson', () {
    test('rejects presets without a name or bands', () {
      expect(ParametricEqSavedPreset.tryFromJson({'id': 'a'}), isNull);
      expect(
        ParametricEqSavedPreset.tryFromJson({
          'id': 'a',
          'name': 'A',
          'bands': const [],
        }),
        isNull,
      );
    });
  });

  group('EqualizerUiSettings parametric JSON', () {
    test('round-trips saved parametric presets and selection', () {
      final settings = EqualizerUiSettings(
        parametricPresets: [
          ParametricEqSavedPreset(
            id: 'pp',
            name: 'Warm',
            pinned: true,
            bands: [_band(g: 2)],
          ),
        ],
        selectedParametricPresetId: 'pp',
      );
      final restored = EqualizerUiSettings.tryDecode(settings.encode());
      expect(restored.parametricPresets, hasLength(1));
      expect(restored.parametricPresets.single.name, 'Warm');
      expect(restored.parametricPresets.single.pinned, true);
      expect(restored.selectedParametricPresetId, 'pp');
      expect(restored, settings);
    });

    test('drops duplicate parametric ids and clears a stale selection', () {
      const source =
          '{"v":1,"mode":"simple","selected":null,"presets":[],'
          '"parametricPresets":['
          '{"id":"a","name":"A","bands":[{"id":"b1","type":"peaking","f":1000,"g":0,"q":1,"enabled":true}]},'
          '{"id":"a","name":"A again","bands":[{"id":"b1","type":"peaking","f":1000,"g":0,"q":1,"enabled":true}]}'
          '],"selectedParametric":"gone"}';
      final restored = EqualizerUiSettings.tryDecode(source);
      expect(restored.parametricPresets, hasLength(1));
      expect(restored.parametricPresets.single.name, 'A');
      expect(restored.selectedParametricPresetId, isNull);
    });
  });

  group('EqualizerSettingsController parametric presets', () {
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

    test('saving a parametric preset selects it', () {
      final saved = controller.saveParametricPreset('  Warm  ', [_band(g: 3)]);
      expect(saved, isNotNull);
      expect(saved!.name, 'Warm');
      expect(controller.state.parametricPresets, hasLength(1));
      expect(controller.state.selectedParametricPresetId, saved.id);
    });

    test('an empty name or empty bands are rejected', () {
      expect(controller.saveParametricPreset('  ', [_band()]), isNull);
      expect(controller.saveParametricPreset('Name', const []), isNull);
      expect(controller.state.parametricPresets, isEmpty);
    });

    test('rename, duplicate, pin and delete target the right preset', () async {
      final saved = controller.saveParametricPreset('A', [_band()])!;
      await controller.renameParametricPreset(saved.id, 'B');
      expect(controller.state.parametricPresets.single.name, 'B');

      await controller.duplicateParametricPreset(saved.id);
      expect(controller.state.parametricPresets, hasLength(2));
      expect(controller.state.parametricPresets.last.name, 'B copy');
      expect(
        controller.state.selectedParametricPresetId,
        controller.state.parametricPresets.last.id,
      );

      await controller.toggleParametricPin(saved.id);
      expect(controller.state.parametricPresetById(saved.id)!.pinned, true);

      await controller.deleteParametricPreset(saved.id);
      expect(controller.state.parametricPresets, hasLength(1));
      expect(controller.state.parametricPresetById(saved.id), isNull);
    });

    test('deleting the selected preset clears the selection', () async {
      final saved = controller.saveParametricPreset('A', [_band()])!;
      await controller.deleteParametricPreset(saved.id);
      expect(controller.state.selectedParametricPresetId, isNull);
    });

    test('reordering moves the requested preset', () async {
      final a = controller.saveParametricPreset('A', [_band()])!;
      final b = controller.saveParametricPreset('B', [_band()])!;
      final c = controller.saveParametricPreset('C', [_band()])!;
      await controller.reorderParametricPresets(0, 3);
      expect(controller.state.parametricPresets.map((p) => p.id), [
        b.id,
        c.id,
        a.id,
      ]);
    });

    test('editing bands updates only the target preset', () async {
      final a = controller.saveParametricPreset('A', [_band(g: 1)])!;
      final b = controller.saveParametricPreset('B', [_band(g: 1)])!;
      await controller.updateParametricPresetBands(a.id, [_band(g: -5)]);
      expect(
        controller.state.parametricPresetById(a.id)!.bands.first.gainDb,
        -5,
      );
      expect(
        controller.state.parametricPresetById(b.id)!.bands.first.gainDb,
        1,
      );
    });

    test('parametric presets persist to the equalizer settings key', () async {
      controller.saveParametricPreset('Warm', [_band(g: 2)]);
      final stored = await repository.kvGet(SettingsKeys.equalizer);
      expect(stored, isNotNull);
      final decoded = EqualizerUiSettings.tryDecode(stored!);
      expect(decoded.parametricPresets, hasLength(1));
      expect(decoded.parametricPresets.single.name, 'Warm');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/core/audio/audio_effects.dart';

void main() {
  group('EqPreset', () {
    test('all presets have exactly 10 bands', () {
      for (final preset in EqPreset.values) {
        expect(
          preset.levels.length,
          eqVirtualBandCount,
          reason: '${preset.name} levels length',
        );
        expect(
          preset.levels.every((l) => l >= kEqLevelMin && l <= kEqLevelMax),
          isTrue,
          reason: '${preset.name} levels within range',
        );
      }
    });

    test('preset curves differ from each other', () {
      // `custom` is deliberately flat-by-design (its real curve lives in
      // persisted settings), so it is excluded here and only the stored
      // presets must be mutually distinct.
      final storedPresets = EqPreset.values
          .where((p) => p != EqPreset.custom)
          .toList();
      final labels = storedPresets.map((p) => p.levels.join(',')).toList();
      expect(
        labels.toSet().length,
        storedPresets.length,
        reason: 'stored presets should have distinct levels',
      );
    });

    test('labels are readable and non-empty', () {
      for (final preset in EqPreset.values) {
        expect(preset.label, isNotEmpty);
      }
    });
  });

  group('clampEqLevel', () {
    test('clamps below range', () {
      expect(clampEqLevel(-20.0), kEqLevelMin);
    });
    test('clamps above range', () {
      expect(clampEqLevel(12.0), kEqLevelMax);
    });
    test('keeps valid value', () {
      expect(clampEqLevel(0.0), 0.0);
    });
  });

  group('clampCrossfadeSeconds', () {
    test('clamps below range', () {
      expect(clampCrossfadeSeconds(-5), kCrossfadeSecondsMin);
    });
    test('clamps above range', () {
      expect(clampCrossfadeSeconds(999), kCrossfadeSecondsMax);
    });
    test('keeps valid value', () {
      expect(clampCrossfadeSeconds(5), 5);
    });
  });

  group('clampAudioBalance', () {
    test('clamps below range', () {
      expect(clampAudioBalance(-5.0), -1.0);
    });
    test('clamps above range', () {
      expect(clampAudioBalance(5.0), 1.0);
    });
    test('keeps valid value', () {
      expect(clampAudioBalance(0.0), 0.0);
      expect(clampAudioBalance(-0.5), -0.5);
      expect(clampAudioBalance(0.8), 0.8);
    });
    test('normalizes negative zero', () {
      expect(clampAudioBalance(-0.0), 0.0);
    });
  });

  group('normalizeEqLevels', () {
    test('pads shorter list with zeros', () {
      final result = normalizeEqLevels([3.0, -2.0]);
      expect(result, [3.0, -2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]);
    });
    test('truncates longer list', () {
      final result = normalizeEqLevels([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
      expect(result, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    });
    test('clips out-of-range values', () {
      final result = normalizeEqLevels([99.0, -99.0]);
      expect(result.first, kEqLevelMax);
      expect(result[1], kEqLevelMin);
    });
    test('returns exactly 10 when already correct', () {
      final levels = [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0];
      expect(normalizeEqLevels(levels), levels);
    });
    test('empty list becomes ten zeros', () {
      expect(normalizeEqLevels([]), List.filled(10, 0.0));
    });
  });

  group('mapVirtualCurveToBands', () {
    // A distinct curve over the virtual frequencies, low→high.
    final curve = [6.0, 5.0, 4.0, 3.0, 2.0, 1.0, 0.0, -1.0, -2.0, -3.0];

    test('identity when device bands exactly match virtual bands', () {
      final deviceBands = kEqVirtualBandFrequencies.toList();
      final result = mapVirtualCurveToBands(
        virtualLevels: curve,
        centerFrequencies: deviceBands,
      );
      expect(result.length, deviceBands.length);
      for (var i = 0; i < deviceBands.length; i++) {
        expect(
          result[i],
          closeTo(curve[i], 0.001),
          reason: 'band at ${deviceBands[i]}Hz',
        );
      }
    });

    test('interpolates between virtual bands', () {
      // 750 Hz sits between 500 Hz (2.0) and 1000 Hz (1.0) → ~1.4
      final result = mapVirtualCurveToBands(
        virtualLevels: curve,
        centerFrequencies: [750.0],
      );
      expect(result.length, 1);
      expect(result[0], closeTo(1.4, 0.15));
    });

    test('extrapolates below the lowest virtual band', () {
      // 20 Hz is below the 31 Hz lowest virtual band → flat-pad with curve[0].
      final result = mapVirtualCurveToBands(
        virtualLevels: curve,
        centerFrequencies: [20.0],
      );
      expect(result.length, 1);
      expect(result[0], closeTo(curve.first, 0.001));
    });

    test('extrapolates above the highest virtual band', () {
      final result = mapVirtualCurveToBands(
        virtualLevels: curve,
        centerFrequencies: [20000.0],
      );
      expect(result.length, 1);
      expect(result[0], closeTo(curve.last, 0.001));
    });

    test('clamps to the device supported range', () {
      final result = mapVirtualCurveToBands(
        virtualLevels: [
          99.0,
          99.0,
          99.0,
          99.0,
          99.0,
          99.0,
          99.0,
          99.0,
          99.0,
          99.0,
        ],
        centerFrequencies: [250.0, 4000.0],
        minDb: 0.0,
        maxDb: 5.0,
      );
      for (final v in result) {
        expect(v, lessThanOrEqualTo(5.0));
        expect(v, greaterThanOrEqualTo(0.0));
      }
      expect(result.every((v) => v == 5.0), isTrue);
    });

    test('reads sensible values at three device bands', () {
      final result = mapVirtualCurveToBands(
        virtualLevels: curve,
        centerFrequencies: [300.0, 2500.0, 8000.0],
      );
      expect(result.length, 3);
      // 300 Hz between 250 Hz (3.0) and 500 Hz (2.0) → ~2.7
      expect(result[0], closeTo(2.7, 0.5));
      // 2500 Hz between 2000 Hz (0.0) and 4000 Hz (-1.0) → ~-0.3
      expect(result[1], closeTo(-0.3, 0.5));
      // 8000 Hz is a virtual band exactly → -2.0
      expect(result[2], closeTo(-2.0, 0.2));
    });
  });

  group('PlaybackTransitionMode', () {
    test('label returns readable strings', () {
      expect(PlaybackTransitionMode.crossfade.label, 'Crossfade');
      expect(PlaybackTransitionMode.gapless.label, 'Gapless');
      expect(PlaybackTransitionMode.off.label, 'Off');
    });
  });

  group('kPlaybackSpeeds', () {
    test('offers exactly the five expected speeds', () {
      expect(kPlaybackSpeeds, [0.25, 0.5, 1.0, 1.5, 2.0]);
      expect(kDefaultPlaybackSpeed, 1.0);
    });
  });

  group('EqMode', () {
    test('exposes Simple and Advanced with readable labels', () {
      expect(EqMode.values, [EqMode.simple, EqMode.advanced]);
      expect(EqMode.simple.label, 'Simple');
      expect(EqMode.advanced.label, 'Advanced');
    });
  });

  group('EqQuickControl', () {
    test('every control maps to real band indices', () {
      for (final control in EqQuickControl.values) {
        expect(control.bandIndices, isNotEmpty);
        for (final index in control.bandIndices) {
          expect(index, greaterThanOrEqualTo(0));
          expect(index, lessThan(eqVirtualBandCount));
        }
      }
    });

    test('quick control value averages only its own bands', () {
      final levels = List<double>.filled(eqVirtualBandCount, 0.0);
      levels[0] = 4.0;
      levels[1] = 8.0;
      expect(eqQuickControlValue(levels, EqQuickControl.subBass), 6.0);
      expect(eqQuickControlValue(levels, EqQuickControl.treble), 0.0);
    });

    test('applying a quick control writes to every owned band', () {
      final levels = List<double>.filled(eqVirtualBandCount, 0.0);
      final updated = applyEqQuickControl(levels, EqQuickControl.bass, -6.0);
      for (final index in EqQuickControl.bass.bandIndices) {
        expect(updated[index], -6.0);
      }
      // Untouched bands stay neutral.
      expect(updated[0], 0.0);
      expect(updated[9], 0.0);
    });

    test('quick control clamps out-of-range gains', () {
      final updated = applyEqQuickControl(
        List<double>.filled(eqVirtualBandCount, 0.0),
        EqQuickControl.treble,
        99.0,
      );
      for (final index in EqQuickControl.treble.bandIndices) {
        expect(updated[index], kEqLevelMax);
      }
    });
  });

  group('clipping helpers', () {
    test('maxEqBoostDb reports the loudest positive band', () {
      expect(maxEqBoostDb(List.filled(10, -3.0)), 0.0);
      expect(maxEqBoostDb([1.0, 5.5, -2.0, 0.0, 0, 0, 0, 0, 0, 0]), 5.5);
    });

    test('suggestedPreampDb offsets the loudest boost', () {
      expect(suggestedPreampDb([6.0, 5.0, 0, 0, 0, 0, 0, 0, 0, 0]), -6.0);
      expect(suggestedPreampDb(List.filled(10, -4.0)), 0.0);
      expect(suggestedPreampDb(List.filled(10, 0.0)), 0.0);
    });

    test('effectiveEqLevels returns preset or custom curve', () {
      expect(
        effectiveEqLevels(
          preset: EqPreset.rock,
          customLevels: List.filled(10, 9.0),
        ),
        EqPreset.rock.levels,
      );
      expect(
        effectiveEqLevels(preset: EqPreset.custom, customLevels: [3.0, -3.0]),
        [3.0, -3.0, 0, 0, 0, 0, 0, 0, 0, 0],
      );
    });
  });
}

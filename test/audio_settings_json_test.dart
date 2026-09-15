import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/features/settings/data/settings_models.dart';
import 'package:vora_tube/core/audio/audio_effects.dart';

void main() {
  group('AudioSettings JSON round-trip', () {
    test('default settings serialize and deserialize identically', () {
      const settings = AudioSettings();
      final json = settings.toJson();
      final restored = AudioSettingsJson.fromJson(json);
      expect(restored.replayGain, ReplayGainPreference.off);
      expect(restored.preampDb, 0.0);
      expect(restored.eqEnabled, false);
      expect(restored.eqPreset, EqPreset.flat);
      expect(restored.eqCustomLevels, List.filled(10, 0.0));
      expect(restored.playbackSpeed, kDefaultPlaybackSpeed);
      expect(restored.transitionMode, PlaybackTransitionMode.crossfade);
      expect(restored.crossfadeSeconds, kDefaultCrossfadeSeconds);
      expect(restored.audioBalance, kDefaultAudioBalance);
    });

    test('all new fields survive round-trip', () {
      const settings = AudioSettings(
        replayGain: ReplayGainPreference.track,
        preampDb: -5.5,
        eqEnabled: true,
        eqPreset: EqPreset.rock,
        eqCustomLevels: [3.0, -1.0, 2.5, 0.0, 4.0, -2.0, 1.0, 3.5, -0.5, 2.0],
        playbackSpeed: 2.0,
        transitionMode: PlaybackTransitionMode.gapless,
        crossfadeSeconds: 6,
        audioBalance: 0.75,
      );
      final json = settings.toJson();
      final restored = AudioSettingsJson.fromJson(json);

      expect(restored.eqEnabled, true);
      expect(restored.eqPreset, EqPreset.rock);
      expect(
        restored.eqCustomLevels,
        [3.0, -1.0, 2.5, 0.0, 4.0, -2.0, 1.0, 3.5, -0.5, 2.0],
      );
      expect(restored.playbackSpeed, 2.0);
      expect(restored.transitionMode, PlaybackTransitionMode.gapless);
      expect(restored.crossfadeSeconds, 6);
      expect(restored.audioBalance, 0.75);
    });

    test('missing new fields deserialize to defaults', () {
      const legacyJson = '{"replayGain": "off", "preampDb": 3.0}';
      final restored = AudioSettingsJson.fromJson(legacyJson);
      expect(restored.eqEnabled, false);
      expect(restored.eqPreset, EqPreset.flat);
      expect(restored.eqCustomLevels, List.filled(10, 0.0));
      expect(restored.playbackSpeed, kDefaultPlaybackSpeed);
      expect(restored.transitionMode, PlaybackTransitionMode.crossfade);
      expect(restored.crossfadeSeconds, kDefaultCrossfadeSeconds);
      expect(restored.audioBalance, kDefaultAudioBalance);
    });

    test('unknown or future keys are ignored safely', () {
      const settings = AudioSettings(eqEnabled: true);
      final withFutureKeys = settings.toJson().replaceFirst(
        '}',
        ', "futureField": "futureValue", "anotherFuture": 42}',
      );
      final restored = AudioSettingsJson.fromJson(withFutureKeys);
      expect(restored.eqEnabled, true);
      expect(restored.transitionMode, PlaybackTransitionMode.crossfade);
    });

    test('invalid JSON falls back to defaults', () {
      final restored = AudioSettingsJson.fromJson('not json at all');
      expect(restored.eqEnabled, false);
      expect(restored.eqPreset, EqPreset.flat);
      expect(restored.eqCustomLevels, List.filled(10, 0.0));
      expect(restored.playbackSpeed, kDefaultPlaybackSpeed);
    });

    test('crossfade string containing other numbers does not confuse parsing', () {
      const settings = AudioSettings(
        audioBalance: -0.5,
        playbackSpeed: 0.5,
        preampDb: -3.0,
        crossfadeSeconds: 10,
      );
      final restored = AudioSettingsJson.fromJson(settings.toJson());
      expect(restored.preampDb, -3.0);
      expect(restored.playbackSpeed, 0.5);
      expect(restored.audioBalance, -0.5);
      expect(restored.crossfadeSeconds, 10);
    });
  });

  group('AudioSettings equality', () {
    test('identical settings are equal', () {
      const a = AudioSettings(eqEnabled: true, playbackSpeed: 1.5);
      const b = AudioSettings(eqEnabled: true, playbackSpeed: 1.5);
      expect(a, b);
    });

    test('different settings are not equal', () {
      const a = AudioSettings(eqEnabled: true);
      const b = AudioSettings(eqEnabled: false);
      expect(a == b, false);
    });

    test('different crossfade durations are not equal', () {
      const a = AudioSettings(crossfadeSeconds: 4);
      const b = AudioSettings(crossfadeSeconds: 8);
      expect(a == b, false);
    });
  });
}
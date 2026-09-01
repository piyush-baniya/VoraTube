import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/core/player/just_audio_controller.dart';

void main() {
  group('QueueSnapshot JSON round-trip', () {
    test('preserves all fields', () {
      const snapshot = QueueSnapshot(
        identityKeys: ['ms:1', 'h:abc', 'ms:42'],
        index: 2,
        positionMs: 95000,
        shuffleEnabled: true,
        repeatMode: RepeatMode.one,
      );

      final restored = QueueSnapshot.fromJson(snapshot.toJson());

      expect(restored.identityKeys, snapshot.identityKeys);
      expect(restored.index, 2);
      expect(restored.positionMs, 95000);
      expect(restored.shuffleEnabled, isTrue);
      expect(restored.repeatMode, RepeatMode.one);
    });

    test('repeat modes map through all values', () {
      for (final mode in RepeatMode.values) {
        final s = QueueSnapshot(
          identityKeys: const ['k'],
          index: 0,
          positionMs: 0,
          shuffleEnabled: false,
          repeatMode: mode,
        );
        expect(QueueSnapshot.fromJson(s.toJson()).repeatMode, mode);
      }
    });

    test('empty snapshot serializes and detects emptiness', () {
      const empty = QueueSnapshot.empty();
      expect(empty.isEmpty, isTrue);
      expect(QueueSnapshot.fromJson(empty.toJson()).isEmpty, isTrue);
    });

    test('malformed or future-version payloads degrade to empty', () {
      expect(QueueSnapshot.fromJson('not json').isEmpty, isTrue);
      expect(QueueSnapshot.fromJson('{"v":99,"keys":["a"]}').isEmpty, isTrue);
      // Version 1 but missing the required key list.
      expect(QueueSnapshot.fromJson('{"v":1}').isEmpty, isTrue);
      expect(QueueSnapshot.fromJson('{"v":1,"keys":["a"]}').isEmpty, isFalse);
    });
  });

  group('clampResumeMs (restored-position safety)', () {
    test('keeps a normal mid-track position', () {
      // e.g. user paused at 2:37 (157s) in a 4:12 song.
      expect(clampResumeMs(157000, 252000), 157000);
    });

    test('clamps a negative saved position to zero', () {
      expect(clampResumeMs(-5, 252000), 0);
    });

    test('restarts a position at/after the known duration from zero', () {
      // Persist raced a natural completion: position == duration.
      expect(clampResumeMs(252000, 252000), 0);
      expect(clampResumeMs(300000, 252000), 0);
    });

    test('keeps the saved value when the duration is unknown', () {
      expect(clampResumeMs(157000, 0), 157000);
    });

    test('zero position stays zero', () {
      expect(clampResumeMs(0, 252000), 0);
    });
  });
}

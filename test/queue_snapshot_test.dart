import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/player/player_controller.dart';

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
}

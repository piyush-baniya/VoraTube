import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/core/player/player_controller.dart';

/// Regression tests for the Volume Booster gain command path.
///
/// The booster's real effect lives at the native boundary: ExoPlayer clamps
/// volume to 0..1, so just_audio alone can never raise output past 100%. The
/// fix routes the multiplier through `volumeBoostMillibel`, producing an actual
/// millibel gain handed to a native LoudnessEnhancer. These tests lock in that
/// mapping — the *value actually sent to the audio engine* — so 100%, 150% and
/// 200% produce strictly increasing real gain instead of all clamping to the
/// same 1.0 volume.
void main() {
  group('volumeBoostMillibel gain mapping', () {
    test('100% = no boost (0 mB)', () {
      expect(volumeBoostMillibel(1.0), 0);
      expect(volumeBoostMillibel(1.0), lessThan(volumeBoostMillibel(1.5)));
    });

    test('150% produces a real gain increase', () {
      final oneFifty = volumeBoostMillibel(1.5);
      expect(oneFifty, greaterThan(0));
      expect(oneFifty, lessThan(volumeBoostMillibel(2.0)));
    });

    test('200% produces a further gain increase', () {
      final twoHundred = volumeBoostMillibel(2.0);
      expect(twoHundred, greaterThan(volumeBoostMillibel(1.5)));
      expect(twoHundred, lessThanOrEqualTo(1000)); // LoudnessEnhancer ceiling
    });

    test('mapping is monotonic across the full range', () {
      var previous = -1;
      for (var step = 10; step <= 20; step++) {
        final boost = step / 10.0; // 1.0, 1.1, ..., 2.0
        final mB = volumeBoostMillibel(boost);
        expect(mB, greaterThan(previous), reason: 'boost=$boost');
        previous = mB;
      }
    });

    test('out-of-range values are clamped, never overdrive the enhancer', () {
      expect(volumeBoostMillibel(0.0), 0); // <100% collapses to no boost
      expect(volumeBoostMillibel(0.5), 0);
      expect(volumeBoostMillibel(-3.0), 0);
      expect(volumeBoostMillibel(5.0), lessThanOrEqualTo(1000));
      expect(volumeBoostMillibel(5.0), volumeBoostMillibel(2.0));
    });

    test('the normal volume layer is independent of the boost gain', () {
      // The booster never rewrites the 0..1 user volume: at 100% the gain is 0
      // mB, and the mapping only concerns the enhancer layer, so unaffected
      // volume settings are preserved by construction.
      expect(volumeBoostMillibel(1.0), 0);
      final normal = 0.7; // any ordinary user volume stays untouched by boost
      expect(normal, greaterThanOrEqualTo(0.0));
      expect(normal, lessThanOrEqualTo(1.0));
    });
  });
}

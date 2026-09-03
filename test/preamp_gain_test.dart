import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/core/player/player_controller.dart';

/// Regression tests for the Preamp gain command path.
///
/// A positive Preamp is real gain above the 0..1 volume clamp that ExoPlayer
/// enforces — before this fix `+6 dB` produced `gainMultiplier = 10^(6/20) ≈
/// 1.995` which was then clamped to `1.0`, so it changed nothing audibly. The
/// fix routes the positive Preamp through the native loudness enhancer. These
/// tests lock in the exact millibel value handed to that enhancer, so
/// 0 / +3 / +6 dB produce strictly increasing real gain.
void main() {
  group('preampBoostMillibel gain mapping', () {
    test('0 dB = no boost (0 mB)', () {
      expect(preampBoostMillibel(0.0), 0);
      expect(preampBoostMillibel(0.0), lessThan(preampBoostMillibel(3.0)));
    });

    test('+3 dB produces a real gain increase', () {
      final threeDb = preampBoostMillibel(3.0);
      expect(threeDb, greaterThan(0));
      expect(threeDb, lessThan(preampBoostMillibel(6.0)));
    });

    test('+6 dB produces a further gain increase', () {
      final sixDb = preampBoostMillibel(6.0);
      expect(sixDb, greaterThan(preampBoostMillibel(3.0)));
    });

    test('mapping is monotonic across the positive range', () {
      var previous = -1;
      for (var db = 0.0; db <= 12.0; db += 0.5) {
        final mB = preampBoostMillibel(db);
        expect(mB, greaterThan(previous), reason: 'preamp=$db dB');
        previous = mB;
      }
    });

    test(
      'negative and zero Preamp attenuate via volume (0 mB to enhancer)',
      () {
        // The enhancer cannot attenuate, so negative values must not push a
        // positive enhancer gain; they reduce gain through the clamped base
        // volume instead.
        expect(preampBoostMillibel(-3.0), 0);
        expect(preampBoostMillibel(-12.0), 0);
        expect(preampBoostMillibel(0.0), 0);
      },
    );

    test('positive Preamp maps linearly on the enhancer', () {
      // Preamp is the only gain layer on the native enhancer; the millibel
      // value is authoritative for the bridge, which caps at the enhancer's
      // 1000 mB ceiling.
      expect(preampBoostMillibel(6.0), 600);
      expect(preampBoostMillibel(3.0), 300);
      expect(preampBoostMillibel(6.0), greaterThan(preampBoostMillibel(3.0)));
    });

    test('out-of-range Preamp is clamped, never overdrives the enhancer', () {
      expect(preampBoostMillibel(20.0), preampBoostMillibel(12.0));
      expect(preampBoostMillibel(12.0), 1200);
      expect(preampBoostMillibel(-99.0), 0);
    });
  });
}

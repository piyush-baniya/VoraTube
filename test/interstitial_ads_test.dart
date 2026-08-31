import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/features/ads/interstitial_ad_service.dart';
import 'package:vora_tube/features/ads/interstitial_ads_provider.dart';

class _FakeService extends InterstitialAdService {
  int loadCalls = 0;
  int showCalls = 0;
  bool ready = false;

  @override
  void load() {
    loadCalls++;
    ready = true;
  }

  @override
  bool get hasAdReady => ready;

  @override
  Future<bool> show() async {
    showCalls++;
    ready = false;
    return true;
  }

  @override
  void dispose() {}
}

void main() {
  group('InterstitialAdController', () {
    test('presents an ad once the fixed threshold of songs is reached',
        () async {
      final service = _FakeService();
      final controller = InterstitialAdController(
        isPremium: () => false,
        service: service,
      );
      // Constructor warms up one ad.
      controller.debugSetThreshold(3);

      controller.onTrackStarted(); // 1
      controller.onTrackStarted(); // 2
      expect(service.showCalls, 0);

      controller.onTrackStarted(); // 3 -> threshold crossed, ad shown
      expect(service.showCalls, 1);

      // Allow the trailing async reload to settle.
      await Future<void>.delayed(Duration.zero);
      expect(service.loadCalls, greaterThanOrEqualTo(2)); // warm-up + reload

      // Counter resets: the next ad needs another 3 songs.
      controller.debugSetThreshold(3);
      controller.onTrackStarted();
      controller.onTrackStarted();
      controller.onTrackStarted();
      expect(service.showCalls, 2);
    });

    test('does not present when the ad is not ready', () {
      final service = _FakeService()..ready = false;
      // Prevent the warm-up load from marking it ready.
      // (load sets ready=true, so re-arm with a service that stays unready.)
      final idle = _IdleService();
      final controller = InterstitialAdController(
        isPremium: () => false,
        service: idle,
      );
      controller.debugSetThreshold(1);
      controller.onTrackStarted();
      expect(idle.showCalls, 0);
      expect(idle.loadCalls, greaterThanOrEqualTo(2));
    });

    test('never shows ads while premium is active', () {
      final service = _FakeService();
      var premium = true;
      final controller = InterstitialAdController(
        isPremium: () => premium,
        service: service,
      );
      controller.debugSetThreshold(1);

      controller.onTrackStarted();
      controller.onTrackStarted();
      expect(service.showCalls, 0);
    });
  });
}

class _IdleService extends InterstitialAdService {
  int loadCalls = 0;
  int showCalls = 0;

  @override
  void load() {
    loadCalls++;
  }

  @override
  bool get hasAdReady => false;

  @override
  Future<bool> show() async {
    showCalls++;
    return false;
  }

  @override
  void dispose() {}
}

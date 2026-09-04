import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/features/ads/interstitial_ad_service.dart';
import 'package:vora_tube/features/ads/interstitial_ads_provider.dart';

class _FakeService extends InterstitialAdService {
  int loadCalls = 0;
  int showCalls = 0;
  int disposeCalls = 0;
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
  void dispose() {
    disposeCalls++;
    ready = false;
  }
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
      // A service that stays unready: its load() never marks it ready.
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
      const premium = true;
      final controller = InterstitialAdController(
        isPremium: () => premium,
        service: service,
      );
      // Premium must not generate ad traffic at startup either: no warm-up
      // load, no request to AdMob.
      expect(service.loadCalls, 0);
      controller.debugSetThreshold(1);

      controller.onTrackStarted();
      controller.onTrackStarted();
      expect(service.showCalls, 0);
    });

    test('premium activation disposes the cached ad and skips further loads',
        () {
      final service = _FakeService();
      var premium = false;
      final controller = InterstitialAdController(
        isPremium: () => premium,
        service: service,
      );
      // Non-premium constructor warmed up one ad.
      expect(service.loadCalls, 1);

      premium = true;
      controller.onPremiumChanged(true);
      expect(service.disposeCalls, 1);

      // Even after threshold crossings, nothing is loaded or shown.
      controller.debugSetThreshold(1);
      controller.onTrackStarted();
      expect(service.loadCalls, 1);
      expect(service.showCalls, 0);
    });

    test('premium deactivation re-primes the ad cache', () {
      final service = _FakeService()..ready = false;
      var premium = true;
      final controller = InterstitialAdController(
        isPremium: () => premium,
        service: service,
      );
      expect(service.loadCalls, 0); // no startup load while premium

      premium = false;
      controller.onPremiumChanged(false);
      expect(service.loadCalls, 1); // cache re-primed for next threshold
    });

    test('shows an ad on every third skip click', () async {
      final service = _FakeService();
      final controller = InterstitialAdController(
        isPremium: () => false,
        service: service,
      );
      controller.debugSetThreshold(999); // keep the song-count path quiet

      controller.onSkipClicked(); // 1
      controller.onSkipClicked(); // 2
      expect(service.showCalls, 0);

      controller.onSkipClicked(); // 3 -> ad
      // Let the trailing async reload settle before the next trigger.
      await Future<void>.delayed(Duration.zero);
      expect(service.showCalls, 1);

      // Counter reset: two more clicks do not fire; the third does.
      controller.onSkipClicked(); // 1
      controller.onSkipClicked(); // 2
      expect(service.showCalls, 1);
      controller.onSkipClicked(); // 3 -> ad
      expect(service.showCalls, 2);
    });

    test('never fires skip-triggered ads while premium is active', () {
      final service = _FakeService();
      final controller = InterstitialAdController(
        isPremium: () => true,
        service: service,
      );
      for (var i = 0; i < 10; i++) {
        controller.onSkipClicked();
      }
      expect(service.showCalls, 0);
      expect(service.loadCalls, 0);
    });

    test('showOnTrigger warms up instead of blocking when no ad is ready', () {
      final idle = _IdleService();
      final controller = InterstitialAdController(
        isPremium: () => false,
        service: idle,
      );
      controller.debugSetThreshold(999);
      // Trigger with nothing cached (beyond the constructor's warm-up, which
      // this idle fake never fulfils): must load for next time, never show.
      controller.showOnTrigger();
      expect(idle.showCalls, 0);
      expect(idle.loadCalls, 2); // constructor warm-up + trigger reload
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

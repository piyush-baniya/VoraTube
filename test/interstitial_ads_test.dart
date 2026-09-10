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
    test(
      'presents an interstitial on exactly the 5th, 10th, … song start',
      () async {
        final service = _FakeService();
        final controller = InterstitialAdController(
          isPremium: () => false,
          service: service,
        );
        // Constructor warms up one ad.
        expect(service.loadCalls, 1);

        for (var i = 0; i < 4; i++) {
          controller.onTrackStarted();
        }
        expect(service.showCalls, 0);

        controller.onTrackStarted(); // 5th distinct track -> ad
        expect(service.showCalls, 1);
        // Let the trailing async reload land before the next batch crosses a
        // threshold (mirrors the real gap between two songs).
        await Future<void>.delayed(Duration.zero);

        for (var i = 0; i < 4; i++) {
          controller.onTrackStarted();
        }
        expect(service.showCalls, 1);

        controller.onTrackStarted(); // 10th distinct track -> second ad
        expect(service.showCalls, 2);

        // Allow the trailing async reloads to settle.
        await Future<void>.delayed(Duration.zero);
        // warm-up + reload after each show.
        expect(service.loadCalls, greaterThanOrEqualTo(3));
      },
    );

    test('banner placements stay locked until the 30-song milestone, then '
        'stay eligible (shared monotonic counter)', () async {
      final service = _FakeService();
      final controller = InterstitialAdController(
        isPremium: () => false,
        service: service,
      );

      // 29 distinct starts: still not banner-eligible (and interstitials
      // fired on the way, proving the milestone shares the song counter).
      for (var i = 0; i < 29; i++) {
        controller.onTrackStarted();
        // Each threshold crossing reloads asynchronously; settle it so the
        // next one can show (as the real seconds-long gap between songs does).
        if (controller.plays % InterstitialAdController.songInterval == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      expect(controller.plays, 29);
      expect(controller.bannerEligible, isFalse);
      expect(service.showCalls, 5); // 5, 10, 15, 20, 25

      controller.onTrackStarted(); // 30 -> milestone reached
      expect(controller.plays, 30);
      expect(controller.bannerEligible, isTrue);
      expect(service.showCalls, 6); // and the 30th also crosses an interval
      await Future<void>.delayed(Duration.zero);

      // Monotonic: the milestone is never re-locked past 30.
      for (var i = 0; i < 10; i++) {
        controller.onTrackStarted();
        if (controller.plays % InterstitialAdController.songInterval == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      expect(controller.plays, 40);
      expect(controller.bannerEligible, isTrue);
    });

    test('does not present when the ad is not ready (non-blocking)', () {
      // A service that stays unready: its load() never marks it ready.
      final idle = _IdleService();
      final controller = InterstitialAdController(
        isPremium: () => false,
        service: idle,
      );
      controller.debugSetInterval(1);
      controller.onTrackStarted(); // 1st song -> threshold, no ad cached
      expect(idle.showCalls, 0);
      expect(idle.loadCalls, greaterThanOrEqualTo(2));
      expect(controller.plays, 1);
    });

    test('premium never counts songs nor shows ads (and skips the startup '
        'warm-up load)', () {
      final service = _FakeService();
      const premium = true;
      final controller = InterstitialAdController(
        isPremium: () => premium,
        service: service,
      );
      // Premium must not generate ad traffic at startup either: no warm-up
      // load, no request to AdMob.
      expect(service.loadCalls, 0);

      for (var i = 0; i < 10; i++) {
        controller.onTrackStarted();
      }
      expect(controller.plays, 0);
      expect(controller.bannerEligible, isFalse);
      expect(service.showCalls, 0);
      expect(service.loadCalls, 0);
    });

    test('premium activation disposes the cached ad and stops the counter', () {
      final service = _FakeService();
      var premium = false;
      final controller = InterstitialAdController(
        isPremium: () => premium,
        service: service,
      );
      // Non-premium constructor warmed up one ad.
      expect(service.loadCalls, 1);
      controller.debugSetInterval(999);
      for (var i = 0; i < 4; i++) {
        controller.onTrackStarted();
      }
      expect(controller.plays, 4);

      premium = true;
      controller.onPremiumChanged(true);
      expect(service.disposeCalls, 1);

      // Song starts no longer count while premium, so nothing loads or shows.
      controller.onTrackStarted();
      controller.onTrackStarted();
      expect(controller.plays, 4);
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

    test('showOnTrigger warms up instead of blocking when no ad is ready', () {
      final idle = _IdleService();
      final controller = InterstitialAdController(
        isPremium: () => false,
        service: idle,
      );
      controller.debugSetInterval(999);
      // Trigger with nothing cached (beyond the constructor's warm-up, which
      // this idle fake never fulfils): must load for next time, never show.
      controller.showOnTrigger();
      expect(idle.showCalls, 0);
      expect(idle.loadCalls, 2); // constructor warm-up + trigger reload
    });

    test('showOnTrigger shows a cached ad and primes the next one', () async {
      final service = _FakeService();
      final controller = InterstitialAdController(
        isPremium: () => false,
        service: service,
      );
      controller.debugSetInterval(999);
      await controller.showOnTrigger();
      expect(service.showCalls, 1);
      // Loaded a replacement for the next trigger (which the earlier
      // await-based show already primed).
      expect(service.loadCalls, greaterThanOrEqualTo(2));
    });

    test('debugSetInterval retunes the ad interval (test seam)', () async {
      final service = _FakeService();
      final controller = InterstitialAdController(
        isPremium: () => false,
        service: service,
      );
      controller.debugSetInterval(2);

      controller.onTrackStarted();
      expect(service.showCalls, 0);
      controller.onTrackStarted(); // 2nd -> ad
      expect(service.showCalls, 1);
      await Future<void>.delayed(Duration.zero); // reload lands
      controller.onTrackStarted();
      controller.onTrackStarted(); // 4th -> second ad
      expect(service.showCalls, 2);
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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'interstitial_ad_service.dart';
import 'premium_providers.dart';

/// Counts songs as they *actually* start playing and, every
/// [InterstitialAdController.songInterval] distinct track starts (Premium
/// off), presents a full-screen interstitial ad before continuing to count.
/// Premium suppresses ads entirely.
///
/// The same monotonic counter also unlocks the always-visible banner
/// placements (Library/detail pages, home, playlists, search, settings) once
/// [InterstitialAdController.bannerPlayThreshold] songs have been played, so a
/// single counter drives every ad milestone and nothing is double-counted.
class InterstitialAdController extends ChangeNotifier {
  InterstitialAdController({
    required this.isPremium,
    InterstitialAdService? service,
  }) : _service = service ?? InterstitialAdService() {
    // Premium users must never generate ad traffic: skip the warm-up load
    // entirely so no request is sent to AdMob at startup (a disposed/hidden
    // view alone would still have burned the request — and the bandwidth).
    if (!isPremium()) _service.load();
  }

  final bool Function() isPremium;
  final InterstitialAdService _service;

  /// Songs played between interstitials. The ad fires on exactly the 5th,
  /// 10th, 15th, … distinct track start.
  static const int songInterval = 5;

  /// Songs played before the always-visible banner ads may render.
  static const int bannerPlayThreshold = 30;

  /// Test seam interval (defaults to [songInterval]); only tuned by tests.
  int _interval = songInterval;

  /// Monotonic count of distinct track starts since the session began. Never
  /// reset per-ad, so the banner milestone keeps counting past the interstitials.
  int _plays = 0;
  int get plays => _plays;

  /// Whether the always-visible banners (Library/detail pages) may render.
  bool get bannerEligible => _plays >= bannerPlayThreshold;

  /// Reacts to Premium activation/deactivation.
  ///
  /// * Activating Premium disposes any cached interstitial so its resources are
  ///   released immediately (its request was already spent — it can't be
  ///   unsent — but it must never be shown).
  /// * Deactivating Premium re-primes the cache so the next threshold crossing
  ///   has an ad ready.
  void onPremiumChanged(bool premium) {
    if (premium) {
      _service.dispose();
    } else if (!_service.hasAdReady) {
      _service.load();
    }
  }

  /// Called whenever a distinct track has actually started playing.
  void onTrackStarted() {
    // Premium never shows ads; leave the counter at zero so a later downgrade
    // cannot fire an ad immediately off the back of the old session.
    if (isPremium()) return;
    _plays++;
    notifyListeners();
    if (_plays % _interval == 0) {
      unawaited(_present());
    }
  }

  /// Presents an interstitial for a user-action trigger: opening a playlist or
  /// a smart mix, opening the ringtone cutter, or successfully setting a
  /// ringtone. If no ad is cached, warms one up for the next trigger instead of
  /// blocking the user's action on a load.
  Future<void> showOnTrigger() async {
    if (isPremium()) return;
    if (!_service.hasAdReady) {
      _service.load();
      return;
    }
    await _service.show();
    // Prepare the next interstitial for the subsequent trigger.
    _service.load();
  }

  Future<void> _present() async {
    if (isPremium()) return;
    if (!_service.hasAdReady) {
      // Not loaded yet (or last load failed): warm it up and try next time.
      _service.load();
      return;
    }
    await _service.show();
    // Prepare the next interstitial for the subsequent threshold crossing.
    _service.load();
  }

  /// Test seam: replaces the fixed song interval.
  @visibleForTesting
  void debugSetInterval(int interval) {
    _interval = interval;
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}

/// The single authoritative ad controller. Watched from the app root so it
/// stays alive for the whole session. The engine (not the media-item stream)
/// drives [InterstitialAdController.onTrackStarted], so restores, rebuilds and
/// resume-only events never count a play.
final interstitialAdControllerProvider =
    ChangeNotifierProvider<InterstitialAdController>((ref) {
      final controller = InterstitialAdController(
        isPremium: () => ref.read(isPremiumProvider),
      );
// Keep the interstitial cache in sync with Premium: dispose the cached ad on
  // activation, re-prime on deactivation.
  ref.listen<bool>(isPremiumProvider, (previous, next) {
    if (next != previous) controller.onPremiumChanged(next);
  });
  return controller;
});

/// Whether the always-visible banner placements may render yet, derived from
/// the same monotonic song counter the interstitials use.
final bannerEligibleProvider = Provider<bool>((ref) {
  return ref.watch(interstitialAdControllerProvider).bannerEligible;
});

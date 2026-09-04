import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/presentation/providers/player_providers.dart';
import 'interstitial_ad_service.dart';
import 'premium_providers.dart';

/// Counts songs as they start playing and, when the count crosses a 10–15 song
/// threshold (Premium off), presents a full-screen interstitial ad before
/// resetting the count. Premium suppresses ads entirely.
class InterstitialAdController {
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
  final Random _random = Random();
  int _count = 0;
  late int _threshold = _randomThreshold();

  int _randomThreshold() => 10 + _random.nextInt(6); // 10..15 inclusive

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

  /// Called whenever a distinct track has started playing.
  void onTrackStarted() {
    // Premium never shows ads; leave the counter at zero so a later downgrade
    // cannot fire an ad immediately off the back of the old session.
    if (isPremium()) return;
    if (++_count < _threshold) return;

    _count = 0;
    _threshold = _randomThreshold();
    unawaited(_present());
  }

  /// Manual skip (next/previous) click counter: an interstitial is presented
  /// every [_skipAdInterval] clicks.
  int _skipCount = 0;
  static const int _skipAdInterval = 3;

  /// Called when the user taps next or previous in the player. Every third
  /// click presents an interstitial (Premium off).
  void onSkipClicked() {
    if (isPremium()) return;
    if (++_skipCount < _skipAdInterval) return;
    _skipCount = 0;
    unawaited(showOnTrigger());
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

  /// Test seam: replaces the random threshold with a fixed value.
  @visibleForTesting
  void debugSetThreshold(int threshold) {
    _threshold = threshold;
    _count = 0;
  }

  void dispose() {
    _service.dispose();
  }
}

/// The single authoritative interstitial controller. Watched from the app root
/// so it stays alive for the whole session; it listens for track identity
/// changes and triggers the ad when appropriate.
final interstitialAdControllerProvider = Provider<InterstitialAdController>((
  ref,
) {
  final controller = InterstitialAdController(
    isPremium: () => ref.read(isPremiumProvider),
  );
  ref.listen<String?>(currentTrackIdentityProvider, (previous, next) {
    if (next != null && next != previous) {
      controller.onTrackStarted();
    }
  });
  // Keep the interstitial cache in sync with Premium: dispose the cached ad on
  // activation, re-prime on deactivation.
  ref.listen<bool>(isPremiumProvider, (previous, next) {
    if (next != previous) controller.onPremiumChanged(next);
  });
  ref.onDispose(controller.dispose);
  return controller;
});

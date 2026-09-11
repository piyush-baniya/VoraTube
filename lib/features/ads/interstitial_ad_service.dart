import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_config.dart';

/// Loads and shows a full-screen interstitial ad, gated by VoraTube's Premium
/// state.
///
/// An interstitial is loaded ahead of time so it is ready the moment the user
/// crosses the song threshold; if none is ready it is simply skipped — an
/// intermission that fails to load must never interrupt playback.
///
/// Lifecycle is made observable via [debugPrint] so ad-region issues (wrong
/// unit ID, wrong app ID, no fill) are visible without shipping a debug screen.
class InterstitialAdService {
  InterstitialAd? _interstitial;
  bool _loading = false;

  bool get hasAdReady => _interstitial != null;

  /// Loads the next interstitial if none is cached. Loading is best-effort and
  /// never throws; failures simply leave the cache empty so [show] skips.
  void load() {
    if (_interstitial != null || _loading) return;

    final adUnitId = VoraTubeAds.interstitialAndroidId;
    debugPrint('VoraTubeAds: interstitial load requested (unit $adUnitId)');
    _loading = true;
    InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loading = false;
          _interstitial = ad;
          debugPrint('VoraTubeAds: interstitial loaded ($adUnitId)');
        },
        onAdFailedToLoad: (error) {
          _loading = false;
          _interstitial?.dispose();
          _interstitial = null;
          debugPrint(
            'VoraTubeAds: interstitial load FAILED ($adUnitId) -> '
            '${error.code} ${error.message}',
          );
        },
      ),
    );
  }

  /// Shows the cached interstitial if one is ready. The ad is always consumed
  /// (shown or invalidated) so a subsequent call triggers a fresh load.
  ///
  /// Returns whether an ad was actually presented.
  Future<bool> show() async {
    final ad = _interstitial;
    _interstitial = null;
    if (ad == null) {
      debugPrint(
        'VoraTubeAds: interstitial show SKIPPED (no ad cached; '
        'premium off, threshold crossed, but nothing was ready)',
      );
      return false;
    }

    var presented = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('VoraTubeAds: interstitial dismissed');
        ad.dispose();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint(
          'VoraTubeAds: interstitial show FAILED -> ${error.code} '
          '${error.message}',
        );
        ad.dispose();
        presented = false;
      },
    );
    try {
      debugPrint('VoraTubeAds: interstitial shown');
      await ad.show();
    } catch (_) {
      ad.dispose();
      return false;
    }
    return presented;
  }

  void dispose() {
    _interstitial?.dispose();
    _interstitial = null;
  }
}

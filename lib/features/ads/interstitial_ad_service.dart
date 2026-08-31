import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_config.dart';

/// Loads and shows a full-screen interstitial ad, gated by VoraTube's Premium
/// state.
///
/// An interstitial is loaded ahead of time so it is ready the moment the user
/// crosses the song threshold; if none is ready it is simply skipped — an
/// intermission that fails to load must never interrupt playback.
class InterstitialAdService {
  InterstitialAd? _interstitial;
  bool _loading = false;

  bool get hasAdReady => _interstitial != null;

  /// Loads the next interstitial if none is cached. Loading is best-effort and
  /// never throws; failures simply leave the cache empty so [show] skips.
  void load() {
    if (_interstitial != null || _loading) return;

    final adUnitId = VoraTubeAds.interstitialAndroidId;
    _loading = true;
    InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loading = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (error) {
          _loading = false;
          _interstitial?.dispose();
          _interstitial = null;
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
    if (ad == null) return false;

    var presented = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) => ad.dispose(),
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        presented = false;
      },
    );
    try {
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

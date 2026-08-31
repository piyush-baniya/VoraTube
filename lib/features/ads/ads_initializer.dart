import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_config.dart';

/// Fires up the Google Mobile Ads SDK once, early in the app's life, so the
/// first banner can load without a cold-start delay.
///
/// Initialization is intentionally fire-and-forget and never blocks the UI: if
/// it fails or the SDK is unavailable, the app keeps working and ad placements
/// simply show no ad. When Premium is already active at launch, [initialize]
/// is skipped and no ad request is made at all.
class AdsInitializer {
  static bool _initialized = false;

  /// Initializes the SDK exactly once per process, only when Premium is off
  /// ([premiumActive] false) and the platform supports mobile ads.
  ///
  /// This is called from the app startup path, after the provider container
  /// exists, so [premiumActive] reflects the persisted entitlement.
  static Future<void> initialize({required bool premiumActive}) async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb) return;

    if (premiumActive) {
      // Premium is already active — do not request or load any ads.
      return;
    }

    // Best-effort, non-blocking. The SDK degrades gracefully on unsupported
    // platforms and failures here must never break the music player.
    try {
      await MobileAds.instance.initialize();
    } catch (_) {
      // Initialization failure is non-fatal.
    }
  }
}

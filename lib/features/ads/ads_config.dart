/// Centralized AdMob configuration for VoraTube.
///
/// All ad-unit IDs live here, in one place, so they can be swapped between the
/// Google test units used during development and VoraTube's real production
/// units before a Google Play release — without touching any of the ad
/// placements.
///
/// During development VoraTube intentionally ships with Google's official
/// *test* ad units (see `useTestAds` and [VoraTubeAds.testBannerAndroidId]).
/// A release APK must NOT switch to live ads automatically: it stays on test
/// ads until the production IDs below are filled in explicitly.
library;

abstract final class VoraTubeAds {
  VoraTubeAds._();

  /// When true (the development default), placements use Google's official
  /// test ad units. Flip this (and fill in the production IDs) only when the
  /// real VoraTube AdMob account is ready.
  static const bool useTestAds = true;

  // ── Production ad-unit IDs (currently the test placeholders) ────────────
  // Replace only these two values before production release:
  //   1. Set `useTestAds` to false.
  //   2. Put VoraTube's real ad-unit IDs in the appId / banner fields below.
  // No ad-placement code needs to change.

  /// The AdMob app identifier (from the AdMob console).
  static const String productionAppId =
      'ca-app-pub-3940256099942544~3347511713';

  /// The production banner ad-unit ID.
  static const String productionBannerAndroidId =
      'ca-app-pub-3940256099942544/9214589741';

  // ── Google official test ad units ────────────────────────────────────────
  static const String testAppId = 'ca-app-pub-3940256099942544~3347511713';

  /// Google's official Android banner test ad unit.
  static const String testBannerAndroidId =
      'ca-app-pub-3940256099942544/9214589741';

  /// The AdMob app ID passed to `MobileAds.instance.initialize()`.
  static String get appId => useTestAds ? testAppId : productionAppId;

  /// The banner ad-unit ID used by Android placements.
  static String get bannerAndroidId =>
      useTestAds ? testBannerAndroidId : productionBannerAndroidId;
}

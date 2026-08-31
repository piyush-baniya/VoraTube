import 'package:meta/meta.dart';

/// Single source of truth for every VoraTube update destination.
///
/// ⚠️ IMPORTANT — THERE IS NO REAL DISTRIBUTION URL IN THIS REPOSITORY.
/// VoraTube is currently distributed by the developer as an APK directly, and
/// no public website/host URL is referenced anywhere in the code. Because of
/// that, the base URL below is a clearly-marked placeholder: until a real URL
/// is provided, [voraTubeUpdateConfigured] reports `false` and the update
/// checker does **not** try to reach a guessed host — the app keeps working
/// exactly as before, fully offline. Pick a real value when you deploy your
/// website.
abstract final class UpdateConfig {
  /// Base for the website hosting the version file and the download page.
  ///
  /// Replace with the real VoraTube site, for example:
  ///   `'https://your-voratube-site.example'`
  static const String distributionBaseUrl =
      'https://REPLACE-WITH-YOUR-VORATUBE-WEBSITE.example';

  /// Endpoint serving the small version JSON file. Example format:
  ///
  /// ```json
  /// {
  ///   "latestVersion": "1.1.0",
  ///   "minimumVersion": "1.0.0",
  ///   "releaseNotes": ["Improved playback", "Fixed lyrics synchronization"]
  /// }
  /// ```
  static const String versionJsonUrl =
      '$distributionBaseUrl/voratube/version.json';

  /// The single hard-coded update destination opened by "Update Now".
  ///
  /// CURRENTLY:
  /// This points to the VoraTube website download page.
  ///
  /// AFTER GOOGLE PLAY RELEASE:
  /// Change this one constant to the official Google Play Store listing:
  ///   `'https://play.google.com/store/apps/details?id=com.piyushbaniya.vora_tube'`
  /// No other part of the app needs to change for that switch.
  static const String updateUrl = '$distributionBaseUrl/download';

  /// True once a real distribution URL has been configured. While the base
  /// URL is still the placeholder, the update checker bails out before doing
  /// any network I/O.
  static bool get isConfigured =>
      testConfigured ||
      !distributionBaseUrl.contains('REPLACE-WITH-YOUR-VORATUBE-WEBSITE');

  /// Test-only overrides so the service and launcher can be exercised without
  /// a real (never-supplied) distribution URL. Never referenced in app code.
  @visibleForTesting
  static bool testConfigured = false;

  @visibleForTesting
  static String testVersionJsonUrl = versionJsonUrl;

  @visibleForTesting
  static String testUpdateUrl = updateUrl;

  /// Effective URLs honouring the test overrides.
  static String get effectiveVersionJsonUrl =>
      testConfigured ? testVersionJsonUrl : versionJsonUrl;

  static String get effectiveUpdateUrl =>
      testConfigured ? testUpdateUrl : updateUrl;
}

import 'package:url_launcher/url_launcher.dart';

import 'update_config.dart';

/// Opens the configured update destination in the system browser. Independent
/// of networking and dialog logic so the URL policy lives in one place.
class UpdateUrlLauncher {
  const UpdateUrlLauncher();

  /// Validates and opens [UpdateConfig.updateUrl] externally. Returns
  /// `false` (never throws) when the URL is missing, not HTTPS, or the
  /// system cannot open it.
  Future<bool> open() async {
    final raw = UpdateConfig.effectiveUpdateUrl;
    final uri = Uri.tryParse(raw);
    // Require an absolute https URL on a real host. Rejecting anything else
    // means a user-supplied/placeholder value can never be launched.
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return false;
    }
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

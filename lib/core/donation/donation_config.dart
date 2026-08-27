import 'dart:io';

/// The project's Buy Me a Momo destination.
const String kBuyMeAMomoUri = 'https://buymemomo.com/piyushbaniya';

/// Lightweight connectivity probe.
///
/// Resolves the donation host's DNS records with a short timeout. Returns
/// `false` on any failure or timeout so the caller can degrade gracefully
/// instead of attempting to load the donation page offline.
Future<bool> checkInternetConnection() async {
  try {
    final result = await InternetAddress.lookup('buymemomo.com')
        .timeout(const Duration(seconds: 5));
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

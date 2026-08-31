import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Keys used by the Premium / ads entitlement feature.
abstract final class PremiumKeys {
  PremiumKeys._();

  /// The KV entry that records whether Premium is active.
  ///
  /// Only a boolean entitlement flag is ever stored — the premium code itself
  /// is never persisted after activation.
  static const String activated = 'premium.activated';
}

/// Whether advertising is shown is derived from the single, authoritative
/// Premium entitlement state (see the provider layer). This type models the
/// boolean that is persisted.
enum PremiumEntitlement {
  inactive,
  active;

  bool get isActive => this == PremiumEntitlement.active;
}

/// Validates an entered premium code against a one-way derived fingerprint.
///
/// The real code is never stored or logged: only its SHA-256 digest is kept
/// here, and validation compares the digest of whatever the user typed (exact
/// bytes, case-sensitive, no trimming beyond the caller's explicit check). A
/// determined reverse engineer could still recover the code from the digest by
/// brute force, which is inherent to any client-side entitlement — this is
/// intended as reasonable protection for a small friends-only code, not DRM.
abstract final class PremiumCodeValidator {
  PremiumCodeValidator._();

  /// SHA-256 digest of the valid premium code. Changing this digest is the
  /// only place that encodes the accepted secret.
  static final List<int> _expectedDigest = _digestFromHex(
    'bd3934c3d5cbf2121e4057feb66356acb1564a5630a889df586bf1ac1d35f609',
  );

  /// Exact, case-sensitive comparison of the entered code against the expected
  /// secret via its derived digest.
  ///
  /// The caller is responsible for rejecting empty / blank input before this
  /// is reached (an empty string will simply not match).
  static bool validate(String enteredCode) {
    final digest = sha256.convert(utf8.encode(enteredCode)).bytes;
    if (digest.length != _expectedDigest.length) return false;
    // Constant-ish comparison to avoid short-circuit leaking length/prefix
    // information. The codes are of fixed length so this leaks nothing more
    // than an equality check anyway, but keeps the intent explicit.
    var diff = 0;
    for (var i = 0; i < digest.length; i++) {
      diff |= digest[i] ^ _expectedDigest[i];
    }
    return diff == 0;
  }

  static List<int> _digestFromHex(String hex) {
    final bytes = List<int>.filled(hex.length ~/ 2, 0);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}

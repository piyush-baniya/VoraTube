import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/features/ads/ads_config.dart';
import 'package:vora_tube/features/ads/premium_models.dart';
import 'package:vora_tube/features/ads/premium_providers.dart';

/// Shared-prefs-free in-memory KV double that mirrors the subset of the
/// LibraryRepository surface the [PremiumController] actually touches
/// (`kvGet` / `kvSet`).
class _KvFake {
  final Map<String, String> _store = {};

  Future<String?> kvGet(String key) async => _store[key];

  Future<void> kvSet(String key, String value) async => _store[key] = value;
}

class _FailingKv {
  Future<String?> kvGet(String key) async => throw StateError('boom');

  Future<void> kvSet(String key, String value) async =>
      throw StateError('boom');
}

void main() {
  group('PremiumCodeValidator', () {
    test('valid code activates Premium (matches the stored digest)', () {
      // The accepted secret is only ever compared through its SHA-256 digest
      // (see premium_models.dart). The plaintext below is a test-only copy used
      // to prove the positive path; it is never shipped (test/ is excluded
      // from the APK) and the installed app still stores only the digest.
      expect(PremiumCodeValidator.validate('PiyuSsh'), isTrue);
    });

    test('rejects an empty / default input', () {
      expect(PremiumCodeValidator.validate(''), isFalse);
    });

    test('rejects a non-matching code', () {
      expect(PremiumCodeValidator.validate('NotTheCode'), isFalse);
    });

    test('is case-sensitive (wrong casing does not validate)', () {
      expect(PremiumCodeValidator.validate('piyussh'), isFalse);
      expect(PremiumCodeValidator.validate('PIYUSSH'), isFalse);
    });

    test('rejects a prefix / trailing-whitespace variant', () {
      expect(PremiumCodeValidator.validate('Piyu'), isFalse);
      expect(PremiumCodeValidator.validate('PiyuSsh '), isFalse);
    });
  });

  group('PremiumController', () {
    test(
      'starts inactive and loads an active entitlement on construct',
      () async {
        final kv = _KvFake();
        await kv.kvSet(PremiumKeys.activated, 'true');

        final controller = PremiumController(kv);
        await Future<void>.delayed(Duration.zero); // let _load() settle

        expect(controller.state, PremiumEntitlement.active);
        expect(controller.isPremium, isTrue);
      },
    );

    test('ignores a stored "false" and stays inactive', () async {
      final kv = _KvFake();
      await kv.kvSet(PremiumKeys.activated, 'false');

      final controller = PremiumController(kv);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, PremiumEntitlement.inactive);
      expect(controller.isPremium, isFalse);
    });

    test('load failure falls back to inactive (safe default)', () async {
      final controller = PremiumController(_FailingKv());
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, PremiumEntitlement.inactive);
    });

    test('activate promotes state and persists the entitlement', () async {
      final kv = _KvFake();
      final controller = PremiumController(kv);
      await Future<void>.delayed(Duration.zero);

      await controller.activate();

      expect(controller.isPremium, isTrue);
      expect(await kv.kvGet(PremiumKeys.activated), 'true');
    });

    test('deactivate revokes state and persists the revocation', () async {
      final kv = _KvFake();
      final controller = PremiumController(kv);
      await Future<void>.delayed(Duration.zero);

      await controller.activate();
      await controller.deactivate();

      expect(controller.isPremium, isFalse);
      expect(await kv.kvGet(PremiumKeys.activated), 'false');
    });

    test('deactivate on a fresh controller is a safe no-op', () async {
      final controller = PremiumController(_KvFake());
      await Future<void>.delayed(Duration.zero);

      await controller.deactivate();

      expect(controller.isPremium, isFalse);
    });
  });

  group('VoraTubeAds configuration', () {
    test('ships with test ads enabled (safe default)', () {
      expect(VoraTubeAds.useTestAds, isTrue);
      expect(VoraTubeAds.appId, VoraTubeAds.testAppId);
      expect(VoraTubeAds.bannerAndroidId, VoraTubeAds.testBannerAndroidId);
    });
  });
}

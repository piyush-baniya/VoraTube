import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/features/ads/ads_config.dart';
import 'package:vora_tube/features/ads/premium_models.dart';
import 'package:vora_tube/features/ads/premium_providers.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';

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
    AppDatabase newDb() => AppDatabase(NativeDatabase.memory());

    test('starts inactive and loads an active entitlement on construct',
        () async {
      final db = newDb();
      final repo = LibraryRepository(db);
      await repo.kvSet(PremiumKeys.activated, 'true');

      final controller = PremiumController(repo);
      await Future<void>.delayed(Duration.zero); // let _load() settle

      expect(controller.state, PremiumEntitlement.active);
      expect(controller.isPremium, isTrue);
      await db.close();
    });

    test('ignores a stored "false" and stays inactive', () async {
      final db = newDb();
      final repo = LibraryRepository(db);
      await repo.kvSet(PremiumKeys.activated, 'false');

      final controller = PremiumController(repo);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, PremiumEntitlement.inactive);
      expect(controller.isPremium, isFalse);
      await db.close();
    });

    test('activate promotes state and persists the entitlement', () async {
      final db = newDb();
      final repo = LibraryRepository(db);
      final controller = PremiumController(repo);
      await Future<void>.delayed(Duration.zero);

      await controller.activate();

      expect(controller.isPremium, isTrue);
      expect(await repo.kvGet(PremiumKeys.activated), 'true');
      await db.close();
    });

    test('deactivate revokes state and persists the revocation', () async {
      final db = newDb();
      final repo = LibraryRepository(db);
      final controller = PremiumController(repo);
      await Future<void>.delayed(Duration.zero);

      await controller.activate();
      await controller.deactivate();

      expect(controller.isPremium, isFalse);
      expect(await repo.kvGet(PremiumKeys.activated), 'false');
      await db.close();
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

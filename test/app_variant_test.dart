import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/app_variant.dart';

void main() {
  group('side-by-side V2 development package detection', () {
    test('production applicationId is not classified as v2dev', () {
      expect(isSideBySideDevPackage(productionApplicationId), isFalse);
    });

    test('the side-by-side applicationId is classified as v2dev', () {
      expect(
        isSideBySideDevPackage(sideBySideDevApplicationId),
        isTrue,
      );
    });

    test('lookalike names are not misclassified', () {
      // Only a trailing ".v2dev" qualifies, so near-misses stay production.
      expect(
        isSideBySideDevPackage('com.piyushbaniya.vora_tube.v2dev2'),
        isFalse,
      );
      expect(
        isSideBySideDevPackage('com.piyushbaniya.vora_tube.v2dev.x'),
        isFalse,
      );
      expect(isSideBySideDevPackage('com.piyushbaniya.vora_tubev2dev'), isFalse);
      expect(isSideBySideDevPackage(''), isFalse);
      expect(isSideBySideDevPackage('.v2dev'), isTrue);
    });

    test('constants form the documented side-by-side applicationId', () {
      expect(sideBySideDevApplicationIdSuffix, '.v2dev');
      expect(productionApplicationId, 'com.piyushbaniya.vora_tube');
      expect(
        sideBySideDevApplicationId,
        'com.piyushbaniya.vora_tube.v2dev',
      );
    });
  });
}

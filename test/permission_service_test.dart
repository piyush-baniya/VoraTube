import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:vora_tube/core/permissions/permission_service.dart';

void main() {
  group('androidMusicPermissionFor maps OS/API level to the right permission', () {
    test('API 32 and below request the legacy storage permission', () {
      // minSdk is 24, so exercise the supported legacy range.
      expect(androidMusicPermissionFor(24), Permission.storage);
      expect(androidMusicPermissionFor(28), Permission.storage);
      expect(androidMusicPermissionFor(29), Permission.storage);
      expect(androidMusicPermissionFor(30), Permission.storage);
      expect(androidMusicPermissionFor(31), Permission.storage);
      expect(androidMusicPermissionFor(32), Permission.storage);
    });

    test('API 33 and above request the modern audio permission', () {
      expect(androidMusicPermissionFor(33), Permission.audio);
      expect(androidMusicPermissionFor(34), Permission.audio);
      expect(androidMusicPermissionFor(35), Permission.audio);
      expect(androidMusicPermissionFor(36), Permission.audio);
    });

    test('boundary: API 32 must not use READ_MEDIA_AUDIO', () {
      expect(androidMusicPermissionFor(32), isNot(Permission.audio));
      expect(androidMusicPermissionFor(32), Permission.storage);
    });

    test('boundary: API 33 must not use READ_EXTERNAL_STORAGE', () {
      expect(androidMusicPermissionFor(33), isNot(Permission.storage));
      expect(androidMusicPermissionFor(33), Permission.audio);
    });
  });
}

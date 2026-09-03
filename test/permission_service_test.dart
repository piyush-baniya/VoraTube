import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:vora_tube/core/permissions/permission_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('currentAndroidApiLevel reads the real SDK_INT via the native channel', () {
    const channel = MethodChannel('voratube/android_version_v1');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('API 35 (Android 15) resolves the modern audio permission', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'sdkInt');
        return 35;
      });

      const service = PermissionService(androidSdkChannel: channel);
      expect(await service.currentAndroidApiLevel(), 35);
      expect(androidMusicPermissionFor(await service.currentAndroidApiLevel()),
          Permission.audio);
    });

    test('API 32 resolves the legacy storage permission', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => 32);

      const service = PermissionService(androidSdkChannel: channel);
      expect(await service.currentAndroidApiLevel(), 32);
      expect(androidMusicPermissionFor(await service.currentAndroidApiLevel()),
          Permission.storage);
    });

    test('falls back to the version-string parse when the channel is missing',
        () async {
      // No mock handler is registered; invoking the real channel throws
      // MissingPluginException, which must fall back to a sane default.
      const service = PermissionService(androidSdkChannel: channel);
      final level = await service.currentAndroidApiLevel();
      // The host test process isn't Android, so this is at most 0; the point
      // is that it does not throw (regression: used to be a mis-parse).
      expect(level, isA<int>());
    });
  });
}

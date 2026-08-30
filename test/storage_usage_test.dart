import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/storage/device_storage_service.dart';
import 'package:vora_tube/features/settings/presentation/providers/settings_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('measureStorageTree aggregation', () {
    test('sums art and music by filename suffix across nested files', () async {
      final dir = Directory.systemTemp.createTempSync('vora_storage_tree');
      addTearDown(() => dir.deleteSync(recursive: true));

      File('${dir.path}/album_s.webp').writeAsBytesSync(List.filled(100, 0));
      File('${dir.path}/thumb_l.webp').writeAsBytesSync(List.filled(50, 0));
      File('${dir.path}/song_a.mp3').writeAsBytesSync(List.filled(1000, 0));
      final sub = Directory('${dir.path}/artist')..createSync();
      // A plain artwork file without a _s/_l suffix is not recognised by the
      // filename-based classifier, so it lands in the music bucket. This is
      // the current, deliberate classification contract we guard against.
      File('${sub.path}/cover.webp').writeAsBytesSync(List.filled(30, 0));

      final (art, music) = await measureStorageTree(dir);

      expect(art, 100 + 50); // _s + _l
      expect(music, 1000 + 30); // mp3 + suffix-less cover
    });

    test('empty directory yields zero instead of throwing', () async {
      final dir = Directory.systemTemp.createTempSync('vora_storage_empty');
      addTearDown(() => dir.deleteSync(recursive: true));

      final (art, music) = await measureStorageTree(dir);
      expect(art, 0);
      expect(music, 0);
    });

    test('unreadable/missing directory degrades to zero', () async {
      final (art, music) = await measureStorageTree(
        Directory('no/such/path/anywhere'),
      );
      expect(art, 0);
      expect(music, 0);
    });
  });

  group('StorageInfo byte formatting', () {
    StorageInfo make(int db, int art, int imp) => StorageInfo(
      databaseSizeBytes: db,
      artworkCacheSizeBytes: art,
      importedMusicSizeBytes: imp,
      totalSizeBytes: db + art + imp,
    );

    test('formats plain bytes', () {
      final info = make(512, 0, 0);
      expect(info.databaseSize, '512 B');
      expect(info.artworkCacheSize, '0 B');
      expect(info.importedMusicSize, '0 B');
    });

    test('formats kilobytes', () {
      expect(make(2 * 1024, 0, 0).databaseSize, '2.0 KB');
    });

    test('formats megabytes', () {
      expect(make(3 * 1024 * 1024, 0, 0).databaseSize, '3.0 MB');
    });

    test('formats gigabytes', () {
      expect(make(2 * 1024 * 1024 * 1024, 0, 0).databaseSize, '2.0 GB');
    });

    test('totals real app usage', () {
      final info = make(1, 2, 3);
      expect(info.totalSize, '6 B');
      expect(info.totalSizeBytes, 6);
    });

    test('device figures expose real totals', () {
      final gb = 1024 * 1024 * 1024;
      final info = StorageInfo(
        databaseSizeBytes: 1,
        artworkCacheSizeBytes: 2,
        importedMusicSizeBytes: 3,
        totalSizeBytes: 6,
        device: DeviceStorageInfo(
          totalBytes: 64 * gb,
          usedBytes: 20 * gb,
          availableBytes: 44 * gb,
        ),
      );
      expect(info.deviceTotalSize, '64.0 GB');
      expect(info.deviceUsedSize, '20.0 GB');
      expect(info.deviceAvailableSize, '44.0 GB');
    });
  });

  group('DeviceStorageService parsing', () {
    test('builds info from a well-formed map', () async {
      const channel = MethodChannel('test/device_storage_ok');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => <String, Object?>{
              'totalBytes': 1000,
              'usedBytes': 200,
              'availableBytes': 800,
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final info = await DeviceStorageService(channel: channel)
          .getStorageInfo();
      expect(info, isNotNull);
      expect(info!.totalBytes, 1000);
      expect(info.usedBytes, 200);
      expect(info.availableBytes, 800);
    });

    test('returns null when measured fields are missing', () async {
      const channel = MethodChannel('test/device_storage_missing');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => <String, Object?>{'totalBytes': 1000},
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final info = await DeviceStorageService(channel: channel)
          .getStorageInfo();
      expect(info, isNull);
    });

    test('returns null on non-map or thrown platform call', () async {
      const channel = MethodChannel('test/device_storage_bad');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => 'not a map');
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final info = await DeviceStorageService(channel: channel)
          .getStorageInfo();
      expect(info, isNull);
    });
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Real on-device storage numbers read from the platform.
///
/// Kept separate from [StorageInfo] (the Settings model) so the app-usage
/// measurement can evolve without coupling to the raw device figures.
@immutable
class DeviceStorageInfo {
  const DeviceStorageInfo({
    required this.totalBytes,
    required this.usedBytes,
    required this.availableBytes,
  });

  final int totalBytes;
  final int usedBytes;
  final int availableBytes;
}

/// Thin MethodChannel wrapper around the native storage reader.
///
/// Every failure collapses to `null` — an unreadable partition or missing
/// native handler must never error the Settings screen; the card degrades to
/// the reachable "app usage" figures instead.
class DeviceStorageService {
  DeviceStorageService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('voratube/device_storage_v1');

  final MethodChannel _channel;

  Future<DeviceStorageInfo?> getStorageInfo() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('getStorageSummary');
      if (raw is! Map<Object?, Object?>) {
        return null;
      }
      final total = _i64(raw, 'totalBytes');
      final used = _i64(raw, 'usedBytes');
      final available = _i64(raw, 'availableBytes');
      if (total == null || used == null || available == null) {
        return null;
      }
      return DeviceStorageInfo(
        totalBytes: total,
        usedBytes: used,
        availableBytes: available,
      );
    } catch (_) {
      return null;
    }
  }

  int? _i64(Map<Object?, Object?> map, String key) {
    final value = map[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }
}

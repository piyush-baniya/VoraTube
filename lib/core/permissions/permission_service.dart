import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

enum MediaPermissionStatus { granted, denied, permanentlyDenied }

/// Android API level at which the modern read-media permission
/// (`READ_MEDIA_AUDIO`) was introduced.
const int _readMediaAudioApiLevel = 33;

/// Returns the [Permission] group that grants read access to the device's
/// music library on a given Android API level.
///
/// - API 33+ (Android 13+): `READ_MEDIA_AUDIO` via [Permission.audio].
/// - API 32 and below (Android 12L and below): `READ_EXTERNAL_STORAGE` via
///   [Permission.storage], which the plugin maps to the legacy storage
///   permission declared in the manifest with `maxSdkVersion="32"`.
///
/// The `permission_handler` Android plugin only exposes `READ_MEDIA_AUDIO` on
/// API 33+; on older Android its `Permission.audio` group returns no manifest
/// names, so requesting it resolves to `denied` without ever showing a system
/// dialog. The legacy storage group must therefore be selected explicitly
/// below API 33.
Permission androidMusicPermissionFor(int apiLevel) {
  return apiLevel >= _readMediaAudioApiLevel
      ? Permission.audio
      : Permission.storage;
}

class PermissionService {
  const PermissionService();

  Future<MediaPermissionStatus> audioStatus() async {
    return _map(await _musicPermission().status);
  }

  Future<MediaPermissionStatus> requestAudio() async {
    return _map(await _musicPermission().request());
  }

  Future<void> openAppSettingsPage() => openAppSettings();

  /// The permission group used to read the music library on the current
  /// platform. Android is version-aware (see [androidMusicPermissionFor]);
  /// other platforms keep the previous behaviour.
  Permission _musicPermission() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return androidMusicPermissionFor(_currentAndroidApiLevel());
    }
    return Permission.audio;
  }

  /// Reads the Android API level the app is running on.
  ///
  /// [Platform.operatingSystemVersion] reports the Android framework release
  /// string, e.g. `"10"`, `"13"` or `"8.1.0"`; the leading integer is the API
  /// level we branch on.
  int _currentAndroidApiLevel() {
    final match = RegExp(r'^(\d+)').firstMatch(Platform.operatingSystemVersion);
    return match == null ? 0 : int.parse(match.group(1)!);
  }

  MediaPermissionStatus _map(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.granted:
      case PermissionStatus.limited:
        return MediaPermissionStatus.granted;
      case PermissionStatus.permanentlyDenied:
        return MediaPermissionStatus.permanentlyDenied;
      case PermissionStatus.denied:
      case PermissionStatus.restricted:
      case PermissionStatus.provisional:
        return MediaPermissionStatus.denied;
    }
  }
}

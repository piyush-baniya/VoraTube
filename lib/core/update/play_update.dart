import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum PlayUpdateStatus {
  idle,
  unsupported,
  notAvailable,
  available,
  downloading,
  downloaded,
  installing,
  installed,
  failed,
  canceled,
}

class PlayUpdateInfo {
  const PlayUpdateInfo({
    this.status = PlayUpdateStatus.idle,
    this.availableVersionCode,
    this.updatePriority = 0,
    this.stalenessDays,
    this.isFlexibleAllowed = false,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.promptToken = 0,
  });

  factory PlayUpdateInfo.fromMap(Map<Object?, Object?> map) {
    final status = PlayUpdateStatus.values.firstWhere(
      (s) => s.name == map['status'],
      orElse: () => PlayUpdateStatus.notAvailable,
    );
    return PlayUpdateInfo(
      status: status,
      availableVersionCode: map['availableVersionCode'] as int?,
      updatePriority: (map['updatePriority'] as int?) ?? 0,
      stalenessDays: map['stalenessDays'] as int?,
      isFlexibleAllowed: (map['isFlexibleAllowed'] as bool?) ?? false,
      downloadedBytes: (map['downloadedBytes'] as int?) ?? 0,
      totalBytes: (map['totalBytes'] as int?) ?? 0,
    );
  }

  final PlayUpdateStatus status;
  final int? availableVersionCode;
  final int updatePriority;
  final int? stalenessDays;
  final bool isFlexibleAllowed;
  final int downloadedBytes;
  final int totalBytes;

  /// Incremented by the controller only when a prompt should be presented.
  /// The host watches this instead of [status] so a re-check for the same
  /// state cannot open a second sheet.
  final int promptToken;

  bool get canPrompt =>
      status == PlayUpdateStatus.available && isFlexibleAllowed;

  double? get progress =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : null;

  PlayUpdateInfo copyWith({
    PlayUpdateStatus? status,
    int? downloadedBytes,
    int? totalBytes,
    int? promptToken,
  }) {
    return PlayUpdateInfo(
      status: status ?? this.status,
      availableVersionCode: availableVersionCode,
      updatePriority: updatePriority,
      stalenessDays: stalenessDays,
      isFlexibleAllowed: isFlexibleAllowed,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      promptToken: promptToken ?? this.promptToken,
    );
  }
}

abstract interface class PlayUpdateApi {
  Future<PlayUpdateInfo> checkForUpdate();
  Future<PlayUpdateStatus> startFlexibleUpdate();
  Future<void> completeUpdate();
  set onStateChange(void Function(PlayUpdateInfo state)? callback);
}

abstract interface class PlayUpdateStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class MethodChannelPlayUpdateApi implements PlayUpdateApi {
  MethodChannelPlayUpdateApi({String? packageName})
    : _knownPackageName = packageName;

  static const _channel = MethodChannel('voratube/play_update_v1');
  final String? _knownPackageName;
  String? _resolvedPackageName;
  void Function(PlayUpdateInfo state)? _callback;

  @override
  set onStateChange(void Function(PlayUpdateInfo state)? callback) {
    _callback = callback;
    _channel.setMethodCallHandler(
      callback == null
          ? null
          : (call) async {
              if (call.method == 'onInstallState') {
                _callback?.call(
                  PlayUpdateInfo.fromMap(
                    Map<Object?, Object?>.from(call.arguments as Map),
                  ),
                );
              }
              return null;
            },
    );
  }

  Future<bool> _isSupported() async {
    if (!Platform.isAndroid) return false;
    _resolvedPackageName =
        _knownPackageName ??
        _resolvedPackageName ??
        (await PackageInfo.fromPlatform()).packageName;
    return !_resolvedPackageName!.endsWith('.v2dev');
  }

  @override
  Future<PlayUpdateInfo> checkForUpdate() async {
    if (!await _isSupported()) {
      return const PlayUpdateInfo(status: PlayUpdateStatus.unsupported);
    }
    try {
      final map = await _channel.invokeMethod<Object?>('checkForUpdate');
      return PlayUpdateInfo.fromMap(Map<Object?, Object?>.from(map as Map));
    } catch (_) {
      return const PlayUpdateInfo(status: PlayUpdateStatus.unsupported);
    }
  }

  @override
  Future<PlayUpdateStatus> startFlexibleUpdate() async {
    if (!await _isSupported()) return PlayUpdateStatus.unsupported;
    try {
      final map = await _channel.invokeMethod<Object?>('startFlexibleUpdate');
      return PlayUpdateInfo.fromMap(Map<Object?, Object?>.from(map as Map))
          .status;
    } catch (_) {
      return PlayUpdateStatus.failed;
    }
  }

  @override
  Future<void> completeUpdate() async {
    try {
      await _channel.invokeMethod<Object?>('completeUpdate');
    } catch (_) {}
  }
}

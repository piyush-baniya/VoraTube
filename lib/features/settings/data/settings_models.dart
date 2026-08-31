import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/player/player_controller.dart';

/// User's theme preference.
enum AppThemeMode {
  /// Follow system theme.
  system,

  /// Always dark.
  dark,

  /// Always light.
  light,
}

/// User's ReplayGain normalization preference.
enum ReplayGainPreference {
  /// No normalization.
  off,

  /// Track-level normalization.
  track,

  /// Album-level normalization.
  album,
}

/// Settings for audio playback.
@immutable
class AudioSettings {
  const AudioSettings({
    this.replayGain = ReplayGainPreference.off,
    this.preampDb = 0.0,
  });

  final ReplayGainPreference replayGain;
  final double preampDb;

  AudioSettings copyWith({ReplayGainPreference? replayGain, double? preampDb}) {
    return AudioSettings(
      replayGain: replayGain ?? this.replayGain,
      preampDb: preampDb ?? this.preampDb,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioSettings &&
          other.replayGain == replayGain &&
          other.preampDb == preampDb;

  @override
  int get hashCode => Object.hash(replayGain, preampDb);
}

/// Settings for library management.
@immutable
class LibrarySettings {
  const LibrarySettings({
    this.cleanMissingFilesOnStart = true,
    this.scanOverWiFiOnly = false,
  });

  final bool cleanMissingFilesOnStart;
  final bool scanOverWiFiOnly;

  LibrarySettings copyWith({
    bool? cleanMissingFilesOnStart,
    bool? scanOverWiFiOnly,
  }) {
    return LibrarySettings(
      cleanMissingFilesOnStart:
          cleanMissingFilesOnStart ?? this.cleanMissingFilesOnStart,
      scanOverWiFiOnly: scanOverWiFiOnly ?? this.scanOverWiFiOnly,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibrarySettings &&
          other.cleanMissingFilesOnStart == cleanMissingFilesOnStart &&
          other.scanOverWiFiOnly == scanOverWiFiOnly;

  @override
  int get hashCode => Object.hash(cleanMissingFilesOnStart, scanOverWiFiOnly);
}

/// Theme preference.
@immutable
class AppearanceSettings {
  const AppearanceSettings({this.themeMode = AppThemeMode.system});

  final AppThemeMode themeMode;

  AppearanceSettings copyWith({AppThemeMode? themeMode}) {
    return AppearanceSettings(themeMode: themeMode ?? this.themeMode);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppearanceSettings && other.themeMode == themeMode;

  @override
  int get hashCode => themeMode.hashCode;
}

/// Aggregated settings state.
@immutable
class AppSettings {
  const AppSettings({
    this.audio = const AudioSettings(),
    this.library = const LibrarySettings(),
    this.appearance = const AppearanceSettings(),
  });

  final AudioSettings audio;
  final LibrarySettings library;
  final AppearanceSettings appearance;

  AppSettings copyWith({
    AudioSettings? audio,
    LibrarySettings? library,
    AppearanceSettings? appearance,
  }) {
    return AppSettings(
      audio: audio ?? this.audio,
      library: library ?? this.library,
      appearance: appearance ?? this.appearance,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          other.audio == audio &&
          other.library == library &&
          other.appearance == appearance;

  @override
  int get hashCode => Object.hash(audio, library, appearance);
}

/// Keys for persistent settings storage.
class SettingsKeys {
  const SettingsKeys._();

  static const String audio = 'settings.audio';
  static const String library = 'settings.library';
  static const String appearance = 'settings.appearance';

  /// Stores the most recent successful update-check timestamp (milliseconds
  /// since epoch) so the check is throttled to once per interval.
  static const String updateCheck = 'update.lastCheck';
}

/// JSON serialization for AudioSettings.
extension AudioSettingsJson on AudioSettings {
  String toJson() =>
      '{"replayGain": "${replayGain.name}", "preampDb": $preampDb}';

  static AudioSettings fromJson(String json) {
    try {
      final replayGainMatch = RegExp(r'"replayGain"\s*:\s*"(\w+)"')
          .firstMatch(json);
      final preampMatch = RegExp(r'"preampDb"\s*:\s*([\d\.\-]+)')
          .firstMatch(json);
      return AudioSettings(
        replayGain: ReplayGainPreference.values.firstWhere(
          (e) => e.name == (replayGainMatch?.group(1) ?? 'off'),
          orElse: () => ReplayGainPreference.off,
        ),
        preampDb: double.tryParse(preampMatch?.group(1) ?? '0') ?? 0.0,
      );
    } catch (_) {
      return const AudioSettings();
    }
  }
}

/// JSON serialization for LibrarySettings.
extension LibrarySettingsJson on LibrarySettings {
  String toJson() =>
      '''
{"cleanMissingFilesOnStart": $cleanMissingFilesOnStart,
 "scanOverWiFiOnly": $scanOverWiFiOnly}''';

  static LibrarySettings fromJson(String json) {
    try {
      // Note: `autoRescanOnStart` was removed from settings; legacy JSON that
      // still contains the key parses fine and the key is simply ignored.
      final cleanMatch = RegExp(
        r'"cleanMissingFilesOnStart"\s*:\s*(true|false)',
      ).firstMatch(json);
      final wifiMatch = RegExp(r'"scanOverWiFiOnly"\s*:\s*(true|false)')
          .firstMatch(json);
      return LibrarySettings(
        cleanMissingFilesOnStart: cleanMatch?.group(1) == 'true',
        scanOverWiFiOnly: wifiMatch?.group(1) == 'true',
      );
    } catch (_) {
      return const LibrarySettings();
    }
  }
}

/// JSON serialization for AppearanceSettings.
extension AppearanceSettingsJson on AppearanceSettings {
  String toJson() => '{"themeMode": "${themeMode.name}"}';

  static AppearanceSettings fromJson(String json) {
    try {
      final themeMatch = RegExp(r'"themeMode"\s*:\s*"(\w+)"').firstMatch(json);
      return AppearanceSettings(
        themeMode: AppThemeMode.values.firstWhere(
          (e) => e.name == (themeMatch?.group(1) ?? 'system'),
          orElse: () => AppThemeMode.system,
        ),
      );
    } catch (_) {
      return const AppearanceSettings();
    }
  }
}

/// JSON serialization for settings.
extension AppSettingsJson on AppSettings {
  String toJson() {
    return '''
{
  "audio": ${audioToJson(audio)},
  "library": ${libraryToJson(library)},
  "appearance": ${appearanceToJson(appearance)}
}''';
  }

  static AppSettings fromJson(String json) {
    // Simple manual parsing - in production use jsonDecode
    final audio = _parseAudio(json);
    final library = _parseLibrary(json);
    final appearance = _parseAppearance(json);
    return AppSettings(audio: audio, library: library, appearance: appearance);
  }

  static String audioToJson(AudioSettings a) =>
      '{"replayGain": "${a.replayGain.name}", "preampDb": ${a.preampDb}}';

  static String libraryToJson(LibrarySettings l) =>
      '''
{"cleanMissingFilesOnStart": ${l.cleanMissingFilesOnStart},
 "scanOverWiFiOnly": ${l.scanOverWiFiOnly}}''';

  static String appearanceToJson(AppearanceSettings a) =>
      '{"themeMode": "${a.themeMode.name}"}';

  static AudioSettings _parseAudio(String json) {
    try {
      final replayGainMatch = RegExp(r'"replayGain"\s*:\s*"(\w+)"')
          .firstMatch(json);
      final preampMatch = RegExp(r'"preampDb"\s*:\s*([\d\.\-]+)')
          .firstMatch(json);
      return AudioSettings(
        replayGain: ReplayGainPreference.values.firstWhere(
          (e) => e.name == (replayGainMatch?.group(1) ?? 'off'),
          orElse: () => ReplayGainPreference.off,
        ),
        preampDb: double.tryParse(preampMatch?.group(1) ?? '0') ?? 0.0,
      );
    } catch (_) {
      return const AudioSettings();
    }
  }

  static LibrarySettings _parseLibrary(String json) {
    try {
      final cleanMatch = RegExp(
        r'"cleanMissingFilesOnStart"\s*:\s*(true|false)',
      ).firstMatch(json);
      final wifiMatch = RegExp(r'"scanOverWiFiOnly"\s*:\s*(true|false)')
          .firstMatch(json);
      return LibrarySettings(
        cleanMissingFilesOnStart: cleanMatch?.group(1) == 'true',
        scanOverWiFiOnly: wifiMatch?.group(1) == 'true',
      );
    } catch (_) {
      return const LibrarySettings();
    }
  }

  static AppearanceSettings _parseAppearance(String json) {
    try {
      final themeMatch = RegExp(r'"themeMode"\s*:\s*"(\w+)"').firstMatch(json);
      return AppearanceSettings(
        themeMode: AppThemeMode.values.firstWhere(
          (e) => e.name == (themeMatch?.group(1) ?? 'system'),
          orElse: () => AppThemeMode.system,
        ),
      );
    } catch (_) {
      return const AppearanceSettings();
    }
  }
}

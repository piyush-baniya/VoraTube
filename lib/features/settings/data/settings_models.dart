import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/audio/audio_effects.dart';

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
///
/// Persistence uses JSON under the [SettingsKeys.audio] key. Unknown keys
/// introduced by newer app versions are gracefully ignored so the format is
/// forward-compatible: a user downgrading the app never loses existing replay
/// gain/preamp settings, and new fields simply default to their neutral
/// constants when absent.
@immutable
class AudioSettings {
  const AudioSettings({
    this.replayGain = ReplayGainPreference.off,
    this.preampDb = 0.0,
    this.eqEnabled = false,
    this.eqPreset = EqPreset.flat,
    this.eqCustomLevels = const [],
    this.playbackSpeed = kDefaultPlaybackSpeed,
    this.transitionMode = PlaybackTransitionMode.crossfade,
    this.crossfadeSeconds = kDefaultCrossfadeSeconds,
    this.audioBalance = kDefaultAudioBalance,
  });

  final ReplayGainPreference replayGain;
  final double preampDb;

  /// When true the Android equalizer effect is active and the persisted EQ
  /// curve is forwarded to just_audio via [mapVirtualCurveToBands].
  final bool eqEnabled;

  /// Current EQ preset. [EqPreset.custom] activates the 10-band custom
  /// curve stored in [eqCustomLevels].
  final EqPreset eqPreset;

  /// The 10-band custom curve (dB), only applied when [eqPreset] is
  /// [EqPreset.custom]. Persisted normalized to [eqVirtualBandCount] entries.
  final List<double> eqCustomLevels;

  /// Playback speed multiplied into the audio pipeline. Preserves pitch
  /// so speeding up / slowing down does not affect voice timbre.
  final double playbackSpeed;

  /// How one track hands over to the next.
  final PlaybackTransitionMode transitionMode;

  /// Crossfade half-duration (seconds) when [transitionMode] is
  /// [PlaybackTransitionMode.crossfade].
  final int crossfadeSeconds;

  /// Audio balance: -1.0 (left) to +1.0 (right), 0.0 = center.
  /// Applied best-effort on devices where the platform audio output exposes a
  /// per-app stereo balance control; otherwise the setting is persisted and
  /// displayed for future native application.
  final double audioBalance;

  AudioSettings copyWith({
    ReplayGainPreference? replayGain,
    double? preampDb,
    bool? eqEnabled,
    EqPreset? eqPreset,
    List<double>? eqCustomLevels,
    double? playbackSpeed,
    PlaybackTransitionMode? transitionMode,
    int? crossfadeSeconds,
    double? audioBalance,
  }) {
    return AudioSettings(
      replayGain: replayGain ?? this.replayGain,
      preampDb: preampDb ?? this.preampDb,
      eqEnabled: eqEnabled ?? this.eqEnabled,
      eqPreset: eqPreset ?? this.eqPreset,
      eqCustomLevels: eqCustomLevels == null
          ? this.eqCustomLevels
          : normalizeEqLevels(eqCustomLevels),
      playbackSpeed: playbackSpeed == null
          ? this.playbackSpeed
          : playbackSpeed.clamp(kPlaybackSpeedMin, kPlaybackSpeedMax).toDouble(),
      transitionMode: transitionMode ?? this.transitionMode,
      crossfadeSeconds: crossfadeSeconds == null
          ? this.crossfadeSeconds
          : clampCrossfadeSeconds(crossfadeSeconds),
      audioBalance: audioBalance == null
          ? this.audioBalance
          : clampAudioBalance(audioBalance),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioSettings &&
          other.replayGain == replayGain &&
          other.preampDb == preampDb &&
          other.eqEnabled == eqEnabled &&
          other.eqPreset == eqPreset &&
          other.eqCustomLevels == eqCustomLevels &&
          other.playbackSpeed == playbackSpeed &&
          other.transitionMode == transitionMode &&
          other.crossfadeSeconds == crossfadeSeconds &&
          other.audioBalance == audioBalance;

  @override
  int get hashCode => Object.hash(
    replayGain,
    preampDb,
    eqEnabled,
    eqPreset,
    eqCustomLevels,
    playbackSpeed,
    transitionMode,
    crossfadeSeconds,
    audioBalance,
  );
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
  const AppearanceSettings({
    this.themeMode = AppThemeMode.system,
    this.themePreset = AppThemePreset.purple,
  });

  final AppThemeMode themeMode;

  /// Which accent identity/surface ramp the app uses. Independent of
  /// [themeMode]; both are persisted in the same appearance JSON.
  final AppThemePreset themePreset;

  AppearanceSettings copyWith({
    AppThemeMode? themeMode,
    AppThemePreset? themePreset,
  }) {
    return AppearanceSettings(
      themeMode: themeMode ?? this.themeMode,
      themePreset: themePreset ?? this.themePreset,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppearanceSettings &&
          other.themeMode == themeMode &&
          other.themePreset == themePreset;

  @override
  int get hashCode => Object.hash(themeMode, themePreset);
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

  /// The last-browsed Library section (Songs/Albums/Artists/Genres), so the
  /// Library tab reopens where the user left off across restarts.
  static const String librarySection = 'settings.librarySection';

  /// Stores the most recent successful update-check timestamp (milliseconds
  /// since epoch) so the check is throttled to once per interval.
  static const String updateCheck = 'update.lastCheck';
}

/// JSON serialization for AudioSettings.
///
/// Uses RegExp-based (no dart:convert dependency) key-value matching so legacy
/// JSON with missing keys gracefully falls back to defaults.
extension AudioSettingsJson on AudioSettings {
  String toJson() =>
      '{"replayGain": "${replayGain.name}", "preampDb": $preampDb, '
      '"eqEnabled": $eqEnabled, "eqPreset": "${eqPreset.name}", '
      '"eqCustomLevels": ${_jsonList(eqCustomLevels)}, '
      '"playbackSpeed": $playbackSpeed, '
      '"transitionMode": "${transitionMode.name}", '
      '"crossfadeSeconds": $crossfadeSeconds, '
      '"audioBalance": $audioBalance}';

  static AudioSettings fromJson(String json) {
    try {
      final replayGainMatch = RegExp(r'"replayGain"\s*:\s*"(\w+)"')
          .firstMatch(json);
      final preampMatch = RegExp(r'"preampDb"\s*:\s*([\d\.\-]+)')
          .firstMatch(json);
      final eqEnabledMatch = RegExp(r'"eqEnabled"\s*:\s*(true|false)')
          .firstMatch(json);
      final eqPresetMatch = RegExp(r'"eqPreset"\s*:\s*"(\w+)"')
          .firstMatch(json);
      final eqCustomLevelsMatch =
          RegExp(r'"eqCustomLevels"\s*:\s*(\[[0-9\.,\-\s]*\])')
              .firstMatch(json);
      final playbackSpeedMatch = RegExp(r'"playbackSpeed"\s*:\s*([\d\.\-]+)')
          .firstMatch(json);
      final transitionModeMatch = RegExp(r'"transitionMode"\s*:\s*"(\w+)"')
          .firstMatch(json);
      final crossfadeSecondsMatch =
          RegExp(r'"crossfadeSeconds"\s*:\s*(\d+)').firstMatch(json);
      final audioBalanceMatch = RegExp(r'"audioBalance"\s*:\s*([\d\.\-]+)')
          .firstMatch(json);

      final parsedCustomLevels = eqCustomLevelsMatch == null
          ? normalizeEqLevels(const [])
          : normalizeEqLevels(
              RegExp(r'[\d\.\-]+')
                  .allMatches(eqCustomLevelsMatch.group(1)!)
                  .map((m) => double.parse(m.group(0)!))
                  .toList(),
            );

      final parsedSpeed =
          double.tryParse(playbackSpeedMatch?.group(1) ?? '1') ?? 1.0;
      final parsedTransition = PlaybackTransitionMode.values.firstWhere(
        (e) => e.name == (transitionModeMatch?.group(1) ?? 'crossfade'),
        orElse: () => PlaybackTransitionMode.crossfade,
      );
      final parsedCrossfadeSeconds =
          int.tryParse(crossfadeSecondsMatch?.group(1) ?? '4') ?? 4;
      final parsedBalance =
          double.tryParse(audioBalanceMatch?.group(1) ?? '0') ?? 0.0;

      return AudioSettings(
        replayGain: ReplayGainPreference.values.firstWhere(
          (e) => e.name == (replayGainMatch?.group(1) ?? 'off'),
          orElse: () => ReplayGainPreference.off,
        ),
        preampDb: double.tryParse(preampMatch?.group(1) ?? '0') ?? 0.0,
        eqEnabled: eqEnabledMatch?.group(1) == 'true',
        eqPreset: EqPreset.values.firstWhere(
          (e) => e.name == (eqPresetMatch?.group(1) ?? 'flat'),
          orElse: () => EqPreset.flat,
        ),
        eqCustomLevels: parsedCustomLevels,
        playbackSpeed: parsedSpeed.clamp(kPlaybackSpeedMin, kPlaybackSpeedMax).toDouble(),
        transitionMode: parsedTransition,
        crossfadeSeconds: clampCrossfadeSeconds(parsedCrossfadeSeconds),
        audioBalance: clampAudioBalance(parsedBalance),
      );
    } catch (_) {
      return const AudioSettings();
    }
  }

  /// Builds a compact JSON array literal from a list of doubles.
  static String _jsonList(List<double> values) =>
      '[${values.map((v) => v.toString()).join(', ')}]';
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
  String toJson() =>
      '{"themeMode": "${themeMode.name}", "themePreset": "${themePreset.name}"}';

  static AppearanceSettings fromJson(String json) {
    try {
      final themeMatch = RegExp(r'"themeMode"\s*:\s*"(\w+)"').firstMatch(json);
      final presetMatch = RegExp(r'"themePreset"\s*:\s*"(\w+)"')
          .firstMatch(json);
      return AppearanceSettings(
        themeMode: AppThemeMode.values.firstWhere(
          (e) => e.name == (themeMatch?.group(1) ?? 'system'),
          orElse: () => AppThemeMode.system,
        ),
        // Missing/legacy `themePreset` falls back to Purple so old saved
        // settings migrate onto the default identity without data loss.
        themePreset: AppThemePreset.values.firstWhere(
          (e) => e.name == (presetMatch?.group(1) ?? 'purple'),
          orElse: () => AppThemePreset.purple,
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

  static String audioToJson(AudioSettings a) => a.toJson();

  static String libraryToJson(LibrarySettings l) =>
      '''
{"cleanMissingFilesOnStart": ${l.cleanMissingFilesOnStart},
 "scanOverWiFiOnly": ${l.scanOverWiFiOnly}}''';

  static String appearanceToJson(AppearanceSettings a) =>
      '{"themeMode": "${a.themeMode.name}", "themePreset": "${a.themePreset.name}"}';

  static AudioSettings _parseAudio(String json) =>
      AudioSettingsJson.fromJson(json);

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
      final presetMatch = RegExp(r'"themePreset"\s*:\s*"(\w+)"')
          .firstMatch(json);
      return AppearanceSettings(
        themeMode: AppThemeMode.values.firstWhere(
          (e) => e.name == (themeMatch?.group(1) ?? 'system'),
          orElse: () => AppThemeMode.system,
        ),
        themePreset: AppThemePreset.values.firstWhere(
          (e) => e.name == (presetMatch?.group(1) ?? 'purple'),
          orElse: () => AppThemePreset.purple,
        ),
      );
    } catch (_) {
      return const AppearanceSettings();
    }
  }
}

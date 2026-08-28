import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../features/library/presentation/providers/library_providers.dart';
import '../../data/settings_models.dart';

// ── Storage info ────────────────────────────────────────────────────────

@immutable
class StorageInfo {
  const StorageInfo({
    required this.databaseSizeBytes,
    required this.artworkCacheSizeBytes,
    required this.importedMusicSizeBytes,
    required this.totalSizeBytes,
  });

  final int databaseSizeBytes;
  final int artworkCacheSizeBytes;
  final int importedMusicSizeBytes;
  final int totalSizeBytes;

  String get databaseSize => _formatBytes(databaseSizeBytes);
  String get artworkCacheSize => _formatBytes(artworkCacheSizeBytes);
  String get importedMusicSize => _formatBytes(importedMusicSizeBytes);
  String get totalSize => _formatBytes(totalSizeBytes);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// drift_flutter stores the named database in the app support directory using
/// the `.sqlite` extension. Keeping this in one place prevents Settings from
/// reporting an empty database simply because it previously checked `''`.
Future<String> _getDatabasePath() async {
  final directory = await getApplicationSupportDirectory();
  return '${directory.path}${Platform.pathSeparator}voratube.sqlite';
}

Future<int> _getFileSize(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) return await file.length();
  } catch (_) {}
  return 0;
}

// ── Persisted app settings loaded from KV storage ───────────────────────

final appSettingsProvider = FutureProvider<AppSettings>((ref) async {
  final repository = ref.watch(libraryRepositoryProvider) as dynamic;
  final audioJson = await repository.kvGet(SettingsKeys.audio) as String?;
  final libraryJson = await repository.kvGet(SettingsKeys.library) as String?;
  final appearanceJson =
      await repository.kvGet(SettingsKeys.appearance) as String?;
  return AppSettings(
    audio: audioJson != null
        ? AudioSettingsJson.fromJson(audioJson)
        : const AudioSettings(),
    library: libraryJson != null
        ? LibrarySettingsJson.fromJson(libraryJson)
        : const LibrarySettings(),
    appearance: appearanceJson != null
        ? AppearanceSettingsJson.fromJson(appearanceJson)
        : const AppearanceSettings(),
  );
});

// ── Audio ───────────────────────────────────────────────────────────────

class AudioSettingsController extends StateNotifier<AudioSettings> {
  AudioSettingsController(this._repository) : super(const AudioSettings()) {
    _load();
  }

  final dynamic _repository;

  Future<void> _load() async {
    try {
      final json = await _repository.kvGet(SettingsKeys.audio) as String?;
      if (json != null && mounted) state = AudioSettingsJson.fromJson(json);
    } catch (_) {}
  }

  Future<void> setReplayGain(ReplayGainPreference mode) async {
    state = state.copyWith(replayGain: mode);
    await _repository.kvSet(SettingsKeys.audio, state.toJson());
  }

  Future<void> setPreampDb(double v) async {
    state = state.copyWith(preampDb: v.clamp(-12.0, 12.0));
    await _repository.kvSet(SettingsKeys.audio, state.toJson());
  }
}

final audioSettingsProvider =
    StateNotifierProvider<AudioSettingsController, AudioSettings>((ref) {
      final repo = ref.watch(libraryRepositoryProvider);
      return AudioSettingsController(repo);
    });

// ── Library ─────────────────────────────────────────────────────────────

class LibrarySettingsController extends StateNotifier<LibrarySettings> {
  LibrarySettingsController(this._repository) : super(const LibrarySettings()) {
    _load();
  }

  final dynamic _repository;

  Future<void> _load() async {
    try {
      final json = await _repository.kvGet(SettingsKeys.library) as String?;
      if (json != null && mounted) state = LibrarySettingsJson.fromJson(json);
    } catch (_) {}
  }

  Future<void> setCleanMissingFilesOnStart(bool v) async {
    state = state.copyWith(cleanMissingFilesOnStart: v);
    await _repository.kvSet(SettingsKeys.library, state.toJson());
  }

  Future<void> setScanOverWiFiOnly(bool v) async {
    state = state.copyWith(scanOverWiFiOnly: v);
    await _repository.kvSet(SettingsKeys.library, state.toJson());
  }
}

final librarySettingsProvider =
    StateNotifierProvider<LibrarySettingsController, LibrarySettings>((ref) {
      final repo = ref.watch(libraryRepositoryProvider);
      return LibrarySettingsController(repo);
    });

// ── Appearance ──────────────────────────────────────────────────────────

class AppearanceSettingsController extends StateNotifier<AppearanceSettings> {
  AppearanceSettingsController(this._repository)
    : super(const AppearanceSettings()) {
    _load();
  }

  final dynamic _repository;

  Future<void> _load() async {
    try {
      final json = await _repository.kvGet(SettingsKeys.appearance) as String?;
      if (json != null && mounted)
        state = AppearanceSettingsJson.fromJson(json);
    } catch (_) {}
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _repository.kvSet(SettingsKeys.appearance, state.toJson());
  }
}

final appearanceSettingsProvider =
    StateNotifierProvider<AppearanceSettingsController, AppearanceSettings>((
      ref,
    ) {
      final repo = ref.watch(libraryRepositoryProvider);
      return AppearanceSettingsController(repo);
    });

final themeModeProvider = Provider<ThemeMode>((ref) {
  final a = ref.watch(appearanceSettingsProvider);
  return switch (a.themeMode) {
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.system => ThemeMode.system,
  };
});

// ── Storage ─────────────────────────────────────────────────────────────

final storageInfoProvider = FutureProvider.autoDispose<StorageInfo>((
  ref,
) async {
  final ingest = ref.watch(ingestServiceProvider);
  final dbSize = await _getFileSize(await _getDatabasePath());
  int artSize = 0;
  int impSize = 0;
  // On Android, imported music lives in MediaStore (not app-controlled files),
  // so importedFilesRoot() is unsupported there. Guard it so storage info still
  // reports the database + artwork cache sizes instead of erroring out.
  Directory? root;
  try {
    root = await ingest.importedFilesRoot();
  } catch (_) {
    root = null;
  }
  if (root != null && await root.exists()) {
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is File) {
        final s = await e.length();
        final name = e.uri.pathSegments.last;
        if (name.contains('_s.png') || name.contains('_l')) {
          artSize += s;
        } else {
          impSize += s;
        }
      }
    }
  }
  return StorageInfo(
    databaseSizeBytes: dbSize,
    artworkCacheSizeBytes: artSize,
    importedMusicSizeBytes: impSize,
    totalSizeBytes: dbSize + artSize + impSize,
  );
});

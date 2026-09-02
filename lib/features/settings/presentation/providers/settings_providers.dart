import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/storage/device_storage_service.dart';
import '../../../../features/library/data/library_repository.dart';
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
    this.device,
  });

  final int databaseSizeBytes;
  final int artworkCacheSizeBytes;
  final int importedMusicSizeBytes;
  final int totalSizeBytes;

  /// Real on-device figures. Null when the platform could not report them
  /// (no native storage handler, partition unreadable) — the card must keep
  /// working from the app-usage figures alone.
  final DeviceStorageInfo? device;

  String get databaseSize => _formatBytes(databaseSizeBytes);
  String get artworkCacheSize => _formatBytes(artworkCacheSizeBytes);
  String get importedMusicSize => _formatBytes(importedMusicSizeBytes);
  String get totalSize => _formatBytes(totalSizeBytes);

  String? get deviceTotalSize =>
      device == null ? null : _formatBytes(device!.totalBytes);
  String? get deviceUsedSize =>
      device == null ? null : _formatBytes(device!.usedBytes);
  String? get deviceAvailableSize =>
      device == null ? null : _formatBytes(device!.availableBytes);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
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
  final repository = ref.watch(libraryRepositoryProvider);
  final audioJson = await repository.kvGet(SettingsKeys.audio);
  final libraryJson = await repository.kvGet(SettingsKeys.library);
  final appearanceJson =
      await repository.kvGet(SettingsKeys.appearance);
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

  final LibraryRepository _repository;

  Future<void> _load() async {
    try {
      final json = await _repository.kvGet(SettingsKeys.audio);
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

  final LibraryRepository _repository;

  Future<void> _load() async {
    try {
      final json = await _repository.kvGet(SettingsKeys.library);
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

  final LibraryRepository _repository;

  Future<void> _load() async {
    try {
      final json = await _repository.kvGet(SettingsKeys.appearance);
      if (json != null && mounted) {
        state = AppearanceSettingsJson.fromJson(json);
      }
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

// ── App version ─────────────────────────────────────────────────────────

/// Reads the installed application version from the platform (e.g. `1.1.6`)
/// so the Settings About section always matches `pubspec.yaml` / the built
/// artifact. Falls back to an empty string (never a hardcoded version) if the
/// platform reports nothing.
final appVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  } catch (_) {
    return '';
  }
});

// ── Storage ─────────────────────────────────────────────────────────────

/// Walks [dir] classifying files as cached artwork (VoraTube's `_s`/`_l`
/// thumbnail suffixes) or imported music. Individual failures are tolerated
/// so a single unreadable or concurrently-deleted file cannot blank the whole
/// card. Public (no leading underscore) so the aggregation layer is unit
/// testable without touching native storage.
Future<(int artBytes, int musicBytes)> measureStorageTree(Directory dir) async {
  var artBytes = 0;
  var musicBytes = 0;
  try {
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      try {
        final bytes = await entity.length();
        final name = entity.uri.pathSegments.last;
        if (name.contains('_s.') || name.contains('_l.')) {
          artBytes += bytes;
        } else {
          musicBytes += bytes;
        }
      } catch (_) {
        // File vanished or is unreadable; it does not invalidate the rest.
      }
    }
  } catch (_) {
    // Directory disappeared or was denied mid-walk.
  }
  return (artBytes, musicBytes);
}

final storageInfoProvider = FutureProvider.autoDispose<StorageInfo>((
  ref,
) async {
  final ingest = ref.watch(ingestServiceProvider);

  // Real device storage first. A platform-channel failure or unreadable
  // partition yields null here; the remaining app-usage numbers still render.
  final device = await DeviceStorageService().getStorageInfo();

  // The database must still contribute honest numbers even when its path is
  // unavailable; a platform-channel failure must never error the whole card.
  int dbSize = 0;
  try {
    dbSize = await _getFileSize(await _getDatabasePath());
  } catch (_) {}

  int artSize = 0;
  int impSize = 0;

  // iOS keeps imported music + embedded artwork in app documents. Android
  // audio lives in MediaStore (no app-controlled files), so this is unsupported
  // there and must be tolerated, not fatal.
  Directory? root;
  try {
    root = await ingest.importedFilesRoot();
  } catch (_) {
    root = null;
  }
  if (root != null && await root.exists()) {
    final measured = await measureStorageTree(root);
    artSize += measured.$1;
    impSize += measured.$2;
  }

  // Android writes native resolved-artwork thumbnails into `<filesDir>/art`,
  // which path_provider surfaces as the app support directory.
  if (Platform.isAndroid && root == null) {
    try {
      final support = await getApplicationSupportDirectory();
      final artDir = Directory('${support.path}${Platform.pathSeparator}art');
      if (await artDir.exists()) {
        final measured = await measureStorageTree(artDir);
        artSize += measured.$1;
      }
    } catch (_) {}
  }

  return StorageInfo(
    databaseSizeBytes: dbSize,
    artworkCacheSizeBytes: artSize,
    importedMusicSizeBytes: impSize,
    totalSizeBytes: dbSize + artSize + impSize,
    device: device,
  );
});

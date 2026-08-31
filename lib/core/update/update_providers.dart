import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../../features/library/data/library_repository.dart';
import '../../../features/library/presentation/providers/library_providers.dart';
import '../../../features/settings/data/settings_models.dart';
import 'update_config.dart';
import 'update_models.dart';
import 'update_service.dart';
import 'update_url_launcher.dart';

/// Standard http client used by the update checker. Injected so tests can
/// substitute a mock without touching the real network.
final updateHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Reads the installed VoraTube version from the real package metadata, e.g.
/// `1.0.0`. Never hardcoded. Falls back to `0.0.0` if metadata is unavailable,
/// which is safe because it only means "no update is forced" or the check
/// skips comparison entirely.
Future<String> installedVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final version = info.version.trim();
    return version.isEmpty ? '0.0.0' : version;
  } catch (_) {
    return '0.0.0';
  }
}

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService(
    client: ref.watch(updateHttpClientProvider),
    installedVersionResolver: installedVersion,
  );
});

final updateUrlLauncherProvider = Provider<UpdateUrlLauncher>((ref) {
  return const UpdateUrlLauncher();
});

/// A decision ready to surface to the user (a dialog), or null when nothing
/// should be shown.
class UpdatePrompt {
  const UpdatePrompt({required this.decision, required this.info});

  final UpdateDecision decision;
  final UpdateInfo info;

  bool get isRequired => decision == UpdateDecision.required;
}

/// Drives the whole update workflow: throttle by persisted last-check time,
/// fetch + decide, and expose exactly one prompt for the UI to display.
class UpdateCheckerController extends StateNotifier<UpdatePrompt?> {
  UpdateCheckerController(
    this._service, {
    required this._kvGet,
    required this._kvSet,
  }) : super(null);

  final UpdateService _service;
  final Future<String?> Function(String) _kvGet;
  final Future<void> Function(String, String) _kvSet;

  /// How often VoraTube checks for updates. Easy to change later.
  Duration get interval => const Duration(hours: 24);

  /// Versions the user dismissed "Later" during this session — they are not
  /// prompted again until the next session (or after the throttle interval).
  final Set<String> _dismissedThisSession = {};

  /// Last successful-check timestamp loaded once at construction. Kept in
  /// memory (a session never lasts 24h without the provider being rebuilt).
  int? persistedLastCheckMs;

  Future<void> run({DateTime? now}) async {
    // Nothing configured → never touch the network.
    if (!UpdateConfig.isConfigured) return;

    final current = now ?? DateTime.now();

    if (!_shouldCheck(current)) return;

    final outcome = await _service.check(now: current);
    if (outcome.isFailure || outcome.info == null) {
      // A failed check must never block the app and does not advance the
      // throttle (so an offline launch can retry next launch).
      return;
    }
    // A successful read (whether an update is due or not) advances the
    // throttle so we don't hammer the server on repeated launches.
    await _rememberCheck(current);

    final prompt = UpdatePrompt(
      decision: outcome.decision,
      info: outcome.info!,
    );
    if (prompt.decision == UpdateDecision.none) return;
    if (_dismissedThisSession.contains(prompt.info.latestVersion)) return;

    state = prompt;
  }

  /// Loads the persisted last-check timestamp. Non-blocking setup; the actual
  /// network check is started separately by the UI once the shell is on screen.
  Future<void> loadPersisted() async {
    try {
      final raw = await _kvGet(SettingsKeys.updateCheck);
      persistedLastCheckMs = int.tryParse(raw ?? '');
    } catch (_) {
      persistedLastCheckMs = null;
    }
  }

  bool _shouldCheck(DateTime now) {
    final lastMs = persistedLastCheckMs;
    if (lastMs == null) return true;
    final lastCheck = DateTime.fromMillisecondsSinceEpoch(lastMs);
    return now.difference(lastCheck) >= interval;
  }

  Future<void> _rememberCheck(DateTime now) async {
    persistedLastCheckMs = now.millisecondsSinceEpoch;
    try {
      await _kvSet(SettingsKeys.updateCheck, '${now.millisecondsSinceEpoch}');
    } catch (_) {
      // Best-effort persistence; a failure only means we may check again
      // sooner than the throttle intends.
    }
  }

  /// Called when the user dismisses the prompt ("Later" or closing the
  /// dialog). Because [run] also gates on the 24h interval, this in-memory
  /// guard only needs to cover the remainder of the current session.
  void dismiss() {
    final prompt = state;
    if (prompt != null) {
      _dismissedThisSession.add(prompt.info.latestVersion);
    }
    state = null;
  }
}

final updateCheckerProvider =
    StateNotifierProvider<UpdateCheckerController, UpdatePrompt?>((ref) {
      final repo = ref.watch(libraryRepositoryProvider);
      final controller = UpdateCheckerController(
        ref.watch(updateServiceProvider),
        kvGet: repo.kvGet,
        kvSet: repo.kvSet,
      );
      // Non-blocking: hydrate the throttle timestamp from the KV store.
      unawaited(Future<void>.microtask(() => controller.loadPersisted()));
      return controller;
    });

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'update_config.dart';
import 'update_models.dart';
import 'version_compare.dart';

/// Fetches and validates the remotely hosted version file and decides whether
/// an update is warranted.
///
/// All error paths return [UpdateCheckOutcome.failed] — the app never throws,
/// so an unreachable server, airplane mode, an HTTP error or malformed JSON can
/// never block playback or any other feature.
class UpdateService {
  UpdateService({
    required http.Client client,
    required Future<String> Function() installedVersionResolver,
    this.requestTimeout = const Duration(seconds: 10),
    this.maxReleaseNotes = 8,
    this.maxNoteLength = 200,
  }) : _client = client,
       _installedVersionResolver = installedVersionResolver;

  final http.Client _client;
  final Future<String> Function() _installedVersionResolver;
  final Duration requestTimeout;

  /// Hard caps so an accidentally huge response cannot destroy the dialog UI.
  final int maxReleaseNotes;
  final int maxNoteLength;

  /// Runs one full update check. Never throws.
  Future<UpdateCheckOutcome> check({DateTime? now}) async {
    now ??= DateTime.now();

    // No real distribution source configured yet → behave as "nothing to do".
    if (!UpdateConfig.isConfigured) {
      return UpdateCheckOutcome.failed(
        StateError('Update source is not configured'),
      );
    }

    final AppVersion installed;
    try {
      installed = AppVersion.tryParse(await _installedVersionResolver());
    } catch (_) {
      return UpdateCheckOutcome.failed(
        StateError('Could not read installed version'),
      );
    }

    final UpdateInfo? info;
    try {
      info = await _fetchInfo(now);
    } catch (e) {
      return UpdateCheckOutcome.failed(e);
    }
    if (info == null) {
      return UpdateCheckOutcome.failed(
        const FormatException('Invalid version payload'),
      );
    }

    return UpdateCheckOutcome.decided(
      decision: decideUpdate(installed: installed, info: info),
      info: info,
    );
  }

  /// Downloads and parses the version file, or returns null when the payload
  /// cannot be validated (malformed JSON, missing/invalid latestVersion).
  Future<UpdateInfo?> _fetchInfo(DateTime now) async {
    final uri = Uri.tryParse(UpdateConfig.effectiveVersionJsonUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return null;
    }

    final response = await _client.get(uri).timeout(requestTimeout);
    if (response.statusCode != 200) {
      return null;
    }

    return parseUpdateInfo(response.body);
  }

  /// Parser separated for direct unit testing. Tolerates missing/malformed
  /// fields without throwing:
  ///   * missing latestVersion / invalid latestVersion → null (skip update)
  ///   * missing minimumVersion → treated as "0.0.0" (no enforced minimum)
  ///   * missing/excess release notes → trimmed to the configured caps
  UpdateInfo? parseUpdateInfo(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;

      final latestRaw = decoded['latestVersion'];
      if (latestRaw is! String || latestRaw.trim().isEmpty) return null;
      final latest = AppVersion.tryParse(latestRaw);
      if (latest.isEmpty) return null;

      final minimumRaw = decoded['minimumVersion'];
      final minimum = minimumRaw is String && minimumRaw.trim().isNotEmpty
          ? AppVersion.tryParse(minimumRaw)
          : AppVersion.tryParse('0.0.0');

      final notes = <String>[];
      final rawNotes = decoded['releaseNotes'];
      if (rawNotes is List) {
        for (final item in rawNotes.take(maxReleaseNotes)) {
          if (item is String && item.trim().isNotEmpty) {
            notes.add(_truncate(item.trim(), maxNoteLength));
          }
        }
      }

      return UpdateInfo(
        latestVersion: latest.toString(),
        minimumVersion: minimum.toString(),
        releaseNotes: notes,
      );
    } catch (_) {
      // jsonDecode or type errors → invalid payload.
      return null;
    }
  }

  static String _truncate(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);
}

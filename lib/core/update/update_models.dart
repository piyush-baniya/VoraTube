import 'package:meta/meta.dart';

import 'version_compare.dart';

/// Which action, if any, the update system should ask the user to take.
enum UpdateDecision { none, optional, required }

/// Parsed, validated remote version information.
@immutable
class UpdateInfo {
  const UpdateInfo({
    required this.latestVersion,
    required this.minimumVersion,
    this.releaseNotes = const <String>[],
  });

  final String latestVersion;
  final String minimumVersion;

  /// Displayed verbatim. Kept small by the parser so an oversized response
  /// cannot blow up the dialog.
  final List<String> releaseNotes;

  bool get hasReleaseNotes => releaseNotes.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'latestVersion': latestVersion,
        'minimumVersion': minimumVersion,
        'releaseNotes': releaseNotes,
      };
}

/// The outcome of a completed (or aborted) update check.
@immutable
class UpdateCheckOutcome {
  const UpdateCheckOutcome({required this.decision, this.info, this.error});

  /// No update is warranted.
  const UpdateCheckOutcome.none()
    : decision = UpdateDecision.none,
      info = null,
      error = null;

  /// The check failed (network, malformed JSON, unconfigured source, …). The
  /// app must simply continue normally.
  factory UpdateCheckOutcome.failed(Object error) =>
      UpdateCheckOutcome(decision: UpdateDecision.none, error: error);

  /// A decision was reached and [info] is available to present.
  factory UpdateCheckOutcome.decided({
    required UpdateDecision decision,
    required UpdateInfo info,
  }) => UpdateCheckOutcome(decision: decision, info: info);

  final UpdateDecision decision;
  final UpdateInfo? info;
  final Object? error;

  bool get isFailure => error != null;
}

/// Decides what to do given the installed version and the remote info.
///
/// * installed >= latest            → none
/// * installed < minimum            → required
/// * otherwise (installed < latest) → optional
UpdateDecision decideUpdate({
  required AppVersion installed,
  required UpdateInfo info,
}) {
  final latest = AppVersion.tryParse(info.latestVersion);
  final minimum = AppVersion.tryParse(info.minimumVersion);

  if (installed.compareTo(latest) >= 0) {
    return UpdateDecision.none;
  }
  if (installed.compareTo(minimum) < 0) {
    return UpdateDecision.required;
  }
  return UpdateDecision.optional;
}

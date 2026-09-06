import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/audio_util_service.dart';
import '../domain/ringtone_selection.dart';

/// Result of a completed "set as ringtone" invocation, distilled so the UI can
/// show the right feedback without reaching into platform-specific details.
enum SetRingtoneOutcome {
  /// The clip was assigned as the device's default ringtone.
  assigned,

  /// The clip was exported but the app is missing the "modify system settings"
  /// permission, so assignment was not attempted. The UI must ask for it.
  permissionRequired,

  /// Assignment failed and no retry is possible without user action first.
  failed,
}

/// Owns the trimming state machine for the [RingtoneCutterScreen]: selection
/// state, export execution and the set-as-ringtone flow.
///
/// The controller is a plain [ChangeNotifier] so the screen stays a thin view
/// and the core behavior (selection clamping, duplicate-export prevention,
/// failure handling, cleanup) is unit-testable with a fake [AudioUtilService] —
/// no device or method channel required.
class RingtoneCutterController extends ChangeNotifier {
  RingtoneCutterController({
    required AudioUtilService service,
    required int durationMs,
    Duration cutProgressPollInterval = const Duration(milliseconds: 80),
  }) : _service = service,
       _selection = RingtoneSelection.forTrack(durationMs: durationMs),
       _cutProgressPollInterval = cutProgressPollInterval;

  final AudioUtilService _service;

  final Duration _cutProgressPollInterval;

  RingtoneSelection _selection;
  RingtoneSelection get selection => _selection;

  bool get hasTrack => _selection.total > Duration.zero;

  /// True while an export (or a set-as-ringtone that includes an export) is in
  /// flight. Guards against duplicate operations and disables the save actions.
  bool _busy = false;
  bool get isBusy => _busy;

  /// Latest [AudioUtilService.cutProgress] snapshot reported while exporting,
  /// in 0..1. Meaningful only while [isBusy]; treated as 0 when idle.
  double _cutProgress = 0;
  double get cutProgress => _busy ? _cutProgress : 0;

  /// The most recent successful export, cleared when the selection changes so
  /// stale output is never presented as current.
  AudioCutResult? _lastExport;
  AudioCutResult? get lastExport => _lastExport;

  /// Snapshot of the last set-ringtone outcome, null until a picker closes.
  SetRingtoneOutcome? _lastSetRingtoneOutcome;
  SetRingtoneOutcome? get lastSetRingtoneOutcome => _lastSetRingtoneOutcome;

  /// The last failure reason (a safe, user-presentable message), null when
  /// everything succeeded.
  String? _lastError;
  String? get lastError => _lastError;

  /// Source URI of the track being trimmed; attached by the screen on open.
  String _sourceUri = '';

  /// Song title used to derive the output filename; attached by the screen.
  String _title = 'Ringtone';

  /// True once [attachTrack] has provided a usable source.
  bool _sourceAttached = false;
  bool get hasSource => _sourceAttached && _sourceUri.isNotEmpty;

  void setStartMs(int ms) {
    _selection = _selection.withStart(ms);
    _lastExport = null;
    notifyListeners();
  }

  void setEndMs(int ms) {
    _selection = _selection.withEnd(ms);
    _lastExport = null;
    notifyListeners();
  }

  void selectAll() {
    _selection = _selection.selectAll();
    _lastExport = null;
    notifyListeners();
  }

  /// Shifts the whole window by [deltaMs], preserving its length and the
  /// selection invariants (used by the fine-tune "shift" control).
  void shiftBy(int deltaMs) {
    if (!_selection.isValid) return;
    final total = _selection.total.inMilliseconds;
    final len = _selection.duration.inMilliseconds;
    final minStart = 0;
    final maxStart = total - len;
    final newStart = (_selection.start.inMilliseconds + deltaMs).clamp(
      minStart,
      maxStart,
    );
    final next = RingtoneSelection.forTrack(durationMs: total)
        .withStart(newStart)
        .withEnd(newStart + len);
    _selection = next;
    _lastExport = null;
    notifyListeners();
  }

  /// Wire-up so the screen can attach the track being trimmed before the user
  /// triggers an export.
  void attachTrack({required String sourceUri, required String title}) {
    _sourceUri = sourceUri;
    _title = title.isEmpty ? 'Ringtone' : title;
    _sourceAttached = true;
  }

  /// Exports the current selection to a ringtone clip.
  ///
  /// Throws a [RingtoneOperationException] on failure, or if an export is
  /// already running (duplicate-prevention guard). Returns the produced clip on
  /// success.
  Future<AudioCutResult> export() async {
    if (_busy) {
      throw const RingtoneOperationException(
        'busy',
        'The export is already in progress.',
      );
    }
    if (!_selection.isUsable) {
      throw const RingtoneOperationException(
        'invalid_range',
        'The selected range is outside the track.',
      );
    }
    if (!hasSource) {
      throw const RingtoneOperationException(
        'missing_source',
        'The original audio file is no longer available.',
      );
    }
    _busy = true;
    _lastError = null;
    _cutProgress = 0;
    notifyListeners();
    unawaited(_pollCutProgress());
    try {
      final result = await _service.cutAudio(
        sourceUri: _sourceUri,
        startMs: _selection.start.inMilliseconds,
        endMs: _selection.end.inMilliseconds,
        songTitle: _title,
      );
      _lastExport = result;
      return result;
    } on RingtoneOperationException catch (e) {
      _lastError = e.message;
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Polls the native cut progress while an export is in flight so listeners
  /// (the progress bar) stay current without blocking the export itself.
  Future<void> _pollCutProgress() async {
    while (_busy) {
      double p = 0;
      try {
        p = await _service.cutProgress();
      } catch (_) {
        // Ignore transient poll errors; treat as "no progress yet".
      }
      final next = p.clamp(0.0, 1.0);
      if (next != _cutProgress) {
        _cutProgress = next;
        notifyListeners();
      }
      if (!_busy) break;
      await Future<void>.delayed(_cutProgressPollInterval);
    }
  }

  /// Exports the selection and, when it produced a MediaStore-registered clip,
  /// sets it as the device's default ringtone directly (no system picker is
  /// launched). Resolves with the published outcome; never falsely reports
  /// success — if the clip cannot be registered or assigned the outcome is
  /// [SetRingtoneOutcome.failed].
  Future<SetRingtoneOutcome> setAsRingtone() async {
    try {
      await export();
    } catch (_) {
      // export() already recorded the error.
      return SetRingtoneOutcome.failed;
    }
    return assignExportedClip();
  }

  /// Assigns the most recent export ([lastExport]) as the device ringtone.
  ///
  /// Extracted from [setAsRingtone] so the screen can re-attempt the
  /// assignment (without re-encoding) right after the user returns from the
  /// system "modify system settings" screen. When the permission is still
  /// missing the outcome is [SetRingtoneOutcome.permissionRequired] and
  /// nothing is assigned.
  Future<SetRingtoneOutcome> assignExportedClip() async {
    final clip = _lastExport;
    if (clip == null || !clip.hasContentUri) {
      _lastSetRingtoneOutcome = SetRingtoneOutcome.failed;
      _lastError = 'This device could not register the clip as a ringtone.';
      notifyListeners();
      return SetRingtoneOutcome.failed;
    }
    if (!await _service.canWriteSettings()) {
      _lastError = RingtoneOperationException.describe('write_settings_denied');
      _lastSetRingtoneOutcome = SetRingtoneOutcome.permissionRequired;
      notifyListeners();
      return SetRingtoneOutcome.permissionRequired;
    }
    try {
      await _service.setDefaultRingtone(clip.contentUri);
      _lastSetRingtoneOutcome = SetRingtoneOutcome.assigned;
      notifyListeners();
      return _lastSetRingtoneOutcome!;
    } on RingtoneOperationException catch (e) {
      _lastError = e.message;
      _lastSetRingtoneOutcome = SetRingtoneOutcome.failed;
      notifyListeners();
      return SetRingtoneOutcome.failed;
    }
  }

  /// Resets transient result/error state (used when re-presenting dialogs)
  /// without touching the selection.
  void clearTransientState() {
    _lastError = null;
    _lastSetRingtoneOutcome = null;
    notifyListeners();
  }
}

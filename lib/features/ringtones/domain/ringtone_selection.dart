/// A validated, clamped start/end window selected from a source track.
///
/// This type owns all trimming invariants so the UI and export path can never
/// produce an impossible range:
///
///  * `start` is never negative,
///  * `end` never exceeds [total],
///  * `start` is always strictly before [end],
///  * the selected length is never below [minimumDuration] nor above [total].
///
/// Mutation is functional: every operation returns a new [RingtoneSelection]
/// rather than mutating in place, so the value stays safe to share across
/// preview and export without aliasing surprises.
class RingtoneSelection {
  RingtoneSelection._(this.start, this.end, this.total);

  /// Creates a selection from a track duration. When [durationMs] is not
  /// positive the track is treated as unusable and both bounds are zero.
  factory RingtoneSelection.forTrack({required int durationMs}) {
    final total = durationMs > 0 ? durationMs : 0;
    return RingtoneSelection._(
      Duration.zero,
      Duration(milliseconds: total),
      Duration(milliseconds: total),
    );
  }

  /// The shortest clip the user may keep selected (ms). Large enough to remain
  /// useful as a ringtone while not fighting casual handle dragging.
  static const int minimumSelectionMs = 1000;

  static const Duration minimumDuration = Duration(
    milliseconds: minimumSelectionMs,
  );

  final Duration start;
  final Duration end;
  final Duration total;

  /// True when the track is usable at all and the window is well formed.
  bool get isValid => total > Duration.zero && end > start;

  /// True when the window is well formed and long enough to export.
  bool get isUsable =>
      total > Duration.zero &&
      end <= total &&
      start >= Duration.zero &&
      duration >= minimumDuration;

  Duration get duration => end - start;

  /// Whether [moment] falls inside the selected window (preview loop use).
  bool contains(Duration moment) => moment >= start && moment < end;

  /// Moves the start bound. [offerMs] is clamped so the result stays valid:
  /// the start never drops below 0 and never reaches [end] (minimum duration
  /// always preserved).
  RingtoneSelection withStart(int offerMs) {
    if (!isValid) return this;
    final raw = offerMs.clamp(0, end.inMilliseconds);
    final maxStart = end.inMilliseconds - minimumSelectionMs;
    final clamped = raw.clamp(0, maxStart);
    return RingtoneSelection._(Duration(milliseconds: clamped), end, total);
  }

  /// Moves the end bound. [offerMs] is clamped so the result stays valid:
  /// the end never exceeds [total] and never reaches [start].
  RingtoneSelection withEnd(int offerMs) {
    if (!isValid) return this;
    final minEnd = start.inMilliseconds + minimumSelectionMs;
    final clamped = offerMs.clamp(minEnd, total.inMilliseconds);
    return RingtoneSelection._(start, Duration(milliseconds: clamped), total);
  }

  /// Selects the whole available track.
  RingtoneSelection selectAll() {
    if (!isValid) return this;
    return RingtoneSelection._(Duration.zero, total, total);
  }

  /// Formats [d] as `m:ss` (ceiling of the millisecond value). Rounded up so a
  /// 0.4s fragment reads as visible progress rather than silently vanishing.
  static String formatCeil(Duration d) {
    final totalSec = (d.inMilliseconds / 1000).ceil();
    final m = (totalSec ~/ 60).toString();
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

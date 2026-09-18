import 'dart:math' as math;

/// The fixed set of virtual equalizer bands shared by every device.
///
/// VoraTube stores EQ curves over these 10 frequencies no matter how many
/// physical bands the device's Android equalizer actually exposes. The stored
/// curve is mapped onto the device's real bands at apply time via
/// [mapVirtualCurveToBands], so a preset (e.g. "Rock") sounds consistent across
/// phones with different equalizer hardware.
const int eqVirtualBandCount = 10;

/// Approximate center frequencies (Hz) of the 10 virtual bands, low→high.
const List<double> kEqVirtualBandFrequencies = [
  31,
  62,
  125,
  250,
  500,
  1000,
  2000,
  4000,
  8000,
  16000,
];

/// Gain hint range (dB) offered for the virtual bands.
const double kEqLevelMin = -12.0;
const double kEqLevelMax = 12.0;

/// Which equalizer interface the user is working in.
///
/// Both modes edit the exact same underlying curve and settings — switching
/// modes never changes the sound, only how much control is exposed.
enum EqMode {
  simple('Simple'),
  advanced('Advanced');

  const EqMode(this.label);

  final String label;
}

/// The selectable playback speeds, in the exact display order. Slower than
/// real-time helps audio books and language learners; 2x is the usual ceiling.
const List<double> kPlaybackSpeeds = [0.25, 0.5, 1.0, 1.5, 2.0];

/// Default playback speed (natural).
const double kDefaultPlaybackSpeed = 1.0;

/// Lower/upper bounds applied to any requested speed.
const double kPlaybackSpeedMin = 0.25;
const double kPlaybackSpeedMax = 2.0;

/// Default crossfade duration in seconds.
const int kDefaultCrossfadeSeconds = 4;

/// Supported crossfade duration window (seconds).
const int kCrossfadeSecondsMin = 2;
const int kCrossfadeSecondsMax = 12;

/// Default audio balance: perfectly centered.
const double kDefaultAudioBalance = 0.0;

/// Clamps an equalizer gain into the supported virtual band range (dB).
double clampEqLevel(double value) =>
    value.clamp(kEqLevelMin, kEqLevelMax).toDouble();

/// Clamps a crossfade duration (seconds) into the supported window.
int clampCrossfadeSeconds(int seconds) =>
    seconds.clamp(kCrossfadeSecondsMin, kCrossfadeSecondsMax);

/// Clamps an audio balance value into `[-1.0 (full left), +1.0 (full right)]`.
double clampAudioBalance(double value) => value.clamp(-1.0, 1.0).toDouble();

/// Normalizes a custom level list to exactly [eqVirtualBandCount] entries,
/// padding with 0 dB and clipping out-of-range values. Persisted custom
/// curves always pass through here before being stored or applied.
List<double> normalizeEqLevels(List<double> levels) {
  final result = <double>[];
  for (var i = 0; i < eqVirtualBandCount; i++) {
    if (i < levels.length) {
      result.add(clampEqLevel(levels[i]));
    } else {
      result.add(0.0);
    }
  }
  return result;
}

/// One-tap equalizer curve presets.
///
/// Each preset is a fixed 10-band dB curve over [kEqVirtualBandFrequencies].
/// [custom] is the "user is dragging the sliders" state; its stored curve
/// always lives in settings and is neutral here.
enum EqPreset {
  flat('Flat', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  rock('Rock', [4.5, 3.5, 2.0, 0.5, -0.5, -0.5, 1.0, 2.5, 4.0, 5.0]),
  pop('Pop', [0.5, 1.0, 2.0, 3.0, 2.0, 0.0, -0.5, -1.0, 0.0, 1.0]),
  hipHop('Hip Hop', [5.0, 4.0, 3.0, 1.0, -0.5, -1.0, 0.0, 1.0, 2.0, 3.0]),
  jazz('Jazz', [4.0, 3.0, 2.0, 1.0, -0.5, -0.5, 1.0, 2.0, 3.0, 3.5]),
  electronic('Electronic', [5.0, 3.0, 1.0, 0.0, 0.0, 1.0, 3.0, 4.0, 4.0, 3.0]),
  bassBoost('Bass Boost', [6.0, 5.0, 4.0, 2.0, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0]),
  custom('Custom', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);

  const EqPreset(this.label, this.levels);

  /// User-facing preset name.
  final String label;

  /// The 10-band dB curve this preset maps to. [EqPreset.custom] holds a
  /// neutral curve; the real custom levels live in persisted settings.
  final List<double> levels;
}

/// How one track hands over to the next.
///
/// [crossfade] is the default: the outgoing track's volume ramps down while the
/// incoming one ramps up, so songs blend smoothly at the boundary. [gapless]
/// swaps instantly with no fade. [off] also swaps instantly but is the explicit
/// "no transition effect" setting (kept distinct so the preference reads
/// clearly). Crossfade and Gapless are mutually exclusive — selecting either
/// clears the other — and both can be turned off at the same time.
enum PlaybackTransitionMode {
  crossfade,
  gapless,
  off;

  String get label => switch (this) {
    PlaybackTransitionMode.crossfade => 'Crossfade',
    PlaybackTransitionMode.gapless => 'Gapless',
    PlaybackTransitionMode.off => 'Off',
  };
}

/// Maps a 10-band virtual curve onto the device equalizer's physical bands.
///
/// For each device band we look at its reported center frequency and read the
/// virtual curve at that frequency (log-frequency linear interpolation between
/// the nearest virtual bands). Devices with fewer/more bands still follow the
/// same stored curve, so presets and custom curves stay device-independent.
/// Each result is clamped to the device's [minDb]..[maxDb] supported range.
List<double> mapVirtualCurveToBands({
  required List<double> virtualLevels,
  required List<double> centerFrequencies,
  double minDb = kEqLevelMin,
  double maxDb = kEqLevelMax,
}) {
  final levels = normalizeEqLevels(virtualLevels);
  final frequencies = kEqVirtualBandFrequencies;
  return [
    for (final centerFrequency in centerFrequencies)
      _readVirtualCurve(
        levels,
        frequencies,
        centerFrequency,
      ).clamp(minDb, maxDb).toDouble(),
  ];
}

/// Reads [levels] (defined over [frequencies], both ascending) at [frequency]
/// using log-frequency linear interpolation.
double _readVirtualCurve(
  List<double> levels,
  List<double> frequencies,
  double frequency,
) {
  if (frequency <= frequencies.first) {
    return levels.first;
  }
  if (frequency >= frequencies.last) {
    return levels.last;
  }
  final target = math.log(frequency);
  for (var i = 0; i < frequencies.length - 1; i++) {
    final f0 = math.log(frequencies[i]);
    final f1 = math.log(frequencies[i + 1]);
    if (target <= f1) {
      final t = (target - f0) / (f1 - f0);
      return levels[i] + (levels[i + 1] - levels[i]) * t;
    }
  }
  return levels.last;
}

/// Simple-mode macro controls. Each one writes directly to a fixed group of
/// real virtual bands, so a quick control and the advanced band editor stay a
/// single source of truth (no double-processing, no hidden second curve).
enum EqQuickControl {
  subBass('Sub Bass', [0, 1]),
  bass('Bass', [1, 2, 3]),
  vocalClarity('Vocal Clarity', [5, 6, 7]),
  treble('Treble', [7, 8, 9]);

  const EqQuickControl(this.label, this.bandIndices);

  final String label;

  /// Indices into [kEqVirtualBandFrequencies] this control drives.
  final List<int> bandIndices;
}

/// The current average gain of a quick control's band group, used to position
/// its slider over a curve that may have been shaped in advanced mode.
double eqQuickControlValue(List<double> levels, EqQuickControl control) {
  final normalized = normalizeEqLevels(levels);
  var sum = 0.0;
  for (final index in control.bandIndices) {
    sum += normalized[index];
  }
  return sum / control.bandIndices.length;
}

/// Applies a quick control's value to every band it owns, returning a new
/// normalized curve. Other bands are left untouched.
List<double> applyEqQuickControl(
  List<double> levels,
  EqQuickControl control,
  double value,
) {
  final result = normalizeEqLevels(levels);
  final clamped = clampEqLevel(value);
  for (final index in control.bandIndices) {
    result[index] = clamped;
  }
  return result;
}

/// The largest positive (boost) gain in [levels], or 0 when the curve only
/// cuts. This is the headroom a flat preamp would overrun.
double maxEqBoostDb(List<double> levels) {
  var max = 0.0;
  for (final level in normalizeEqLevels(levels)) {
    if (level > max) max = level;
  }
  return max;
}

/// The preamp (dB, never positive) that would keep a boosted curve's loudest
/// band at or below 0 dBFS. Returns 0.0 for cuts/flat curves.
double suggestedPreampDb(List<double> levels) {
  final boost = maxEqBoostDb(levels);
  if (boost <= 0) return 0.0;
  return clampEqLevel(-boost);
}

/// The curve that is actually heard for the current settings: a preset's fixed
/// levels, or the persisted custom levels when [preset] is [EqPreset.custom].
List<double> effectiveEqLevels({
  required EqPreset preset,
  required List<double> customLevels,
}) => preset == EqPreset.custom
    ? normalizeEqLevels(customLevels)
    : List<double>.from(preset.levels);

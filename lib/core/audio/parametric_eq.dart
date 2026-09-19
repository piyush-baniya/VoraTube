import 'dart:math' as math;

/// Filter topologies supported by the parametric equalizer. Each band is
/// implemented with a second-order biquad using RBJ cookbook coefficients.
///
/// DSP truth lives here in Dart: the native Media3 processor only applies the
/// coefficients it receives, and every curve/preset feature uses these exact
/// formulas, keeping the UI, the maths tests and the audio path in lockstep.
enum ParametricFilterType { peaking, lowShelf, highShelf, lowPass, highPass }

enum EqEngineMode { graphic, parametric }

const int parametricMaxBands = 10;
const double parametricMinFrequencyHz = 20;
const double parametricMaxGainDb = 12;
const double parametricMinQ = 0.1;
const double parametricMaxQ = 10;

class ParametricEqBand {
  ParametricEqBand({
    required this.id,
    this.enabled = true,
    this.type = ParametricFilterType.peaking,
    this.frequencyHz = 1000,
    this.gainDb = 0,
    this.q = 1,
  });

  String id;
  bool enabled;
  ParametricFilterType type;
  double frequencyHz;
  double gainDb;
  double q;

  ParametricEqBand copyWith({
    String? id,
    bool? enabled,
    ParametricFilterType? type,
    double? frequencyHz,
    double? gainDb,
    double? q,
  }) {
    return ParametricEqBand(
      id: id ?? this.id,
      enabled: enabled ?? this.enabled,
      type: type ?? this.type,
      frequencyHz: frequencyHz ?? this.frequencyHz,
      gainDb: gainDb ?? this.gainDb,
      q: q ?? this.q,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'enabled': enabled,
      'type': type.name,
      'f': frequencyHz,
      'g': gainDb,
      'q': q,
    };
  }

  /// Coeff clamp strategy: frequency and Q are bounded coarsely here but the
  /// DSP honors 0.45·sampleRate as the ultimate frequency ceiling.
  void clampToDspBounds({double? sampleRate}) {
    frequencyHz = clampedFrequency(frequencyHz, sampleRate: sampleRate);
    q = q.clamp(parametricMinQ, parametricMaxQ).toDouble();
    gainDb = gainDb.clamp(-parametricMaxGainDb, parametricMaxGainDb).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParametricEqBand &&
          other.id == id &&
          other.enabled == enabled &&
          other.type == type &&
          other.frequencyHz == frequencyHz &&
          other.gainDb == gainDb &&
          other.q == q;

  @override
  int get hashCode => Object.hash(id, enabled, type, frequencyHz, gainDb, q);
}

class ParametricEqPreset {
  ParametricEqPreset({
    required this.id,
    required this.name,
    this.pinned = false,
    this.bands = const [],
  });

  String id;
  String name;
  bool pinned;
  List<ParametricEqBand> bands;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'pinned': pinned,
      'bands': bands.map((b) => b.toJson()).toList(),
    };
  }
}

double clampedFrequency(double frequencyHz, {double? sampleRate}) {
  final ceiling = sampleRate == null || sampleRate <= 0
      ? 0.45 * 48000.0
      : 0.45 * sampleRate;
  return frequencyHz.clamp(parametricMinFrequencyHz, ceiling).toDouble();
}

/// Biquad coefficients `[b0, b1, b2, a1, a2]` for one band at [sampleRate].
/// The native pipeline computes `y = b0·x + b1·x1 + b2·x2 − a1·y1 − a2·y2`.
List<double> parametricBandCoeffs(
  ParametricEqBand band, {
  required int sampleRate,
}) {
  if (sampleRate <= 0) return const [1, 0, 0, 0, 0];
  final f = clampedFrequency(
    band.frequencyHz,
    sampleRate: sampleRate.toDouble(),
  );
  if (f >= 0.45 * sampleRate || f <= 0) return const [1, 0, 0, 0, 0];
  final q = band.q.clamp(parametricMinQ, parametricMaxQ).toDouble();
  final wr = 2 * math.pi * f / sampleRate;
  final cosW = math.cos(wr);
  final sinW = math.sin(wr);
  final S = q;
  final alpha = sinW / (2 * S);

  final double b0;
  final double b1;
  final double b2;
  final double a0;
  final double a1;
  final double a2;

  switch (band.type) {
    case ParametricFilterType.peaking:
      final A = math.pow(10, band.gainDb / 40);
      b0 = 1 + alpha * A;
      b1 = -2 * cosW;
      b2 = 1 - alpha * A;
      a0 = 1 + alpha / A;
      a1 = -2 * cosW;
      a2 = 1 - alpha / A;
    case ParametricFilterType.lowShelf:
      final A = math.pow(10, band.gainDb / 40);
      final s = 2 * math.sqrt(A) * alpha;
      b0 = A * ((A + 1) - (A - 1) * cosW + s);
      b1 = 2 * A * ((A - 1) - (A + 1) * cosW);
      b2 = A * ((A + 1) - (A - 1) * cosW - s);
      a0 = (A + 1) + (A - 1) * cosW + s;
      a1 = -2 * ((A - 1) + (A + 1) * cosW);
      a2 = (A + 1) + (A - 1) * cosW - s;
    case ParametricFilterType.highShelf:
      final A = math.pow(10, band.gainDb / 40);
      final s = 2 * math.sqrt(A) * alpha;
      b0 = A * ((A + 1) + (A - 1) * cosW + s);
      b1 = -2 * A * ((A - 1) + (A + 1) * cosW);
      b2 = A * ((A + 1) + (A - 1) * cosW - s);
      a0 = (A + 1) - (A - 1) * cosW + s;
      a1 = 2 * ((A - 1) - (A + 1) * cosW);
      a2 = (A + 1) - (A - 1) * cosW - s;
    case ParametricFilterType.lowPass:
      b0 = (1 - cosW) / 2;
      b1 = 1 - cosW;
      b2 = (1 - cosW) / 2;
      a0 = 1 + alpha;
      a1 = -2 * cosW;
      a2 = 1 - alpha;
    case ParametricFilterType.highPass:
      b0 = (1 + cosW) / 2;
      b1 = -(1 + cosW);
      b2 = (1 + cosW) / 2;
      a0 = 1 + alpha;
      a1 = -2 * cosW;
      a2 = 1 - alpha;
  }

  final inv = 1 / a0;
  return [b0 * inv, b1 * inv, b2 * inv, a1 * inv, a2 * inv];
}

/// Response (dB) of a single band at [frequencyHz] for [sampleRate].
double parametricBandResponseDb(
  List<double> coeffs,
  double frequencyHz, {
  required int sampleRate,
}) {
  if (sampleRate <= 0 || frequencyHz >= 0.45 * sampleRate) return 0;
  final wr = 2 * math.pi * frequencyHz / sampleRate;
  final reZ = math.cos(wr);
  final imZ = -math.sin(wr);
  final reZ2 = math.cos(2 * wr);
  final imZ2 = -math.sin(2 * wr);
  final numRe = coeffs[0] + coeffs[1] * reZ + coeffs[2] * reZ2;
  final numIm = coeffs[1] * imZ + coeffs[2] * imZ2;
  final denRe = 1 + coeffs[3] * reZ + coeffs[4] * reZ2;
  final denIm = coeffs[3] * imZ + coeffs[4] * imZ2;
  final n = math.sqrt(numRe * numRe + numIm * numIm);
  final d = math.sqrt(denRe * denRe + denIm * denIm);
  if (d == 0 || n == 0) return 0;
  return 20 * math.log(n / d) / math.ln10;
}

/// Combined response curve (dB) for a logarithmic sweep across
/// [parametricMinFrequencyHz]..ceiling at [pointCount] points per octave step.
List<double> parametricResponseCurve(
  List<ParametricEqBand> bands, {
  required int sampleRate,
  int pointCount = 64,
}) {
  if (sampleRate <= 0) return List.filled(pointCount, 0);
  final freqs = List<double>.generate(pointCount, (i) {
    final minF = math.log(parametricMinFrequencyHz);
    final maxF = math.log(
      clampedFrequency(20000, sampleRate: sampleRate.toDouble()),
    );
    return math.exp(minF + (maxF - minF) * i / (pointCount - 1));
  });
  return [
    for (final f in freqs)
      bands.where((b) => b.enabled).fold(0.0, (sum, b) {
        return sum +
            parametricBandResponseDb(
              parametricBandCoeffs(b, sampleRate: sampleRate),
              f,
              sampleRate: sampleRate,
            );
      }),
  ];
}

/// Flattened per-band coefficient order sent to the native bridge, plus the
/// enabled flag for each band.
List<Map<String, Object?>> parametricNativeBands(
  List<ParametricEqBand> bands, {
  required int sampleRate,
}) {
  return [
    for (final band in bands)
      {
        'enabled': band.enabled,
        'coeffs': parametricBandCoeffs(band, sampleRate: sampleRate),
      },
  ];
}

String parametricBandsToJson(List<ParametricEqBand> bands) {
  return '[${bands.map((b) {
    final json = b.toJson();
    final parts = <String>[];
    json.forEach((key, value) {
      if (value is String) {
        parts.add('"$key": "$value"');
      } else if (value is bool) {
        parts.add('"$key": $value');
      } else {
        parts.add('"$key": ${(value as num).toString()}');
      }
    });
    return '{${parts.join(', ')}}';
  }).join(', ')}]';
}

List<ParametricEqBand> parametricBandsFromJson(String json) {
  final match = RegExp(r'"parametricBands"\s*:\s*(\[[^\]]*\])')
      .firstMatch(json);
  if (match == null) return const [];
  final content = match.group(1)!;
  if (content == '[]') return const [];
  final inner = content.substring(1, content.length - 1);
  final chunks = inner.split(RegExp(r'\},\s*\{'));
  final bands = <ParametricEqBand>[];
  for (var i = 0; i < chunks.length; i++) {
    final chunk = chunks[i].trim();
    final id = RegExp(r'"id"\s*:\s*"([\w\-]+)"').firstMatch(chunk)?.group(1);
    final enabled =
        RegExp(r'"enabled"\s*:\s*(true|false)').firstMatch(chunk)?.group(1) ==
        'true';
    final typeName = RegExp(r'"type"\s*:\s*"(\w+)"')
        .firstMatch(chunk)
        ?.group(1);
    final freq = double.tryParse(
      RegExp(r'"f"\s*:\s*([\d\.\-]+)').firstMatch(chunk)?.group(1) ?? '',
    );
    final gain = double.tryParse(
      RegExp(r'"g"\s*:\s*([\d\.\-]+)').firstMatch(chunk)?.group(1) ?? '',
    );
    final q = double.tryParse(
      RegExp(r'"q"\s*:\s*([\d\.\-]+)').firstMatch(chunk)?.group(1) ?? '',
    );
    final type = ParametricFilterType.values.firstWhere(
      (e) => e.name == (typeName ?? ''),
      orElse: () => ParametricFilterType.peaking,
    );
    if (id == null || freq == null || gain == null || q == null) continue;
    bands.add(
      ParametricEqBand(
        id: id,
        enabled: enabled,
        type: type,
        frequencyHz: freq,
        gainDb: gain,
        q: q,
      ),
    );
  }
  return bands;
}

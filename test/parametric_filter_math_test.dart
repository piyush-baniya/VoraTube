import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/audio/parametric_eq.dart';

const _rate = 48000;

ParametricEqBand _band({
  ParametricFilterType type = ParametricFilterType.peaking,
  double f = 1000,
  double g = 0,
  double q = 1,
  bool enabled = true,
}) {
  return ParametricEqBand(
    id: 'b',
    enabled: enabled,
    type: type,
    frequencyHz: f,
    gainDb: g,
    q: q,
  );
}

double _response(ParametricEqBand band, double at) => parametricBandResponseDb(
  parametricBandCoeffs(band, sampleRate: _rate),
  at,
  sampleRate: _rate,
);

void main() {
  group('clampedFrequency', () {
    test('never drops below 20 Hz', () {
      expect(clampedFrequency(5), 20);
    });

    test('honors 0.45 * sampleRate as the ceiling', () {
      expect(clampedFrequency(100000, sampleRate: 48000), 21600);
    });

    test('leaves in-range values untouched', () {
      expect(clampedFrequency(1000, sampleRate: 48000), 1000);
    });

    test('falls back to a 48 kHz assumption when the rate is unknown', () {
      expect(clampedFrequency(100000), 21600);
    });
  });

  group('parametricBandCoeffs', () {
    test('invalid sample rates yield an identity biquad', () {
      expect(parametricBandCoeffs(_band(g: 6), sampleRate: 0), [1, 0, 0, 0, 0]);
    });

    test('a peaking band at its center hits the requested gain', () {
      expect(_response(_band(g: 6, f: 1000, q: 1), 1000), closeTo(6, 0.1));
      expect(_response(_band(g: -6, f: 1000, q: 1), 1000), closeTo(-6, 0.1));
    });

    test('a peaking band leaves the extremes untouched', () {
      final band = _band(g: 8, f: 1000, q: 1.4);
      expect(_response(band, 20), closeTo(0, 0.1));
      expect(_response(band, 20000), closeTo(0, 0.1));
    });

    test('a low shelf lifts the lows and passes the highs', () {
      final band = _band(type: ParametricFilterType.lowShelf, g: 6, f: 200);
      expect(_response(band, 20), closeTo(6, 0.2));
      expect(_response(band, 20000), closeTo(0, 0.1));
    });

    test('a high shelf lifts the highs and passes the lows', () {
      final band = _band(type: ParametricFilterType.highShelf, g: 6, f: 4000);
      expect(_response(band, 20000), closeTo(6, 0.2));
      expect(_response(band, 20), closeTo(0, 0.1));
    });

    test('a low-pass rolls off above its cutoff', () {
      final band = _band(type: ParametricFilterType.lowPass, f: 1000, q: 0.707);
      expect(_response(band, 100), closeTo(0, 0.2));
      expect(_response(band, 10000), lessThan(-20));
    });

    test('a high-pass rolls off below its cutoff', () {
      final band = _band(
        type: ParametricFilterType.highPass,
        f: 1000,
        q: 0.707,
      );
      expect(_response(band, 10000), closeTo(0, 0.2));
      expect(_response(band, 100), lessThan(-20));
    });

    test('each call returns a stable 5-tap coefficient tuple', () {
      final coeffs = parametricBandCoeffs(_band(g: 3), sampleRate: _rate);
      expect(coeffs, hasLength(5));
      expect(coeffs.every((c) => c.isFinite), isTrue);
    });
  });

  group('parametricResponseCurve', () {
    test('returns the requested number of points', () {
      expect(
        parametricResponseCurve(const [], sampleRate: _rate, pointCount: 32),
        hasLength(32),
      );
    });

    test('disabled bands are a flat 0 dB line', () {
      final curve = parametricResponseCurve(
        [_band(g: 10, enabled: false)],
        sampleRate: _rate,
        pointCount: 64,
      );
      expect(curve.every((db) => db == 0), isTrue);
    });

    test('an empty band stack is a flat 0 dB line', () {
      final curve = parametricResponseCurve(const [], sampleRate: _rate);
      expect(curve.every((db) => db == 0), isTrue);
    });

    test('an active peaking band introduces a positive bump', () {
      final curve = parametricResponseCurve(
        [_band(g: 6, f: 1000, q: 1)],
        sampleRate: _rate,
        pointCount: 512,
      );
      expect(curve.reduce((a, b) => a > b ? a : b), greaterThan(5));
    });

    test('two identical bands stack their gain', () {
      final one = parametricBandResponseDb(
        parametricBandCoeffs(_band(g: 6), sampleRate: _rate),
        1000,
        sampleRate: _rate,
      );
      final two = parametricBandResponseDb(
        parametricBandCoeffs(_band(g: 6), sampleRate: _rate),
        1000,
        sampleRate: _rate,
      );
      expect(one + two, closeTo(12, 0.3));
    });
  });

  group('parametricNativeBands', () {
    test('preserves order and enabled flags', () {
      final bands = [_band(f: 100, g: 2), _band(f: 200, g: -2, enabled: false)];
      final native = parametricNativeBands(bands, sampleRate: _rate);
      expect(native, hasLength(2));
      expect(native[0]['enabled'], true);
      expect(native[1]['enabled'], false);
      expect(native[0]['coeffs'], hasLength(5));
      expect(native[1]['coeffs'], hasLength(5));
    });
  });

  group('ParametricEqBand', () {
    test('clampToDspBounds clamps frequency, Q and gain', () {
      final band = ParametricEqBand(
        id: 'b',
        frequencyHz: 99999,
        gainDb: 40,
        q: 100,
      );
      band.clampToDspBounds(sampleRate: 48000);
      expect(band.frequencyHz, 21600);
      expect(band.gainDb, parametricMaxGainDb);
      expect(band.q, parametricMaxQ);
    });

    test('copyWith overrides only the given fields', () {
      final band = _band(f: 500, g: 3, q: 2);
      final copy = band.copyWith(gainDb: -1);
      expect(copy.frequencyHz, 500);
      expect(copy.gainDb, -1);
      expect(copy.q, 2);
    });

    test('JSON round-trips the filter definition', () {
      final band = _band(
        type: ParametricFilterType.highShelf,
        f: 8000,
        g: -4.5,
        q: 0.7,
      );
      final json = band.toJson();
      expect(json['type'], 'highShelf');
      expect(json['f'], 8000);
      expect(json['g'], -4.5);
      expect(json['q'], 0.7);
    });
  });
}

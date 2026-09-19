import 'dart:async';

import 'package:flutter/services.dart';

/// Live spectrum frames streamed from the native post-EQ FFT analyzer.
///
/// A thin singleton wrapper around the `voratube/spectrum` EventChannel:
/// it owns the single platform subscription and fans frames out to any
/// interested widgets as a broadcast stream. The native analyzer runs only
/// while at least one Dart listener exists — unsubscribing (leaving the
/// Equalizer screen, disabling the toggle) stops the FFT worker.
class SpectrumService {
  SpectrumService._();

  static final SpectrumService instance = SpectrumService._();

  static const int bandCount = 48;

  static const EventChannel _channel = EventChannel('voratube/spectrum');

  final StreamController<List<double>> _controller =
      StreamController<List<double>>.broadcast();

  StreamSubscription<Object?>? _platformSubscription;
  var _listeners = 0;
  var _sampleRateHz = 48000;

  /// Newest spectrum frame: 48 normalized values, 0.0 (silence) → 1.0 (loud).
  Stream<List<double>> get frames => _controller.stream;

  /// Sample rate of the analyzed audio as reported by the native analyzer; the
  /// band grid it produced is 20 Hz → [sampleRateHz] / 2.
  int get sampleRateHz => _sampleRateHz;

  bool get isActive => _listeners > 0;

  /// Subscribes to spectrum frames; returns a subscription that must be
  /// cancelled to release the native analyzer.
  StreamSubscription<List<double>> subscribe(
    void Function(List<double> values) onData,
  ) {
    _ensurePlatformSubscription();
    _listeners++;
    final inner = _controller.stream.listen(onData);
    return _ManagedSubscription(this, inner);
  }

  void _ensurePlatformSubscription() {
    if (_platformSubscription != null) return;
    _platformSubscription = _channel.receiveBroadcastStream().listen(
      (data) {
        final values = _parseFrame(data);
        if (values == null) return;
        final rate = _parseSampleRate(data);
        if (rate != null) _sampleRateHz = rate;
        _controller.add(values);
      },
      onError: (Object _) {
        // Native analyzer failed: spectrum simply becomes unavailable,
        // playback and EQ are untouched.
      },
      cancelOnError: false,
    );
  }

  /// Parses one native frame; never throws, returns null for malformed data.
  static List<double>? _parseFrame(Object? data) {
    if (data is! Map) return null;
    final raw = data['values'];
    if (raw is! List || raw.length != bandCount) return null;
    final values = List<double>.filled(bandCount, 0.0);
    for (var i = 0; i < bandCount; i++) {
      final v = raw[i];
      if (v is! num) return null;
      final d = v.toDouble();
      if (d.isNaN || d.isInfinite) return null;
      values[i] = d.clamp(0.0, 1.0);
    }
    return values;
  }

  /// Parses the playback sample rate reported alongside a frame; null when the
  /// native side did not (or could not) report a usable rate.
  static int? _parseSampleRate(Object? data) {
    if (data is! Map) return null;
    final raw = data['sampleRate'];
    if (raw is! num) return null;
    final rate = raw.toInt();
    return rate >= 8000 ? rate : null;
  }

  void _release(StreamSubscription<List<double>> inner) {
    inner.cancel();
    if (--_listeners > 0) return;
    _platformSubscription?.cancel();
    _platformSubscription = null;
    _controller.add(List<double>.filled(bandCount, 0.0));
  }
}

class _ManagedSubscription implements StreamSubscription<List<double>> {
  _ManagedSubscription(this._owner, this._inner);

  final SpectrumService _owner;
  final StreamSubscription<List<double>> _inner;
  bool _cancelled = false;

  @override
  Future<void> cancel() {
    if (_cancelled) return Future<void>.value();
    _cancelled = true;
    return Future<void>.sync(() => _owner._release(_inner));
  }

  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture<E>(futureValue);

  @override
  bool get isPaused => _inner.isPaused;

  @override
  void onData(void Function(List<double> data)? handleData) =>
      _inner.onData(handleData);

  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);

  @override
  void onError(Function? handleError) => _inner.onError(handleError);

  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);

  @override
  void resume() => _inner.resume();
}

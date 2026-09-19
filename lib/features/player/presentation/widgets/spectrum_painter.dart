import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/audio/spectrum_service.dart';

/// Native log-band edge frequencies (20 Hz → Nyquist) matching the analyzer's
/// 48-band grid, so spectrum bars align exactly with any log-frequency axis.
List<double> spectrumEdgeFrequencies({double nyquist = 24000}) {
  final minHz = 20.0;
  final maxHz = nyquist > 40 ? nyquist : 24000.0;
  return [
    for (var b = 0; b <= SpectrumService.bandCount; b++)
      minHz * math.pow(maxHz / minHz, b / SpectrumService.bandCount).toDouble(),
  ];
}

/// Paints the 48-band spectrum as smooth filled bars behind an equalizer
/// graph. [edgeFrequencies] comes from [spectrumEdgeFrequencies] (matching the
/// native analyzer grid); [frequencyToX] maps a frequency (Hz) onto the host
/// graph's x coordinate, so spectral energy lines up exactly with the EQ
/// response curve it belongs to.
void paintSpectrumBands(
  Canvas canvas,
  Size size, {
  required List<double>? values,
  required List<double> edgeFrequencies,
  required double Function(double frequencyHz) frequencyToX,
  required double plotBottom,
  required double maxBarHeight,
  required Color color,
}) {
  if (values == null || values.isEmpty) return;

  double xForEdge(int band) => frequencyToX(edgeFrequencies[band]);

  final fillPaint = Paint()
    ..style = PaintingStyle.fill
    ..shader = ui.Gradient.linear(
      Offset(0, plotBottom - maxBarHeight),
      Offset(0, plotBottom),
      [color.withValues(alpha: 0.34), color.withValues(alpha: 0.10)],
    );

  final path = Path()..moveTo(xForEdge(0), plotBottom);
  for (var b = 0; b < values.length; b++) {
    final x0 = xForEdge(b);
    final x1 = xForEdge(b + 1);
    if (x1 <= x0) continue;
    final h = values[b].clamp(0.0, 1.0) * maxBarHeight;
    final y = plotBottom - h;
    path.lineTo(x0, y);
    path.lineTo(x1, y);
  }
  path.lineTo(xForEdge(values.length), plotBottom);
  path.close();
  canvas.drawPath(path, fillPaint);

  // Subtle bright top edge so the spectrum reads as a surface, not a wash.
  final topPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4
    ..color = color.withValues(alpha: 0.55)
    ..strokeCap = StrokeCap.round;
  for (var b = 0; b < values.length; b++) {
    final x0 = xForEdge(b);
    final x1 = xForEdge(b + 1);
    if (x1 - x0 < 0.5) continue;
    final y = plotBottom - values[b].clamp(0.0, 1.0) * maxBarHeight;
    canvas.drawLine(Offset(x0, y), Offset(x1, y), topPaint);
  }
}

/// Binds one widget (a graph) to the live spectrum stream. Subscribing starts
/// the native analyzer, cancelling stops it; frames only repaint the widget
/// that owns this binder.
class SpectrumStreamBinder {
  StreamSubscription<List<double>>? _subscription;
  List<double>? values;

  /// Band edge frequencies of the *actual* playback sample rate, so the drawn
  /// bands line up with the graph's log-frequency axis.
  List<double> edges = spectrumEdgeFrequencies();
  int _edgesNyquist = 24000;

  bool _active = false;

  bool get isActive => _active;

  void sync(bool active, VoidCallback onFrame) {
    if (active == _active) return;
    _active = active;
    if (active) {
      values = null;
      _subscription = SpectrumService.instance.subscribe((frame) {
        _refreshEdges();
        values = frame;
        onFrame();
      });
    } else {
      _subscription?.cancel();
      _subscription = null;
      values = null;
    }
  }

  void _refreshEdges() {
    final nyquist = SpectrumService.instance.sampleRateHz ~/ 2;
    if (nyquist == _edgesNyquist || nyquist < 80) return;
    _edgesNyquist = nyquist;
    edges = spectrumEdgeFrequencies(nyquist: nyquist.toDouble());
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _active = false;
    values = null;
  }
}

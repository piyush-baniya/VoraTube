import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/audio/parametric_eq.dart';

/// Display sample rate used for coefficient/curve maths when no popped decoded
/// rate is known yet. The engine recomputes for the real rate automatically, so
/// this only affects where the curve is drawn.
const int kParametricDisplaySampleRate = 48000;

/// Curved display range for the graph (dB).
const double kParametricCurveDbSpan = 15;

/// Formats a frequency as `1.5 kHz` / `800 Hz`.
String formatFrequency(double hz) {
  if (hz >= 1000) {
    final kHz = hz / 1000;
    final text = kHz >= 100
        ? kHz.toStringAsFixed(0)
        : kHz.toStringAsFixed(kHz == kHz.roundToDouble() ? 0 : 1);
    return '$text kHz';
  }
  return '${hz.round()} Hz';
}

/// Interactive parametric response graph.
///
/// Log-frequency x axis (20 Hz → 20 kHz, or the DSP ceiling), dB y axis
/// (−[kParametricCurveDbSpan]..+[kParametricCurveDbSpan]). Each enabled band is
/// a draggable node: horizontal drags retune the frequency; vertical drags
/// change gain for peaking/shelf bands (low-pass/high-pass never expose gain).
/// The rendered curve is the combined biquad response computed from the very
/// same [parametricBandCoeffs] used by the native audio processor, so what you
/// see is exactly what you hear.
///
/// Callers keep the curve outside any scrollable so node drags never fight the
/// scroll gesture.
class ParametricEqCurve extends StatefulWidget {
  const ParametricEqCurve({
    super.key,
    required this.bands,
    required this.enabled,
    required this.height,
    this.sampleRate = kParametricDisplaySampleRate,
    this.selectedBandId,
    this.onSelectBand,
    this.onBandChanged,
    this.onDragCommit,
  });

  final List<ParametricEqBand> bands;
  final bool enabled;
  final double height;
  final int sampleRate;
  final String? selectedBandId;
  final ValueChanged<String?>? onSelectBand;
  final ValueChanged<ParametricEqBand>? onBandChanged;
  final VoidCallback? onDragCommit;

  @override
  State<ParametricEqCurve> createState() => _ParametricEqCurveState();
}

class _ParametricEqCurveState extends State<ParametricEqCurve> {
  double _logCeiling = math.log(kParametricDisplaySampleRate * 0.45);

  String? _dragId;
  double _startLogF = 0;
  double _startGain = 0;
  double _startDx = 0;
  double _startDy = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ceiling = clampedFrequency(
          20000,
          sampleRate: widget.sampleRate.toDouble(),
        );
        _logCeiling = math.log(ceiling);
        return SizedBox(
          height: widget.height,
          width: constraints.maxWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) =>
                _beginDrag(details.localPosition, constraints.maxWidth),
            onPanUpdate: (details) =>
                _updateDrag(details.localPosition, constraints.maxWidth),
            onPanEnd: (_) => _endDrag(),
            onPanCancel: _endDrag,
            child: CustomPaint(
              painter: _ParametricCurvePainter(
                bands: widget.bands,
                enabled: widget.enabled,
                logCeiling: _logCeiling,
                width: constraints.maxWidth,
                height: widget.height,
                selectedBandId: widget.selectedBandId ?? _dragId,
                colorScheme: Theme.of(context).colorScheme,
              ),
            ),
          ),
        );
      },
    );
  }

  double _logScale(double frequencyHz) {
    final minLog = math.log(parametricMinFrequencyHz);
    return ((math.log(frequencyHz) - minLog) / (_logCeiling - minLog)).clamp(
      0.0,
      1.0,
    );
  }

  void _beginDrag(Offset position, double width) {
    const hitRadius = 32.0;
    String? nearest;
    double nearestDist = double.infinity;
    for (final band in widget.bands) {
      if (!band.enabled) continue;
      final dx = (_logScale(band.frequencyHz) * width - position.dx).abs();
      if (dx > hitRadius) continue;
      if (band.type == ParametricFilterType.peaking ||
          band.type == ParametricFilterType.lowShelf ||
          band.type == ParametricFilterType.highShelf) {
        final dyPx =
            widget.height / 2 -
            (band.gainDb / kParametricCurveDbSpan) * (widget.height / 2);
        if ((dyPx - position.dy).abs() > hitRadius) continue;
      }
      if (dx < nearestDist) {
        nearestDist = dx;
        nearest = band.id;
      }
    }
    if (nearest == null) {
      widget.onSelectBand?.call(null);
      return;
    }
    final band = widget.bands.firstWhere((b) => b.id == nearest);
    setState(() {
      _dragId = nearest;
      _startLogF = math.log(band.frequencyHz);
      _startGain = band.gainDb;
      _startDx = position.dx;
      _startDy = position.dy;
    });
    widget.onSelectBand?.call(nearest);
  }

  void _updateDrag(Offset position, double width) {
    final id = _dragId;
    if (id == null) return;
    final band = widget.bands.firstWhere((b) => b.id == id);
    final minLog = math.log(parametricMinFrequencyHz);
    final logF =
        _startLogF + (position.dx - _startDx) / width * (_logCeiling - minLog);
    final freq = math.exp(logF);

    var gain = band.gainDb;
    final gainEditable =
        band.type != ParametricFilterType.lowPass &&
        band.type != ParametricFilterType.highPass;
    if (gainEditable) {
      final dyDb =
          -(position.dy - _startDy) /
          (widget.height / 2) *
          kParametricCurveDbSpan;
      gain = (_startGain + dyDb)
          .clamp(-parametricMaxGainDb, parametricMaxGainDb)
          .toDouble();
    }
    final updated = band.copyWith(
      frequencyHz: clampedFrequency(
        freq,
        sampleRate: widget.sampleRate.toDouble(),
      ),
      gainDb: gain,
    );
    widget.onBandChanged?.call(updated);
  }

  void _endDrag() {
    if (_dragId == null) return;
    setState(() => _dragId = null);
    widget.onDragCommit?.call();
  }
}

class _ParametricCurvePainter extends CustomPainter {
  _ParametricCurvePainter({
    required this.bands,
    required this.enabled,
    required this.logCeiling,
    required this.width,
    required this.height,
    required this.selectedBandId,
    required this.colorScheme,
  });

  final List<ParametricEqBand> bands;
  final bool enabled;
  final double logCeiling;
  final double width;
  final double height;
  final String? selectedBandId;
  final ColorScheme colorScheme;

  static const List<double> _majorFreqs = [
    20,
    50,
    100,
    200,
    500,
    1000,
    2000,
    5000,
    10000,
    20000,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final centre = height / 2;
    final dbPerPx = centre / kParametricCurveDbSpan;

    final gridPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.9)
      ..strokeWidth = 1.2;

    // Horizontal dB grid.
    for (final db in [-12.0, -6.0, 6.0, 12.0]) {
      final y = centre - db * dbPerPx;
      canvas.drawLine(Offset(0, y), Offset(width, y), gridPaint);
    }
    // 0 dB axis.
    canvas.drawLine(Offset(0, centre), Offset(width, centre), axisPaint);

    // Vertical frequency grid + labels.
    final labelStyle = TextStyle(
      fontSize: 9,
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
    );
    for (final freq in _majorFreqs) {
      final x = _xFor(freq) * width;
      canvas.drawLine(Offset(x, 0), Offset(x, height), gridPaint);
      final painter = TextPainter(
        text: TextSpan(
          text: formatFrequency(freq.toDouble()),
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          (x - painter.width / 2).clamp(1, width - painter.width - 2),
          height - painter.height - 4,
        ),
      );
    }
    for (final freq in <double>[
      31.5,
      63,
      125,
      250,
      400,
      800,
      1600,
      3150,
      6400,
      12500,
    ]) {
      final x = _xFor(freq) * width;
      canvas.drawLine(Offset(x, 0), Offset(x, height), gridPaint);
    }

    // Combined response curve, reusing the DSP response functions.
    final curve = parametricResponseCurve(
      bands,
      sampleRate: 48000,
      pointCount: 128,
    );
    final clipped = [
      for (final db in curve)
        db.clamp(-kParametricCurveDbSpan, kParametricCurveDbSpan),
    ];
    final linePaint = Paint()
      ..color = (enabled ? colorScheme.primary : colorScheme.onSurfaceVariant)
          .withValues(alpha: enabled ? 1 : 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fillPaint = Paint()
      ..color = (enabled ? colorScheme.primary : colorScheme.onSurfaceVariant)
          .withValues(alpha: enabled ? 0.16 : 0.08)
      ..style = PaintingStyle.fill;

    final path = Path();
    final minLog = math.log(parametricMinFrequencyHz);
    for (var i = 0; i < clipped.length; i++) {
      final t = i / (clipped.length - 1);
      final freq = math.exp(minLog + t * (logCeiling - minLog));
      // Recompute over the actual display ceiling so the path hugs the grid.
      final x = _xFor(freq) * width;
      final y = centre - clipped[i] * dbPerPx;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fillPath = Path.from(path)
      ..lineTo(width, height)
      ..lineTo(0, height)
      ..close();
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    // Nodes.
    for (final band in bands) {
      if (!band.enabled && !enabled) continue;
      final x =
          _xFor(
            band.frequencyHz
                .clamp(parametricMinFrequencyHz, math.exp(logCeiling))
                .toDouble(),
          ) *
          width;
      final gainShown =
          band.type == ParametricFilterType.peaking ||
              band.type == ParametricFilterType.lowShelf ||
              band.type == ParametricFilterType.highShelf
          ? band.gainDb
          : 0.0;
      final y =
          centre -
          gainShown.clamp(-kParametricCurveDbSpan, kParametricCurveDbSpan) *
              dbPerPx;
      final selected = band.id == selectedBandId;
      final radius = selected ? 6.5 : 4.5;
      canvas.drawCircle(
        Offset(x, y),
        radius + 4,
        Paint()
          ..color = colorScheme.surfaceContainerLowest.withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..color = band.enabled
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant
          ..style = band.enabled ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      if (selected) {
        canvas.drawCircle(
          Offset(x, y),
          radius + 7,
          Paint()
            ..color = colorScheme.primary.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    // Mode / gesture hint.
    final hint = enabled
        ? 'Drag nodes: horizontal = frequency, vertical = gain'
        : 'Bypassed — curve kept, not applied.';
    final hintPainter = TextPainter(
      text: TextSpan(
        text: hint,
        style: TextStyle(
          fontSize: 11,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    hintPainter.paint(canvas, Offset(14, height - hintPainter.height - 14));
  }

  double _xFor(double frequencyHz) {
    final minLog = math.log(parametricMinFrequencyHz);
    return ((math.log(frequencyHz) - minLog) / (logCeiling - minLog)).clamp(
      0.0,
      1.0,
    );
  }

  @override
  bool shouldRepaint(_ParametricCurvePainter oldDelegate) =>
      oldDelegate.bands != bands ||
      oldDelegate.enabled != enabled ||
      oldDelegate.width != width ||
      oldDelegate.height != height ||
      oldDelegate.selectedBandId != selectedBandId ||
      oldDelegate.colorScheme != colorScheme;
}

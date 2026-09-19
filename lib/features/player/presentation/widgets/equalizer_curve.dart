import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/audio/audio_effects.dart';
import 'spectrum_painter.dart';

/// The interactive 10-band equalizer curve.
///
/// A single [CustomPaint] draws the grid, the filled curve and the ten draggable
/// nodes; the widget's own gesture recogniser maps a vertical drag onto the
/// nearest node's gain. Horizontal movement is deliberately ignored (no band
/// frequency/Q editing yet), so users cannot accidentally move a band sideways.
///
/// Preset changes animate from the previous curve to the new one over ~280 ms.
/// Static geometry (the grid, labels and node layout) is computed once per paint
/// and the whole thing sits in a [RepaintBoundary], so unrelated screen content
/// never repaints with the curve.
class EqualizerCurve extends StatefulWidget {
  const EqualizerCurve({
    super.key,
    required this.levels,
    required this.enabled,
    this.onChanged,
    this.onChangedEnd,
    this.interactive = true,
    this.height = 220,
    this.showLabels = true,
    this.showSpectrum = false,
  });

  final List<double> levels;
  final bool enabled;

  /// Live callback while dragging `(bandIndex, newGainDb)`.
  final void Function(int index, double value)? onChanged;

  /// Fired once when a drag finishes.
  final VoidCallback? onChangedEnd;

  final bool interactive;
  final double height;
  final bool showLabels;

  /// Renders the real-time spectrum behind the curve and runs the native
  /// analyzer while this curve is on screen.
  final bool showSpectrum;

  @override
  State<EqualizerCurve> createState() => _EqualizerCurveState();
}

class _EqualizerCurveState extends State<EqualizerCurve>
    with SingleTickerProviderStateMixin {
  static const double _leftPad = 30;
  static const double _rightPad = 12;
  static const double _topPad = 14;
  static const double _bottomPad = 26;

  late final AnimationController _animation;
  late final Animation<double> _curve;

  late List<double> _from;
  late List<double> _to;
  int? _dragIndex;
  final SpectrumStreamBinder _spectrum = SpectrumStreamBinder();

  @override
  void initState() {
    super.initState();
    _from = normalizeEqLevels(widget.levels);
    _to = List<double>.of(_from);
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..value = 1.0;
    _curve = CurvedAnimation(parent: _animation, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _spectrum.dispose();
    _animation.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant EqualizerCurve oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragIndex != null) return;
    final next = normalizeEqLevels(widget.levels);
    if (_listEquals(next, _to)) return;
    _from = _displayed();
    _to = next;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _animation.value = 1.0;
      _from = next;
    } else {
      _animation.forward(from: 0.0);
    }
  }

  List<double> _displayed() {
    if (_dragIndex != null) return normalizeEqLevels(widget.levels);
    if (_animation.value >= 1.0) return _to;
    final t = _curve.value;
    return [
      for (var i = 0; i < eqVirtualBandCount; i++)
        _from[i] + (_to[i] - _from[i]) * t,
    ];
  }

  double _valueForDy(double dy, double plotTop, double plotHeight) {
    final t = ((dy - plotTop) / plotHeight).clamp(0.0, 1.0);
    return kEqLevelMax - t * (kEqLevelMax - kEqLevelMin);
  }

  double _plotTop() => _topPad;
  double _plotHeight(double height) =>
      (height - _topPad - (widget.showLabels ? _bottomPad : 0)).clamp(
        1.0,
        double.infinity,
      );

  int? _indexForDx(double dx, double width) {
    final plotLeft = _leftPad;
    final plotWidth = (width - _leftPad - _rightPad).clamp(
      1.0,
      double.infinity,
    );
    final step = plotWidth / (eqVirtualBandCount - 1);
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < eqVirtualBandCount; i++) {
      final distance = (dx - (plotLeft + step * i)).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }

  void _handleStart(Offset local, Size size) {
    if (!widget.interactive) return;
    final index = _indexForDx(local.dx, size.width);
    if (index == null) return;
    setState(() => _dragIndex = index);
    _handleUpdate(local, size);
  }

  void _handleUpdate(Offset local, Size size) {
    if (!widget.interactive || _dragIndex == null) return;
    final value = _valueForDy(local.dy, _plotTop(), _plotHeight(widget.height));
    final clamped = clampEqLevel(value);
    if (widget.levels[_dragIndex!] == clamped) return;
    widget.onChanged?.call(_dragIndex!, clamped);
  }

  void _handleEnd() {
    if (_dragIndex == null) return;
    setState(() => _dragIndex = null);
    widget.onChangedEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = widget.enabled
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    _spectrum.sync(widget.showSpectrum, () {
      if (mounted) setState(() {});
    });

    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, _) {
            final levels = _displayed();
            return LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, widget.height);
                return Semantics(
                  label: 'Equalizer curve',
                  value: _semanticsValue(levels),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) =>
                        _handleStart(details.localPosition, size),
                    onPanUpdate: (details) =>
                        _handleUpdate(details.localPosition, size),
                    onPanEnd: (_) => _handleEnd(),
                    onPanCancel: _handleEnd,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: size,
                        painter: _EqualizerCurvePainter(
                          levels: levels,
                          accent: accent,
                          enabled: widget.enabled,
                          showLabels: widget.showLabels,
                          activeIndex: _dragIndex,
                          labelColor: colorScheme.onSurfaceVariant,
                          gridColor: colorScheme.outlineVariant,
                          surfaceColor: colorScheme.surface,
                          leftPad: _leftPad,
                          rightPad: _rightPad,
                          topPad: _plotTop(),
                          bottomPad: widget.showLabels ? _bottomPad : 0,
                          spectrum: _spectrum.values,
                          spectrumEdges: _spectrum.edges,
                          spectrumColor: colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _semanticsValue(List<double> levels) {
    final peak = maxEqBoostDb(levels);
    final cut = levels.fold(0.0, (m, v) => v < m ? v : m);
    if (peak == 0 && cut == 0) return 'Flat curve';
    return 'Curve with ${peak.toStringAsFixed(1)} dB maximum boost';
  }
}

class _EqualizerCurvePainter extends CustomPainter {
  _EqualizerCurvePainter({
    required this.levels,
    required this.accent,
    required this.enabled,
    required this.showLabels,
    required this.activeIndex,
    required this.labelColor,
    required this.gridColor,
    required this.surfaceColor,
    required this.leftPad,
    required this.rightPad,
    required this.topPad,
    required this.bottomPad,
    this.spectrum,
    required this.spectrumEdges,
    required this.spectrumColor,
  });

  final List<double> levels;
  final Color accent;
  final bool enabled;
  final bool showLabels;
  final int? activeIndex;
  final Color labelColor;
  final Color gridColor;
  final Color surfaceColor;
  final double leftPad;
  final double rightPad;
  final double topPad;
  final double bottomPad;
  final List<double>? spectrum;
  final List<double> spectrumEdges;
  final Color spectrumColor;

  @override
  void paint(Canvas canvas, Size size) {
    final plotLeft = leftPad;
    final plotWidth = (size.width - leftPad - rightPad).clamp(
      1.0,
      double.infinity,
    );
    final plotHeight = (size.height - topPad - bottomPad).clamp(
      1.0,
      double.infinity,
    );
    final range = kEqLevelMax - kEqLevelMin;

    double yFor(double db) => topPad + (kEqLevelMax - db) / range * plotHeight;
    double xFor(int index) =>
        plotLeft + plotWidth / (eqVirtualBandCount - 1) * index;

    // Real spectrum first: it sits behind the grid and the curve.
    paintSpectrumBands(
      canvas,
      size,
      values: spectrum,
      edgeFrequencies: spectrumEdges,
      frequencyToX: (f) {
        // The graphic graph's x axis is its node grid: the 10 virtual band
        // centres (31 Hz → 16 kHz) sit at evenly spaced positions, and they are
        // exactly octave-spaced, so the axis is the log range between the first
        // and last node. Anchoring here makes spectrum energy line up with the
        // node labels (1 kHz energy appears under the "1k" node).
        final minLog = math.log(kEqVirtualBandFrequencies.first);
        final maxLog = math.log(kEqVirtualBandFrequencies.last);
        final t = ((math.log(f) - minLog) / (maxLog - minLog)).clamp(0.0, 1.0);
        return plotLeft + t * plotWidth;
      },
      plotBottom: topPad + plotHeight,
      maxBarHeight: plotHeight,
      color: spectrumColor,
    );

    _paintGrid(canvas, size, plotLeft, plotWidth, plotHeight, yFor);
    _paintCurve(canvas, xFor, yFor);
    _paintNodes(canvas, xFor, yFor);
    if (showLabels) _paintLabels(canvas, size, plotLeft, plotWidth, plotHeight);
  }

  void _paintGrid(
    Canvas canvas,
    Size size,
    double plotLeft,
    double plotWidth,
    double plotHeight,
    double Function(double) yFor,
  ) {
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    for (final db in const [kEqLevelMax, 6.0, 0.0, -6.0, kEqLevelMin]) {
      final y = yFor(db);
      final isZero = db == 0;
      gridPaint.color = isZero
          ? gridColor.withValues(alpha: 0.9)
          : gridColor.withValues(alpha: 0.35);
      canvas.drawLine(
        Offset(plotLeft, y),
        Offset(plotLeft + plotWidth, y),
        gridPaint,
      );
    }
    // dB labels on the left spine.
    for (final db in const [kEqLevelMax, 0.0, kEqLevelMin]) {
      _text(
        canvas,
        '${db > 0 ? '+' : ''}${db.toInt()}',
        Offset(0, yFor(db) - 7),
        size: 10,
      );
    }
  }

  void _paintCurve(
    Canvas canvas,
    double Function(int) xFor,
    double Function(double) yFor,
  ) {
    final zeroY = yFor(0);
    final path = Path()..moveTo(xFor(0), yFor(levels[0]));
    for (var i = 1; i < eqVirtualBandCount; i++) {
      path.lineTo(xFor(i), yFor(levels[i]));
    }

    final fill = Path.from(path)
      ..lineTo(xFor(eqVirtualBandCount - 1), zeroY)
      ..lineTo(xFor(0), zeroY)
      ..close();

    final fillPaint = Paint()
      ..shader =
          LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accent.withValues(alpha: enabled ? 0.35 : 0.12),
              accent.withValues(alpha: enabled ? 0.05 : 0.02),
            ],
          ).createShader(
            Rect.fromLTRB(
              xFor(0),
              yFor(kEqLevelMax),
              xFor(eqVirtualBandCount - 1),
              zeroY,
            ),
          );
    canvas.drawPath(fill, fillPaint);

    final linePaint = Paint()
      ..color = accent.withValues(alpha: enabled ? 1.0 : 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);
  }

  void _paintNodes(
    Canvas canvas,
    double Function(int) xFor,
    double Function(double) yFor,
  ) {
    for (var i = 0; i < eqVirtualBandCount; i++) {
      final center = Offset(xFor(i), yFor(levels[i]));
      final active = i == activeIndex;
      final radius = active ? 9.0 : 6.0;
      canvas.drawCircle(
        center,
        radius + 2,
        Paint()..color = surfaceColor.withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = enabled ? accent : accent.withValues(alpha: 0.5),
      );
      if (active) {
        canvas.drawCircle(
          center,
          radius + 4,
          Paint()
            ..color = accent.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  void _paintLabels(
    Canvas canvas,
    Size size,
    double plotLeft,
    double plotWidth,
    double plotHeight,
  ) {
    for (var i = 0; i < eqVirtualBandCount; i++) {
      final frequency = kEqVirtualBandFrequencies[i];
      final label = frequency >= 1000
          ? '${(frequency / 1000).toStringAsFixed(frequency % 1000 == 0 ? 0 : 1)}k'
          : '${frequency.toInt()}';
      final x = plotLeft + plotWidth / (eqVirtualBandCount - 1) * i;
      final painter = _textPainter(label, size: 9.5);
      painter.paint(
        canvas,
        Offset(x - painter.width / 2, size.height - painter.height - 2),
      );
    }
  }

  TextPainter _textPainter(String text, {required double size}) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: labelColor,
          fontSize: size,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  void _text(
    Canvas canvas,
    String text,
    Offset offset, {
    required double size,
  }) {
    _textPainter(text, size: size).paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _EqualizerCurvePainter oldDelegate) {
    return !_listEquals(oldDelegate.levels, levels) ||
        oldDelegate.accent != accent ||
        oldDelegate.enabled != enabled ||
        oldDelegate.activeIndex != activeIndex ||
        !identical(oldDelegate.spectrumEdges, spectrumEdges) ||
        !identical(oldDelegate.spectrum, spectrum);
  }
}

bool _listEquals(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

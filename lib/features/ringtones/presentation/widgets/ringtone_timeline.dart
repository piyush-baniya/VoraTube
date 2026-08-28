import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../domain/ringtone_selection.dart';

/// Lightweight, dependency-free timeline for trimming a track.
///
/// No waveform decoding is performed (that would require a heavy audio
/// dependency). Instead a decorative, deterministic pseudo-waveform is drawn
/// purely from a seed, while the *selection window* (the true source of truth)
/// is rendered as a strongly-visible highlighted region with draggable start
/// and end handles.
///
/// Dragging maps horizontal pixels to milliseconds and delegates clamping to
/// [RingtoneSelection], so the handles can never cross or exceed the track, and
/// the minimum duration is always preserved. Only this subtree repaints during
/// a drag — the surrounding screen is untouched.
class RingtoneTimeline extends StatefulWidget {
  const RingtoneTimeline({
    super.key,
    required this.selection,
    this.height = 76,
    required this.onStartChanged,
    required this.onEndChanged,
  });

  final RingtoneSelection selection;
  final double height;
  final ValueChanged<int> onStartChanged;
  final ValueChanged<int> onEndChanged;

  @override
  State<RingtoneTimeline> createState() => _RingtoneTimelineState();
}

enum _Handle { start, end, none }

class _RingtoneTimelineState extends State<RingtoneTimeline> {
  _Handle _dragging = _Handle.none;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalMs = widget.selection.total.inMilliseconds;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final usable = math.max(1.0, width - _HandleRegion.knobSize * 2);
          final startX =
              _HandleRegion.knobSize +
              (usable *
                  (widget.selection.start.inMilliseconds /
                      math.max(1, totalMs)));
          final endX =
              _HandleRegion.knobSize +
              (usable *
                  (widget.selection.end.inMilliseconds / math.max(1, totalMs)));

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (details) {
              final dx = details.localPosition.dx;
              final toStart = (dx - startX).abs();
              final toEnd = (dx - endX).abs();
              _dragging = toStart <= toEnd ? _Handle.start : _Handle.end;
            },
            onHorizontalDragUpdate: (details) {
              final dx = (details.localPosition.dx).clamp(0.0, width);
              final ratio = dx / math.max(1.0, width) * totalMs;
              final ms = ratio.round();
              if (_dragging == _Handle.start) {
                widget.onStartChanged(ms);
              } else if (_dragging == _Handle.end) {
                widget.onEndChanged(ms);
              }
            },
            onHorizontalDragEnd: (_) => _dragging = _Handle.none,
            onHorizontalDragCancel: () => _dragging = _Handle.none,
            child: CustomPaint(
              size: Size(width, widget.height),
              painter: _TimelinePainter(
                startX: startX,
                endX: endX,
                knobSize: _HandleRegion.knobSize,
                baseColor: theme.colorScheme.surfaceContainerHighest,
                accent: theme.colorScheme.primary,
                onAccent: theme.colorScheme.onPrimary,
                seed:
                    widget.selection.start.inSeconds +
                    widget.selection.total.inSeconds,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One draggable handle + the grab target it occupies on the timeline.
class _HandleRegion {
  static const double knobSize = 18;
  static const double knobWidth = 6;
}

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.startX,
    required this.endX,
    required this.knobSize,
    required this.baseColor,
    required this.accent,
    required this.onAccent,
    required this.seed,
  });

  final double startX;
  final double endX;
  final double knobSize;
  final Color baseColor;
  final Color accent;
  final Color onAccent;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final barTop = size.height * 0.18;
    final barBottom = size.height * 0.82;
    final barRect = Rect.fromLTRB(0, barTop, size.width, barBottom);

    // Track background.
    final bg = Paint()
      ..color = baseColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    final rrect = RRect.fromRectAndRadius(
      barRect.inflate(4),
      const Radius.circular(AppTokens.rMd),
    );
    canvas.drawRRect(rrect, bg);

    // Decorative pseudo-waveform: deterministic bars inside the track.
    final barPaint = Paint()..color = baseColor;
    const barCount = 42;
    final rng = math.Random(seed);
    final step = size.width / barCount;
    for (var i = 0; i < barCount; i++) {
      final f = 0.25 + rng.nextDouble() * 0.95;
      final h = (barBottom - barTop) * 0.9 * f;
      final cx = i * step + step / 2;
      final left = cx - step * 0.28;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            left.clamp(0, size.width),
            barBottom - h,
            (step * 0.56).clamp(1.0, 8.0),
            h,
          ),
          const Radius.circular(2),
        ),
        barPaint,
      );
    }

    // Selected region.
    final selRect = Rect.fromLTRB(startX, barTop, endX, barBottom);
    final selPaint = Paint()..color = accent.withValues(alpha: 0.50);
    canvas.drawRRect(
      RRect.fromRectAndRadius(selRect, const Radius.circular(4)),
      selPaint,
    );

    _drawHandle(canvas, startX);
    _drawHandle(canvas, endX);
  }

  void _drawHandle(Canvas canvas, double x) {
    final paint = Paint()..color = accent;
    final glow = Paint()..color = accent.withValues(alpha: 0.18);
    canvas.drawCircle(Offset(x, 0), knobSize, glow);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x - _HandleRegion.knobWidth / 2,
          0,
          _HandleRegion.knobWidth,
          knobSize,
        ),
        const Radius.circular(3),
      ),
      paint..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.startX != startX || old.endX != endX || old.accent != accent;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/player/player_controller.dart';
import '../../../../app/theme/app_tokens.dart';

/// Can be disabled in tests to prevent the infinite pulse animation.
bool waveTimelineEnabled = true;

/// Public function to disable the wave pulse animation for testing.
void disableWaveTimelineForTesting() {
  waveTimelineEnabled = false;
}

/// Purple, smooth flowing wave progress bar for the full-screen player.
///
/// A single sine-based wave path is drawn as a continuous curve — deliberately
/// NOT equalizer bars. The wave is split at the playback progress point: the
/// played region is stroked in vivid purple, the remainder in a faint purple
/// tint, so progress stays readable while the shape stays a smooth flowing
/// single line. While playing the phase advances so the wave gently flows;
/// when paused the phase freezes and the painter only repaints on progress
/// changes.
class PlayerProgress extends StatefulWidget {
  const PlayerProgress({
    super.key,
    required this.snapshot,
    required this.position,
    required this.onSeek,
  });

  final PlayerSnapshot snapshot;
  final Duration position;
  final Future<void> Function(Duration position) onSeek;

  @override
  State<PlayerProgress> createState() => _PlayerProgressState();
}

class _PlayerProgressState extends State<PlayerProgress>
    with SingleTickerProviderStateMixin {
  bool _dragging = false;
  double _dragValue = 0;

  late final AnimationController _pulse;

  Duration get _duration => Duration(milliseconds: widget.snapshot.durationMs);
  Duration get _displayPosition =>
      _dragging ? Duration(milliseconds: _dragValue.round()) : widget.position;

  double get _progress {
    final total = _duration.inMilliseconds;
    if (total <= 0) return 0;
    return (_displayPosition.inMilliseconds / total).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (_shouldPulse) {
      _pulse.repeat();
    }
  }

  bool get _shouldPulse => waveTimelineEnabled && widget.snapshot.isPlaying;

  @override
  void didUpdateWidget(covariant PlayerProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldPulse = _shouldPulse;
    if (shouldPulse && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!shouldPulse && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _startDrag(double fraction) {
    setState(() {
      _dragging = true;
      _dragValue = fraction * _duration.inMilliseconds;
    });
  }

  void _updateDrag(double fraction) {
    setState(() {
      _dragValue = fraction * _duration.inMilliseconds;
    });
  }

  Future<void> _endDrag() async {
    if (!_dragging) {
      return;
    }
    final seekTo = Duration(milliseconds: _dragValue.round());
    setState(() {
      _dragging = false;
    });
    await widget.onSeek(seekTo);
  }

  Future<void> _tapAt(double fraction) async {
    final seekTo = Duration(
      milliseconds: (fraction * _duration.inMilliseconds).round(),
    );
    await widget.onSeek(seekTo);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalMs = _duration.inMilliseconds;
    // BUG #3: the wave is a subtle ripple on top of a thin progress line, so
    // the painted band is now a few logical pixels tall instead of a large
    // oscillation. The outer box keeps a comfortable seek hit-target.
    final compactHeight = MediaQuery.sizeOf(context).height < 480;
    final waveHeight = compactHeight ? 20.0 : 26.0;
    final wavePaintHeight = compactHeight ? 10.0 : 12.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WaveTimeline(
          progress: totalMs > 0 ? _progress : 0,
          isPlaying: widget.snapshot.isPlaying,
          pulse: _pulse,
          activeColor: colorScheme.primary,
          inactiveColor: colorScheme.primary.withValues(alpha: 0.16),
          height: waveHeight,
          paintHeight: wavePaintHeight,
          onDragStart: _startDrag,
          onDrag: _updateDrag,
          onDragEnd: _endDrag,
          onTap: _tapAt,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.s6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_displayPosition),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                _formatDuration(_duration),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Interactive wave-style track with tap/drag seeking.
class _WaveTimeline extends StatelessWidget {
  const _WaveTimeline({
    required this.progress,
    required this.isPlaying,
    required this.pulse,
    required this.activeColor,
    required this.inactiveColor,
    required this.height,
    required this.paintHeight,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
    required this.onTap,
  });

  final double progress;
  final bool isPlaying;
  final Animation<double> pulse;
  final Color activeColor;
  final Color inactiveColor;
  final double height;
  final double paintHeight;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;
  final ValueChanged<double> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        double toFraction(double dx) => (dx / width).clamp(0.0, 1.0);

        return Semantics(
          slider: true,
          label: 'Seek',
          value: '${(progress * 100).round()} percent',
          child: GestureDetector(
            key: const Key('player_progress_wave'),
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => onTap(toFraction(details.localPosition.dx)),
            onHorizontalDragStart: (details) =>
                onDragStart(toFraction(details.localPosition.dx)),
            onHorizontalDragUpdate: (details) =>
                onDrag(toFraction(details.localPosition.dx)),
            onHorizontalDragEnd: (_) => onDragEnd(),
            onHorizontalDragCancel: onDragEnd,
            child: SizedBox(
              height: height,
              width: width,
              child: Center(
                child: AnimatedBuilder(
                  animation: pulse,
                  builder: (context, _) {
                    return CustomPaint(
                      size: Size(double.infinity, paintHeight),
                      painter: _WavePainter(
                        progress: progress,
                        isPlaying: isPlaying,
                        wave: pulse.value,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints the thin progress line with a subtle ripple on the played portion.
///
/// BUG #3 redesign (visual only — seeking/progress semantics unchanged):
/// - The UNPLAYED portion is a straight line: a brand-new song shows a plain
///   purple line, never an animated wave.
/// - The PLAYED portion develops a very low-amplitude, continuous sine ripple
///   whose size grows with the fraction of the song already played (so the
///   wave "belongs" to that song's accumulated playback and follows the
///   persisted position after a restart — no separate storage).
/// - Only the wave PHASE animates while playing; pausing freezes it and the
///   accumulated ripple stays exactly where it is (no reset, no motion).
/// - Amplitude no longer depends on [isPlaying], so pausing no longer jumps.
class _WavePainter extends CustomPainter {
  const _WavePainter({
    required this.progress,
    required this.isPlaying,
    required this.wave,
    required this.activeColor,
    required this.inactiveColor,
  });

  final double progress;
  final bool isPlaying;
  final double wave;
  final Color activeColor;
  final Color inactiveColor;

  Path _wavePath({
    required double width,
    required double midY,
    required double amplitude,
    required double frequency,
    required double phaseShift,
    required double envelopeFrequency,
    required double envelopePhase,
  }) {
    final path = Path();
    const step = 4.0;
    var first = true;
    for (double x = 0; x <= width + step; x += step) {
      final envelope =
          0.55 + 0.45 * math.sin(x * envelopeFrequency + envelopePhase);
      final y =
          midY +
          math.sin(x * frequency + wave * 2 * math.pi + phaseShift) *
              amplitude *
              envelope;
      if (first) {
        path.moveTo(0, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final playedWidth = size.width * progress.clamp(0.0, 1.0);

    // BUG #3: max ripple is a small fraction of the (already slim) paint band
    // — a gentle ±~1.5 logical px at full playback, not a large oscillation —
    // and it scales with the played fraction so an unstarted song paints a
    // perfectly straight line.
    final maxAmplitude = size.height * 0.25;
    final amplitude = maxAmplitude * progress.clamp(0.0, 1.0);

    // Played portion: the subtle flowing ripple (phase advances only while
    // playing via the pulse controller; paused it freezes in place).
    if (playedWidth > 0 && amplitude > 0) {
      final played = _wavePath(
        width: playedWidth,
        midY: midY,
        amplitude: amplitude,
        frequency: 2 * math.pi / 95,
        phaseShift: 0,
        envelopeFrequency: 2 * math.pi / 300,
        envelopePhase: 0,
      );
      final activePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = activeColor;
      canvas.save();
      canvas.clipRect(Offset.zero & Size(playedWidth, size.height));
      canvas.drawPath(played, activePaint);
      canvas.restore();
    }

    // Unplayed portion: a plain straight line. This keeps the widget a
    // recognizable progress bar and gives new songs a straight purple line.
    final inactivePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..color = inactiveColor;
    canvas.drawLine(
      Offset(playedWidth, midY),
      Offset(size.width, midY),
      inactivePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.wave != wave ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}

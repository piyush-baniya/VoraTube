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
/// Two overlapping sine-based wave paths (a primary stroke plus a softer echo)
/// are drawn as continuous curves — deliberately NOT equalizer bars. The wave
/// is split at the playback progress point: the played region is stroked in
/// vivid purple, the remainder in a faint purple tint, so progress stays
/// readable while the shape stays a smooth flowing wave. While playing the
/// phase advances so the wave gently flows; when paused the phase freezes and
/// the painter only repaints on progress changes.
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
    // Compact-height screens (landscape phones) get a slimmer wave so the
    // fixed control region never overflows.
    final compactHeight = MediaQuery.sizeOf(context).height < 480;
    final waveHeight = compactHeight ? 30.0 : 44.0;
    final wavePaintHeight = compactHeight ? 22.0 : 36.0;

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

/// Paints the smooth flowing wave.
///
/// Geometry: a height envelope (a slow sine over x) modulates the amplitude so
/// the silhouette varies like a real waveform, while two phase-shifted sine
/// curves provide the flowing motion. The played portion is clipped and
/// re-stroked in the active color so seeking stays pixel-accurate.
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
          midY + math.sin(x * frequency + wave * 2 * math.pi + phaseShift) *
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

  void _paintSplit(Canvas canvas, Path path, double strokeWidth, Size size) {
    final playedWidth = size.width * progress.clamp(0.0, 1.0);

    final activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = activeColor;
    final inactivePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = inactiveColor;

    if (playedWidth > 0) {
      canvas.save();
      canvas.clipRect(Offset.zero & Size(playedWidth, size.height));
      canvas.drawPath(path, activePaint);
      canvas.restore();
    }
    if (playedWidth < size.width) {
      canvas.save();
      canvas.clipRect(
        Offset(playedWidth, 0) & Size(size.width - playedWidth, size.height),
      );
      canvas.drawPath(path, inactivePaint);
      canvas.restore();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    // Flow amplitude: gently larger while playing, settled when paused.
    final amplitude = isPlaying ? size.height * 0.36 : size.height * 0.28;
    // The envelope drifts slowly with the phase so the silhouette itself
    // breathes; when paused everything freezes naturally.
    final envelopePhase = wave * 2 * math.pi * 0.35;

    // Softer echo wave beneath the primary stroke.
    final echo = _wavePath(
      width: size.width,
      midY: midY,
      amplitude: amplitude * 0.6,
      frequency: 2 * math.pi / 130,
      phaseShift: 1.7,
      envelopeFrequency: 2 * math.pi / 420,
      envelopePhase: envelopePhase + 2.1,
    );
    // Primary wave.
    final main = _wavePath(
      width: size.width,
      midY: midY,
      amplitude: amplitude,
      frequency: 2 * math.pi / 95,
      phaseShift: 0,
      envelopeFrequency: 2 * math.pi / 300,
      envelopePhase: envelopePhase,
    );

    _paintSplit(canvas, echo, 2.0, size);
    _paintSplit(canvas, main, 3.0, size);
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
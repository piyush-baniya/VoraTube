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

/// Seekable wave-style progress bar for the full-screen player.
///
/// The track is drawn as a row of vertical segments that fill one by one as
/// playback advances (like a sound wave / equalizer). While playing, a subtle
/// travelling pulse animates the bars; when paused or stopped the bars stay
/// static so the animation costs nothing.
///
/// Designed for performance:
/// - Only this widget rebuilds on position ticks.
/// - The pulse animation repaints just the small custom-painted bar area.
/// - Uses a local StatefulWidget for drag state and the pulse controller.
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WaveTimeline(
          progress: totalMs > 0 ? _progress : 0,
          isPlaying: widget.snapshot.isPlaying,
          pulse: _pulse,
          activeColor: colorScheme.onSurface,
          inactiveColor: colorScheme.onSurface.withValues(alpha: 0.12),
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
              height: 30,
              width: width,
              child: Center(
                child: AnimatedBuilder(
                  animation: pulse,
                  builder: (context, _) {
                    return CustomPaint(
                      size: const Size(double.infinity, 18),
                      painter: _WaveBarPainter(
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

class _WaveBarPainter extends CustomPainter {
  const _WaveBarPainter({
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

  static const int _barCount = 36;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = 2.5;
    final barWidth = (size.width - gap * (_barCount - 1)) / _barCount;
    if (barWidth <= 0) return;

    final baseHeight = 11.0;
    final pulseAmp = isPlaying ? 3.0 : 0.0;
    final phase = wave * 2 * math.pi;
    final centerY = size.height / 2;

    final playedIndex = progress * _barCount;
    final currentIndex = playedIndex.floor().clamp(0, _barCount - 1);

    for (var i = 0; i < _barCount; i++) {
      final x = i * (barWidth + gap);

      final double height;
      if (isPlaying) {
        final offset = math.sin(phase + i * 0.6);
        height = baseHeight + pulseAmp * offset;
      } else {
        height = baseHeight;
      }

      final bool fullyFilled = i < playedIndex.floor();
      final bool isCurrent = i == currentIndex && progress < 1.0;

      final Color color;
      if (fullyFilled) {
        color = activeColor;
      } else if (isCurrent) {
        color = activeColor.withValues(alpha: 0.5);
      } else {
        color = inactiveColor;
      }

      final rect = Rect.fromLTWH(
        x,
        centerY - height / 2,
        barWidth,
        height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2)),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveBarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.wave != wave ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}
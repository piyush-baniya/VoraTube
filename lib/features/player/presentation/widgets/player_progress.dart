import 'package:flutter/material.dart';

import '../../../../core/player/player_controller.dart';
import '../../../../app/theme/app_tokens.dart';

/// Seekable progress bar for the full-screen player.
///
/// Designed for performance:
/// - Only this widget rebuilds on position ticks.
/// - Uses a local StatefulWidget for drag state.
/// - Clean thin track with accent color.
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

class _PlayerProgressState extends State<PlayerProgress> {
  bool _dragging = false;
  double _dragValue = 0;

  Duration get _duration => Duration(milliseconds: widget.snapshot.durationMs);
  Duration get _displayPosition =>
      _dragging ? Duration(milliseconds: _dragValue.round()) : widget.position;

  double get _progress {
    final total = _duration.inMilliseconds;
    if (total <= 0) return 0;
    return (_displayPosition.inMilliseconds / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalMs = _duration.inMilliseconds;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2.5,
            activeTrackColor: colorScheme.onSurface,
            inactiveTrackColor: colorScheme.onSurface.withValues(alpha: 0.1),
            thumbColor: colorScheme.onSurface,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 5,
              elevation: 0,
            ),
            overlayColor: Colors.transparent,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            trackShape: const _RoundedTrackShape(),
          ),
          child: Slider(
            value: totalMs > 0 ? _progress : 0,
            onChangeStart: (value) {
              setState(() {
                _dragging = true;
                _dragValue = value * totalMs;
              });
            },
            onChanged: (value) {
              setState(() {
                _dragValue = value * totalMs;
              });
            },
            onChangeEnd: (value) async {
              final seekTo = Duration(milliseconds: (value * totalMs).round());
              setState(() {
                _dragging = false;
              });
              await widget.onSeek(seekTo);
            },
          ),
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

class _RoundedTrackShape extends RoundedRectSliderTrackShape {
  const _RoundedTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
  }

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 2.5;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    return Rect.fromLTWH(
      offset.dx + 6,
      trackTop,
      parentBox.size.width - 12,
      trackHeight,
    );
  }
}

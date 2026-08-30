import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/player/player_controller.dart';
import '../../../../shared/widgets/artwork_view.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../features/ringtones/data/audio_util_providers.dart';
import '../../../../features/ringtones/data/audio_util_service.dart';
import '../../../../features/ringtones/domain/ringtone_selection.dart';
import '../../../../features/ringtones/presentation/ringtone_cutter_controller.dart';
import '../../../../features/ringtones/presentation/ringtone_previewer.dart';
import '../../../../features/ringtones/presentation/widgets/ringtone_timeline.dart';
import '../../../player/presentation/providers/player_providers.dart';

/// A polished, reliable ringtone cutter.
///
/// The user picks a start/end window from a song, previews it, then exports a
/// real trimmed audio clip (via the native audio bridge) and optionally assigns
/// it through the Android system ringtone picker.
class RingtoneCutterScreen extends ConsumerStatefulWidget {
  const RingtoneCutterScreen({super.key, required this.song});

  final SongRef song;

  @override
  ConsumerState<RingtoneCutterScreen> createState() =>
      _RingtoneCutterScreenState();
}

class _RingtoneCutterScreenState extends ConsumerState<RingtoneCutterScreen> {
  late final RingtoneCutterController _controller;
  late final RingtonePreviewer _previewer;

  @override
  void initState() {
    super.initState();
    final service = ref.read(audioUtilServiceProvider);
    _controller = RingtoneCutterController(
      service: service,
      durationMs: widget.song.durationMs,
    )..attachTrack(sourceUri: widget.song.uri, title: widget.song.title);
    _controller.addListener(_onControllerChange);
    _previewer = RingtonePreviewer(ref.read(playerProvider));
  }

  @override
  void dispose() {
    _previewer.dispose();
    _controller
      ..removeListener(_onControllerChange)
      ..dispose();
    super.dispose();
  }

  void _onControllerChange() {
    _previewer.updateSelection(_controller.selection);
    if (mounted) setState(() {});
  }

  Future<void> _startPreview() async {
    if (_controller.isBusy) return;
    await _previewer.start(song: widget.song, selection: _controller.selection);
    if (mounted) setState(() {});
  }

  Future<void> _stopPreview() async {
    await _previewer.stop();
    if (mounted) setState(() {});
  }

  Future<void> _onSetAsRingtone() async {
    if (_controller.isBusy || !_controller.selection.isUsable) return;
    await _stopPreview();
    final outcome = await _controller.setAsRingtone();
    if (!mounted) return;
    switch (outcome) {
      case SetRingtoneOutcome.assigned:
        _snack('Ringtone set successfully.');
      case SetRingtoneOutcome.failed:
        _snack(_controller.lastError ?? 'Ringtone could not be set.');
    }
  }

  static String _fileNameOf(String path) {
    final uri = Uri.tryParse(path);
    final segs = uri?.pathSegments ?? const <String>[];
    return segs.isNotEmpty ? segs.last : path;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: _controller.hasTrack
          ? _buildBody(theme, colors)
          : _buildUnavailable(theme),
    );
  }

  Widget _buildUnavailable(ThemeData theme) {
    return Column(
      children: [
        _buildHeader(theme),
        const Expanded(
          child: Padding(
            padding: EdgeInsets.all(AppTokens.s5),
            child: EmptyState(
              icon: Icons.music_off_rounded,
              title: 'No playable audio',
              message:
                  'The duration of this track is unknown, so it cannot be '
                  'trimmed. Pick a song that has a known length.',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colors) {
    final selection = _controller.selection;
    return Column(
      children: [
        _buildHeader(theme),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.s5,
              AppTokens.s2,
              AppTokens.s5,
              AppTokens.s4,
            ),
            children: [
              _buildTrackCard(theme, colors),
              const SizedBox(height: AppTokens.s6),
              Text(
                'Trim your ringtone',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppTokens.s2),
              Text(
                'Drag the handles to pick the segment, then preview or save.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTokens.s4),
              _buildTimelineCard(theme),
              const SizedBox(height: AppTokens.s4),
              _buildPrecisionCard(theme, selection),
              const SizedBox(height: AppTokens.s2),
              Center(
                child: Text(
                  'Selected: ${RingtoneSelection.formatCeil(selection.duration)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.s6),
            ],
          ),
        ),
        _buildBottomBar(theme),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final colors = theme.colorScheme;
    return Material(
      color: colors.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.s3,
            AppTokens.s2,
            AppTokens.s4,
            AppTokens.s3,
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: AppTokens.s1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ringtone Cutter',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Create a ringtone from any song in your library',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrackCard(ThemeData theme, ColorScheme colors) {
    final song = widget.song;
    final total = _controller.selection.total;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s4),
        child: Row(
          children: [
            ArtworkView(
              path: song.artPath,
              size: AppTokens.artworkLg,
              radius: AppTokens.rMd,
            ),
            const SizedBox(width: AppTokens.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (song.artist != null)
                    Text(
                      song.artist!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: AppTokens.s2),
                  Text(
                    'Track length  '
                    '${RingtoneSelection.formatCeil(total)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineCard(ThemeData theme) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.s3,
          AppTokens.s4,
          AppTokens.s3,
          AppTokens.s4,
        ),
        child: Column(
          children: [
            RingtoneTimeline(
              selection: _controller.selection,
              onStartChanged: _controller.setStartMs,
              onEndChanged: _controller.setEndMs,
            ),
            const SizedBox(height: AppTokens.s2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _timeChip(
                  theme,
                  'Start',
                  RingtoneSelection.formatCeil(_controller.selection.start),
                ),
                _timeChip(
                  theme,
                  'End',
                  RingtoneSelection.formatCeil(_controller.selection.end),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeChip(ThemeData theme, String label, String value) {
    final colors = theme.colorScheme;
    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppTokens.s2),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s3,
            vertical: AppTokens.s1,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppTokens.rSm),
          ),
          child: Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrecisionCard(ThemeData theme, RingtoneSelection selection) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s4),
        child: Column(
          children: [
            Wrap(
              spacing: AppTokens.s3,
              runSpacing: AppTokens.s3,
              alignment: WrapAlignment.spaceAround,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _precisionRow(
                  theme,
                  label: 'Start',
                  value: RingtoneSelection.formatCeil(selection.start),
                  onMinus: selection.start > Duration.zero
                      ? () => _controller.setStartMs(
                          selection.start.inMilliseconds - 1000,
                        )
                      : null,
                  onPlus: () => _controller.setStartMs(
                    selection.start.inMilliseconds + 1000,
                  ),
                ),
                _precisionRow(
                  theme,
                  label: 'End',
                  value: RingtoneSelection.formatCeil(selection.end),
                  onMinus: () =>
                      _controller.setEndMs(selection.end.inMilliseconds - 1000),
                  onPlus: selection.end < selection.total
                      ? () => _controller.setEndMs(
                          selection.end.inMilliseconds + 1000,
                        )
                      : null,
                ),
              ],
            ),
            const SizedBox(height: AppTokens.s3),
            Wrap(
              spacing: AppTokens.s2,
              runSpacing: AppTokens.s2,
              alignment: WrapAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () => _controller.selectAll(),
                  icon: const Icon(Icons.select_all_rounded, size: 18),
                  label: const Text('Use full track'),
                ),
                TextButton.icon(
                  onPressed: () => _controller.shiftBy(-1000),
                  icon: const Icon(Icons.fast_rewind_rounded, size: 18),
                  label: const Text('Shift −1s'),
                ),
                TextButton.icon(
                  onPressed: () => _controller.shiftBy(1000),
                  icon: const Icon(Icons.fast_forward_rounded, size: 18),
                  label: const Text('Shift +1s'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _precisionRow(
    ThemeData theme, {
    required String label,
    required String value,
    required VoidCallback? onMinus,
    required VoidCallback? onPlus,
  }) {
    final canDecrement = onMinus != null;
    final canIncrement = onPlus != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '$label −1s',
          onPressed: canDecrement ? onMinus : null,
          icon: const Icon(Icons.remove_circle_outline_rounded),
          visualDensity: VisualDensity.compact,
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        IconButton(
          tooltip: '$label +1s',
          onPressed: canIncrement ? onPlus : null,
          icon: const Icon(Icons.add_circle_outline_rounded),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    final colors = theme.colorScheme;
    final selection = _controller.selection;
    final usable = selection.isUsable;
    final busy = _controller.isBusy;
    final previewing = _previewer.isPreviewing;

    return Material(
      color: colors.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.s4,
            AppTokens.s2,
            AppTokens.s4,
            AppTokens.s3,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const LinearProgressIndicator(minHeight: 2)
              else
                const SizedBox(height: 2),
              const SizedBox(height: AppTokens.s2),
              Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: previewing ? 'Stop preview' : 'Preview',
                    onPressed: busy
                        ? null
                        : previewing
                        ? _stopPreview
                        : _startPreview,
                    icon: Icon(
                      previewing
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  const SizedBox(width: AppTokens.s3),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy || !usable ? null : _onSetAsRingtone,
                      icon: const Icon(Icons.phone_android_rounded),
                      label: const Text('Set as ringtone'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

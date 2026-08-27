import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/player/player_controller.dart';
import '../../../library/data/library_repository.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../providers/player_providers.dart';

/// Lets a user pick a start/end window from a song to use as a ringtone, and
/// previews the trimmed segment through the real [PlayerController].
///
/// V1 scope: range trimming + preview only. Writing a transcoded audio file
/// requires frame-accurate audio processing (e.g. ffmpeg_kit), which is
/// intentionally out of scope -- the chosen range is persisted locally in the
/// KV table so it can be applied later without re-recording.
class RingtoneCutterScreen extends ConsumerStatefulWidget {
  const RingtoneCutterScreen({super.key, required this.song});

  final SongRef song;

  @override
  ConsumerState<RingtoneCutterScreen> createState() =>
      _RingtoneCutterScreenState();
}

class _RingtoneCutterScreenState extends ConsumerState<RingtoneCutterScreen> {
  Duration _start = Duration.zero;
  Duration _end = Duration.zero;

  // Playback state captured before preview so we can restore the queue.
  List<SongRef> _savedQueue = const [];
  int _savedIndex = -1;
  bool _wasPlaying = false;
  StreamSubscription<Duration>? _posSub;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    final ms = widget.song.durationMs;
    _end = ms > 0 ? Duration(milliseconds: ms) : Duration.zero;
  }

  @override
  void dispose() {
    _stopPreview();
    super.dispose();
  }

  bool get _canPreview => _end > Duration.zero;

  void _startPreview() {
    final player = ref.read(playerProvider);
    _wasPlaying = player.current.isPlaying;
    _savedQueue = List<SongRef>.of(player.currentQueue);
    _savedIndex = player.current.currentIndex;
    _posSub = player.positions.listen((pos) {
      if (_previewing && pos >= _end) {
        player.seek(_start);
      }
    });
    // Enqueue only this song and jump to the user's start offset.
    unawaited(player.playQueue([widget.song]));
    player.seek(_start);
    setState(() => _previewing = true);
  }

  void _stopPreview() {
    _posSub?.cancel();
    _posSub = null;
    final player = ref.read(playerProvider);
    player.pause();
    _previewing = false;
    if (_wasPlaying && _savedQueue.isNotEmpty) {
      player.playQueue(
        _savedQueue,
        startIndex: _savedIndex < 0 ? 0 : _savedIndex,
      );
    }
    _savedQueue = const [];
    _savedIndex = -1;
  }

  Future<void> _saveCue() async {
    final repo = ref.read(libraryRepositoryProvider);
    final key = widget.song.identityKey;
    await repo.kvSet('ringtone_cue:$key', _start.inMilliseconds.toString());
    await repo.kvSet('ringtone_cue_end:$key', _end.inMilliseconds.toString());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Ringtone range saved (${_format(_start)} - ${_format(_end)}). '
          'Full file trimming is a future feature; set the ringtone via '
          'system Settings for now.',
        ),
      ),
    );
  }

  static String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final total = _end;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ringtone cutter'),
        actions: [
          if (_canPreview)
            IconButton(
              icon: Icon(
                _previewing ? Icons.stop_rounded : Icons.play_arrow_rounded,
              ),
              tooltip: _previewing ? 'Stop preview' : 'Preview',
              onPressed: _previewing ? _stopPreview : _startPreview,
            ),
        ],
      ),
      body: !_canPreview
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.s5),
                child: Text(
                  'This song duration is unknown, so it cannot be trimmed.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                const SizedBox(height: AppTokens.s4),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppTokens.s5),
                  child: Text(
                    widget.song.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.song.artist != null)
                  Padding(
                    padding: EdgeInsets.only(
                      top: AppTokens.s1,
                      left: AppTokens.s5,
                      right: AppTokens.s5,
                    ),
                    child: Text(
                      widget.song.artist!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: AppTokens.s5),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppTokens.s5),
                  child: RangeSlider(
                    values: RangeValues(
                      _start.inSeconds.toDouble(),
                      _end.inSeconds.toDouble(),
                    ),
                    min: 0,
                    max: total.inSeconds.toDouble(),
                    divisions: total.inSeconds < 1 ? 1 : total.inSeconds,
                    labels: RangeLabels(_format(_start), _format(_end)),
                    onChanged: (v) {
                      final startMs = v.start.round().clamp(0, v.end.round());
                      final endMs = v.end.round();
                      setState(() {
                        _start = Duration(milliseconds: startMs);
                        _end = Duration(milliseconds: endMs);
                      });
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppTokens.s5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_format(_start), style: theme.textTheme.bodySmall),
                      Text(_format(_end), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: EdgeInsets.all(AppTokens.s4),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _end > _start ? _saveCue : null,
                      icon: Icon(Icons.save_rounded),
                      label: Text('Save ringtone range'),
                    ),
                  ),
                ),
                SizedBox(
                  height: MediaQuery.paddingOf(context).bottom + AppTokens.s3,
                ),
              ],
            ),
    );
  }
}

import 'dart:async';

import '../../../core/player/player_controller.dart';
import '../domain/ringtone_selection.dart';

/// Auditions the selected ringtone window through the existing
/// [PlayerController].
///
/// Rather than spinning up a second global playback engine (which would
/// contradict the single-engine architecture), it temporarily replays the
/// track confined to the selected window and faithfully restores the previous
/// queue and play state when it stops. Playback is looped within the window so
/// a short clip can be auditioned repeatedly, and calling [stop] or [dispose]
/// always returns the player to its prior session.
class RingtonePreviewer {
  RingtonePreviewer(this._player);

  final PlayerController _player;

  bool _previewing = false;
  bool get isPreviewing => _previewing;

  StreamSubscription<Duration>? _posSub;
  List<SongRef> _savedQueue = const [];
  int _savedIndex = -1;
  bool _wasPlaying = false;
  RingtoneSelection? _selection;

  /// Starts looping the [selection] of [song]. Any previous queue and play
  /// state are captured so they can be restored by [stop].
  Future<void> start({
    required SongRef song,
    required RingtoneSelection selection,
  }) async {
    if (_previewing) return;
    final snap = _player.current;
    _wasPlaying = snap.isPlaying;
    _savedQueue = List<SongRef>.of(_player.currentQueue);
    _savedIndex = snap.currentIndex;
    _selection = selection;
    _previewing = true;

    await _player.playQueue([song]);
    await _player.seek(selection.start);
    // Attach (or re-attach) the windowing listener AFTER seeking so the very
    // first position emission is judged against the real selection window.
    await _posSub?.cancel();
    _posSub = _player.positions.listen((pos) => _onPosition(pos));
  }

  void _onPosition(Duration pos) {
    final sel = _selection;
    if (!_previewing || sel == null) return;
    if (sel.contains(pos)) return;
    // Outside the window: loop back to the start of the selection. This keeps
    // playback confined to the selected range instead of running on to the end
    // of the track.
    unawaited(_player.seek(sel.start));
  }

  /// Stops previewing and restores the queue and play state that existed
  /// before [start]. Safe to call multiple times and from [dispose].
  Future<void> stop() async {
    if (!_previewing && _posSub == null) return;
    await _posSub?.cancel();
    _posSub = null;
    _previewing = false;
    _selection = null;
    await _player.pause();
    if (_savedQueue.isNotEmpty) {
      final index = _savedIndex < 0 ? 0 : _savedIndex;
      await _player.playQueue(_savedQueue, startIndex: index);
      if (!_wasPlaying) {
        // Only auto-resume what the user was actually listening to.
        await _player.pause();
      }
    }
    _savedQueue = const [];
    _savedIndex = -1;
  }

  Future<void> dispose() => stop();
}

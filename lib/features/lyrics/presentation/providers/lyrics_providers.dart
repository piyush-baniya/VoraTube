import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/lyrics.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../data/lyrics_service.dart';
import '../../data/lrclib_client.dart';

final lrclibClientProvider = Provider<LrclibClient>((ref) {
  final client = LrclibClient();
  ref.onDispose(client.dispose);
  return client;
});

final lyricsServiceProvider = Provider<LyricsService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final lrclib = ref.watch(lrclibClientProvider);
  return LyricsService(db: db, lrclib: lrclib);
});

/// Tracks the current lyrics state for the playing song.
///
/// Automatically re-fetches when the track changes. Exposes the lyrics
/// data, current line index, and status for the UI to render.
final currentLyricsProvider =
    AsyncNotifierProvider<CurrentLyricsNotifier, LyricsResult>(
      CurrentLyricsNotifier.new,
    );

class CurrentLyricsNotifier extends AsyncNotifier<LyricsResult> {
  StreamSubscription<Duration>? _positionSub;
  int _currentLineIndex = -1;

  int get currentLineIndex => _currentLineIndex;

  @override
  Future<LyricsResult> build() async {
    ref.onDispose(() {
      _positionSub?.cancel();
    });

    final snapshot = ref.watch(playbackSnapshotProvider).value;
    if (snapshot == null || !snapshot.hasTrack) {
      return const LyricsResult.notFound();
    }

    final song = snapshot.current!;
    final service = ref.read(lyricsServiceProvider);
    final result = await service.getLyrics(song);

    if (result.data?.hasSyncedLines == true) {
      _startPositionTracking();
    }

    return result;
  }

  void _startPositionTracking() {
    _positionSub?.cancel();
    _positionSub = ref.read(playerProvider).positions.listen((position) {
      _updateCurrentLine(position);
    });
  }

  void _updateCurrentLine(Duration position) {
    final lyrics = state.value?.data;
    if (lyrics == null || !lyrics.hasSyncedLines) return;

    final positionMs = position.inMilliseconds;
    final lines = lyrics.lines;

    int newIndex = -1;
    for (var i = lines.length - 1; i >= 0; i--) {
      final ts = lines[i].startTimeMs;
      if (ts != null && positionMs >= ts) {
        newIndex = i;
        break;
      }
    }

    if (newIndex != _currentLineIndex) {
      _currentLineIndex = newIndex;
    }
  }

  void seekToLine(int index) {
    final lyrics = state.value?.data;
    if (lyrics == null) return;
    if (index < 0 || index >= lyrics.lines.length) return;

    final ts = lyrics.lines[index].startTimeMs;
    if (ts != null) {
      ref.read(playerProvider).seek(Duration(milliseconds: ts));
    }
  }
}

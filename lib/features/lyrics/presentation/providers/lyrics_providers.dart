import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/lyrics.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../data/lrclib_client.dart';
import '../../data/lyrics_service.dart';

final lrclibClientProvider = Provider<LrclibClient>((ref) {
  final client = LrclibClient();
  ref.onDispose(client.dispose);
  return client;
});

final lyricsServiceProvider = Provider<LyricsService>((ref) {
  return LyricsService(
    db: ref.watch(appDatabaseProvider),
    lrclib: ref.watch(lrclibClientProvider),
  );
});

/// Loads lyrics for the current track.
///
/// This provider deliberately owns only immutable lyric data. In particular,
/// it does not expose a disposable listenable to widgets: a widget can outlive
/// an asynchronous provider refresh during navigation or a track transition.
///
/// It watches only the track identity, never the whole playback snapshot, so
/// pausing or resuming never triggers a refetch.
final currentLyricsProvider = FutureProvider.autoDispose<LyricsResult>((
  ref,
) async {
  final song = ref.watch(currentTrackProvider);
  if (song == null) {
    return const LyricsResult.notFound();
  }

  return ref.read(lyricsServiceProvider).getLyrics(song);
});

/// Emits the active synced-lyric line for the current lyrics result.
///
/// Riverpod owns the player-position subscription and cancels it as soon as
/// no lyrics widget is listening. This prevents providers from updating
/// widget-owned state, and prevents widgets from retaining disposed provider
/// objects.
final currentLyricLineIndexProvider = StreamProvider.autoDispose<int>((ref) {
  final lyrics = ref.watch(currentLyricsProvider).valueOrNull?.data;
  if (lyrics == null || !lyrics.hasSyncedLines) {
    return Stream.value(-1);
  }

  final lines = lyrics.lines;
  return ref
      .watch(playerProvider)
      .positions
      .map((position) => lyricLineIndexAt(lines, position))
      .distinct();
});

int lyricLineIndexAt(List<LyricsLine> lines, Duration position) {
  final positionMs = position.inMilliseconds;
  for (var index = lines.length - 1; index >= 0; index--) {
    final startTimeMs = lines[index].startTimeMs;
    if (startTimeMs != null && positionMs >= startTimeMs) return index;
  }
  return -1;
}

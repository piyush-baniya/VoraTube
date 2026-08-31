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

/// Lyrics the user chose explicitly for the current song — from an online
/// result they picked or an uploaded .lrc file. Shown in place of the
/// provider-driven result and reset when the track changes.
final manualLyricsProvider = StateProvider.autoDispose<LyricsData?>((ref) {
  // Watching the identity means a track transition rebuilds this provider,
  // clearing any lyrics chosen for the previous song.
  ref.watch(currentTrackIdentityProvider);
  return null;
});

/// The lyrics currently in effect: the user's explicit choice wins, otherwise
/// whatever the standard pipeline resolved.
final activeLyricsProvider = Provider<LyricsData?>((ref) {
  final manual = ref.watch(manualLyricsProvider);
  if (manual != null) return manual;
  return ref.watch(currentLyricsProvider).valueOrNull?.data;
});

/// The user's stored .lrc payload for the current song, or null. Used both to
/// show the "Show lyrics from uploaded LRC file" action and to let the lyrics
/// pipeline prefer the upload automatically.
final uploadedLrcProvider = FutureProvider.autoDispose<String?>((ref) async {
  final song = ref.watch(currentTrackProvider);
  if (song == null) return null;
  final service = ref.watch(lyricsServiceProvider);
  final stored = await service.userLrc.load(song.identityKey);
  ref.keepAlive();
  return stored?.lrc;
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
  final lyrics = ref.watch(activeLyricsProvider);
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

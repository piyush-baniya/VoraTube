import '../../../core/player/player_controller.dart';
import 'library_models.dart';

/// Playback intent for a visible list of songs.
final class PlayContext {
  const PlayContext({required this.refs, required this.startIndex});

  final List<SongRef> refs;
  final int startIndex;
}

typedef OnPlaySong = void Function(PlayContext context);

/// Converts a decorated library row into an engine-agnostic [SongRef] so
/// player code stays decoupled from Drift types.
SongRef songTileToRef(SongTileData tile) {
  final song = tile.song;
  final key = song.source == 'mediastore'
      ? 'ms:${song.mediaStoreId}'
      : 'h:${song.contentHash}';
  return SongRef(
    identityKey: key,
    uri: song.contentUri,
    title: song.title,
    artist: song.artist,
    album: song.albumName,
    artPath: tile.artPath,
    durationMs: song.durationMs,
  );
}

/// Builds a play context from a list of tiles starting at [startIndex].
PlayContext playContextFromTiles(List<SongTileData> tiles, int startIndex) {
  return PlayContext(
    refs: [for (final t in tiles) songTileToRef(t)],
    startIndex: startIndex,
  );
}

import '../../library/data/library_models.dart';

final class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.pinned,
    required this.songCount,
    required this.covers,
    this.totalDurationMs = 0,
  });

  final int id;
  final String name;
  final bool pinned;
  final int songCount;

  /// Up to three artwork paths (most recent positions first) used to draw
  /// the mosaic collage. Entries may be null when songs lack artwork.
  final List<String?> covers;
  final int totalDurationMs;
}

/// A playlist row plus its decorated song payload for detail screens.
typedef PlaylistEntry = SongTileData;

class DuplicatePlaylistNameException implements Exception {
  const DuplicatePlaylistNameException(this.name);

  final String name;

  @override
  String toString() => 'A playlist named "$name" already exists';
}

class PlaylistNotFoundException implements Exception {
  const PlaylistNotFoundException(this.id);

  final int id;

  @override
  String toString() => 'Playlist $id does not exist';
}

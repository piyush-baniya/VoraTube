import '../../../core/db/app_database.dart' show Song, Playlist;
import '../../../core/ingest/ingest_service.dart' show ReplayGainInfo;

enum LibrarySection { songs, albums, artists, genres }

enum SongSort {
  recentlyAdded,
  title,
  artist,
  album,
  duration;

  String get label => switch (this) {
    SongSort.recentlyAdded => 'Recently added',
    SongSort.title => 'Title',
    SongSort.artist => 'Artist',
    SongSort.album => 'Album',
    SongSort.duration => 'Duration',
  };
}

/// One page of song rows plus a cursor for fetching the next page.
final class SongTileData {
  const SongTileData({required this.song, this.artPath, this.replayGain});

  final Song song;
  final String? artPath;
  final ReplayGainInfo? replayGain;
}

final class SongPage {
  const SongPage({required this.songs, required this.nextOffset});

  final List<SongTileData> songs;
  final int nextOffset;

  bool get hasMore => nextOffset >= 0;
}

final class AlbumSummary {
  const AlbumSummary({
    required this.albumRowId,
    required this.key,
    required this.name,
    this.artistName,
    this.artPath,
    required this.songCount,
    this.totalDurationMs = 0,
  });

  final int albumRowId;
  final String key;
  final String name;
  final String? artistName;
  final String? artPath;
  final int songCount;
  final int totalDurationMs;
}

final class ArtistSummary {
  const ArtistSummary({
    required this.artistRowId,
    required this.key,
    required this.name,
    this.artPath,
    required this.songCount,
  });

  final int artistRowId;
  final String key;
  final String name;
  final String? artPath;
  final int songCount;
}

final class GenreSummary {
  const GenreSummary({required this.genre, required this.songCount});

  final String genre;
  final int songCount;
}

final class SearchResults {
  const SearchResults({
    required this.query,
    required this.songs,
    required this.albums,
    required this.artists,
    required this.playlists,
  });

  final String query;
  final List<SongTileData> songs;
  final List<AlbumSummary> albums;
  final List<ArtistSummary> artists;
  final List<Playlist> playlists;

  bool get isEmpty =>
      songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;
}

final class ListeningStats {
  const ListeningStats({
    required this.totalSongs,
    required this.totalPlays,
    required this.totalListeningMs,
    required this.favoritesCount,
    required this.mostPlayedCount,
    required this.recentlyPlayedCount,
    this.mostPlayedSongTitle,
    this.mostPlayedSongArtist,
    this.mostPlayedSongCount = 0,
  });

  final int totalSongs;
  final int totalPlays;
  final int totalListeningMs;
  final int favoritesCount;
  final int mostPlayedCount;
  final int recentlyPlayedCount;

  /// Top-scoring song across the whole library, for a featured stat card.
  final String? mostPlayedSongTitle;
  final String? mostPlayedSongArtist;
  final int mostPlayedSongCount;

  bool get hasActivity => totalPlays > 0;

  bool get hasMostPlayedSong =>
      mostPlayedSongTitle != null && mostPlayedSongCount > 0;

  String get formattedListeningTime {
    final hours = totalListeningMs ~/ 3600000;
    final minutes = (totalListeningMs % 3600000) ~/ 60000;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}

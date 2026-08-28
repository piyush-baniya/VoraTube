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
    this.playlistCountsById = const {},
  });

  final String query;
  final List<SongTileData> songs;
  final List<AlbumSummary> albums;
  final List<ArtistSummary> artists;
  final List<Playlist> playlists;

  /// Playlist row id -> number of songs in that playlist, so search result
  /// tiles show a real count without inventing a `songCount` on [Playlist].
  final Map<int, int> playlistCountsById;

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
    this.mostPlayedSongArtPath,
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

  /// Cached artwork path for [mostPlayedSongTitle], resolved the same way the
  /// song lists do (song_extras override, then album art). Null when the song
  /// has no resolved artwork yet.
  final String? mostPlayedSongArtPath;

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

/// A single "top" entry (song or artist) derived from [ListeningBreakdown].
///
/// `count` is the number of plays contributed by that entry in the period.
final class HistoryTopEntry {
  const HistoryTopEntry({
    required this.label,
    required this.count,
    this.artist,
  });

  final String label;
  final String? artist;
  final int count;
}

/// A period (week / year) aggregated from [ListeningBreakdown].
final class PeriodStats {
  const PeriodStats({
    required this.listenedMs,
    required this.plays,
    required this.uniqueSongs,
    this.topSongs = const [],
    this.topArtist,
  });

  final int listenedMs;
  final int plays;
  final int uniqueSongs;
  final List<HistoryTopEntry> topSongs;
  final HistoryTopEntry? topArtist;

  bool get hasActivity => plays > 0;
}

/// The single most-listened day within the analyzed window.
final class PeakDayStats {
  const PeakDayStats({
    required this.day,
    required this.listenedMs,
    required this.plays,
  });

  final DateTime day;
  final int listenedMs;
  final int plays;
}

/// A day-of-listening bar used by the lightweight weekly chart.
final class DayListen {
  const DayListen({required this.day, required this.listenedMs});

  final DateTime day;
  final int listenedMs;
}

/// Complete, time-series-backed listening breakdown for the statistics screen.
///
/// Unlike [ListeningStats] (which estimates listening time from play counts),
/// every field here is aggregated from persisted `play_history` records —
/// actual, measured listening time plus the timestamp of each play.
final class ListeningBreakdown {
  const ListeningBreakdown({
    required this.totalListenedMs,
    required this.totalPlays,
    required this.totalUniqueSongs,
    this.peakDay,
    this.topArtist,
    required this.week,
    required this.year,
    required this.weekDaily,
    required this.yearMonthly,
  });

  final int totalListenedMs;
  final int totalPlays;
  final int totalUniqueSongs;
  final PeakDayStats? peakDay;
  final HistoryTopEntry? topArtist;
  final PeriodStats week;
  final PeriodStats year;
  final List<DayListen> weekDaily;
  final List<DayListen> yearMonthly;

  bool get hasActivity => totalPlays > 0;
}

/// Formats milliseconds as `Xm`, `Xh Ym` or `Xd Yh` — matching the compact
/// Home stats style (e.g. `42 min`, `2 hr 14 min`, `18 hr 32 min`).
String formatListeningDuration(int ms) {
  if (ms < 0) ms = 0;
  final totalMinutes = ms ~/ 60000;
  final days = totalMinutes ~/ (60 * 24);
  final hours = (totalMinutes % (60 * 24)) ~/ 60;
  final minutes = totalMinutes % 60;
  if (days > 0) {
    if (hours > 0) return '${days}d ${hours}h';
    return '${days}d';
  }
  if (hours > 0) {
    if (minutes > 0) return '${hours}h ${minutes}m';
    return '${hours}h';
  }
  return '${minutes}m';
}

final class IngestTrack {
  const IngestTrack({
    required this.mediaStoreId,
    required this.contentUri,
    required this.durationMs,
    required this.dateModifiedSec,
    required this.albumMediaStoreId,
    required this.artistMediaStoreId,
    this.path,
    this.title,
    this.artist,
    this.albumArtist,
    this.album,
    this.genre,
    this.year,
    this.trackNumber,
    this.discNumber,
    this.dateAddedSec,
    this.sizeBytes,
  });

  final int mediaStoreId;
  final String contentUri;
  final String? path;
  final String? title;
  final String? artist;
  final String? albumArtist;
  final String? album;
  final String? genre;
  final int albumMediaStoreId;
  final int artistMediaStoreId;
  final int durationMs;
  final int dateModifiedSec;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final int? dateAddedSec;
  final int? sizeBytes;
}

final class ResolvedArtwork {
  const ResolvedArtwork({required this.smallPath, required this.largePath});

  final String? smallPath;
  final String? largePath;

  bool get hasArt => smallPath != null && largePath != null;
}

enum ScanPhase { reading, artwork, finalizing }

final class ScanProgress {
  const ScanProgress({
    required this.phase,
    required this.processedCount,
    this.addedCount = 0,
    this.totalHint,
  });

  final ScanPhase phase;
  final int processedCount;
  final int addedCount;
  final int? totalHint;
}

final class ScanSummary {
  const ScanSummary({
    required this.totalSongs,
    required this.addedSongs,
    required this.updatedSongs,
    required this.removedSongs,
    required this.artworkAttempts,
    required this.artworksResolved,
    required this.completedAt,
  });

  final int totalSongs;
  final int addedSongs;
  final int updatedSongs;
  final int removedSongs;
  final int artworkAttempts;
  final int artworksResolved;
  final DateTime completedAt;
}

abstract interface class IngestService {
  Future<void> prepareScan();

  Future<List<IngestTrack>> getAudioBatch({
    required int afterId,
    required int limit,
  });

  Future<Map<int, ResolvedArtwork?>> resolveArtwork(Set<int> albumIds);
}

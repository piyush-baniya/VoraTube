import 'dart:io';
import 'dart:typed_data';

enum IngestSource { mediastore, imported }

enum IngestCapability { scan, import }

final class IngestCapabilities {
  const IngestCapabilities(this.allowed);

  final Set<IngestCapability> allowed;

  bool get canScan => allowed.contains(IngestCapability.scan);
  bool get canImport => allowed.contains(IngestCapability.import);
}

final class ResolvedArtwork {
  const ResolvedArtwork({required this.smallPath, required this.largePath});

  final String? smallPath;
  final String? largePath;

  bool get hasArt => smallPath != null && largePath != null;
}

final class ExtractedMetadata {
  const ExtractedMetadata({
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.genre,
    this.year,
    this.trackNumber,
    this.discNumber,
    this.durationMs,
    this.pictureBytes,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? genre;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final int? durationMs;
  final Uint8List? pictureBytes;
}

abstract interface class MetadataReader {
  ExtractedMetadata read(String filePath);
}

final class IngestTrack {
  const IngestTrack({
    required this.source,
    required this.contentUri,
    required this.durationMs,
    required this.dateModifiedSec,
    this.mediaStoreId,
    this.albumMediaStoreId,
    this.artistMediaStoreId,
    this.contentHash,
    this.albumKey,
    this.artistKey,
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
  }) : assert(
         source != IngestSource.mediastore || mediaStoreId != null,
         'MediaStore tracks require a mediaStoreId',
       ),
       assert(
         source != IngestSource.imported || contentHash != null,
         'Imported tracks require a contentHash',
       );

  final IngestSource source;

  /// Android only: MediaStore identifier of the song/album/artist.
  final int? mediaStoreId;
  final int? albumMediaStoreId;
  final int? artistMediaStoreId;

  /// IOS import only: SHA-256 hex of the copied file's bytes.
  final String? contentHash;

  /// Stable cross-platform identity for grouping:
  /// `'ms:<mediaStoreAlbumId>'` on Android, `'n:<name-hash>'` on iOS,
  /// null when the track has no usable album/artist information.
  final String? albumKey;
  final String? artistKey;

  final String contentUri;
  final String? path;
  final String? title;
  final String? artist;
  final String? albumArtist;
  final String? album;
  final String? genre;
  final int durationMs;
  final int dateModifiedSec;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final int? dateAddedSec;
  final int? sizeBytes;

  String get identityKey =>
      source == IngestSource.mediastore ? 'ms:$mediaStoreId' : 'h:$contentHash';
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

enum ImportPhase { copying, artwork, finalizing }

final class ImportProgress {
  const ImportProgress({
    required this.phase,
    required this.processedCount,
    required this.totalCount,
    this.importedCount = 0,
    this.skippedCount = 0,
    this.failedCount = 0,
  });

  final ImportPhase phase;
  final int processedCount;
  final int totalCount;
  final int importedCount;
  final int skippedCount;
  final int failedCount;
}

final class FailedImport {
  const FailedImport({required this.fileName, required this.reason});

  final String fileName;
  final String reason;
}

final class ImportSummary {
  const ImportSummary({
    required this.totalSelected,
    required this.importedSongs,
    required this.skippedDuplicates,
    required this.failures,
    required this.completedAt,
  });

  final int totalSelected;
  final int importedSongs;
  final int skippedDuplicates;
  final List<FailedImport> failures;
  final DateTime completedAt;

  int get failedCount => failures.length;
}

final class PickedImportFile {
  const PickedImportFile({required this.tempPath, required this.fileName});

  final String tempPath;
  final String fileName;
}

final class ProcessedImport {
  const ProcessedImport({required this.track, required this.artworkBytes});

  final IngestTrack track;

  /// Raw embedded artwork, if the source file carried any. Decoding into
  /// display tiers happens on the UI side so the worker isolate stays
  /// free of Flutter engine dependencies.
  final Uint8List? artworkBytes;
}

class ImportProcessingException implements Exception {
  const ImportProcessingException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// The public ingestion contract for VoraTube.
///
/// Platform differences live entirely behind this interface:
///
/// ANDROID: MediaStore enumeration. The user grants READ_MEDIA_AUDIO.
/// MediaStore owns the source media; tracks are identified by
/// `mediaStoreId` and referenced through content URIs.
///
/// IOS: user-initiated import. The user picks audio files; VoraTube copies
/// them into its own sandbox (`Documents/Library/<id>/<name>`) and owns the
/// copies. No music-library permission is requested. Tracks are identified
/// by content hash.
abstract interface class IngestService {
  IngestCapabilities get capabilities;

  Future<void> prepareScan();

  Future<List<IngestTrack>> getAudioBatch({
    required int afterId,
    required int limit,
  });

  Future<Map<String, ResolvedArtwork?>> resolveArtwork(Set<String> albumKeys);

  Future<List<PickedImportFile>> pickImportFiles();

  Future<ProcessedImport> processImportFile(PickedImportFile file);

  Future<Directory?> importedFilesRoot();
}

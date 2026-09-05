import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

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

/// One artwork lookup, addressed by every handle the platform might need.
///
/// Album art used to be requested by album id alone. That fails for two large
/// classes of track: anything whose MediaStore `album_id` is 0 (singles, voice
/// memos, most downloaded files), and anything on Android 10+, where the
/// `albumart` provider that album ids resolved through no longer exists.
/// Carrying the song id and file path alongside the album id lets the native
/// side fall back to per-song thumbnails and then to embedded cover art.
final class ArtworkTarget {
  const ArtworkTarget({
    required this.key,
    this.albumMediaStoreId,
    this.audioMediaStoreId,
    this.path,
    this.preferEmbedded = false,
  });

  /// Album-scoped lookup: one decode is cached under the album key and shared
  /// by every track on the album. [audioMediaStoreId] and [path] point at a
  /// representative member track, which is what the per-song fallbacks need.
  factory ArtworkTarget.album({
    required String albumKey,
    int? albumMediaStoreId,
    int? audioMediaStoreId,
    String? path,
  }) => ArtworkTarget(
    key: albumKey,
    albumMediaStoreId: albumMediaStoreId,
    audioMediaStoreId: audioMediaStoreId,
    path: path,
  );

  /// Song-scoped lookup for tracks that belong to no album at all.
  ///
  /// The prefix is what makes the result routable: album keys and song identity
  /// keys are both shaped `ms:<int>`, so without it a returned key would be
  /// ambiguous and artwork could be written to the wrong row.
  ///
  /// Song-scoped targets always resolve embedded artwork first (see
  /// [preferEmbedded]).
  factory ArtworkTarget.song({
    required String identityKey,
    int? audioMediaStoreId,
    String? path,
  }) => ArtworkTarget(
    key: '$songKeyPrefix$identityKey',
    audioMediaStoreId: audioMediaStoreId,
    path: path,
    preferEmbedded: true,
  );

  static const String songKeyPrefix = 'song:';

  /// Cache identity, and the key results are returned under.
  final String key;

  /// MediaStore album id, when the track belongs to a known album.
  final int? albumMediaStoreId;

  /// MediaStore song id — the only handle that works for album-less tracks.
  final int? audioMediaStoreId;

  /// Absolute file path, used for embedded-artwork extraction.
  final String? path;

  /// When true, the native resolver reads the track's own embedded artwork
  /// before consulting any MediaStore thumbnail.
  ///
  /// This matters for song-scoped targets: MediaStore generates song
  /// thumbnails from the *album's* artwork, so a thumbnail-first strategy
  /// resolves every track of an album to the same image and per-song covers
  /// (tracks with their own embedded art) can never appear. Embedded-first
  /// makes per-song artwork distinct; the thumbnail remains the fallback for
  /// tracks without embedded art.
  final bool preferEmbedded;

  bool get isSongScoped => isSongKey(key);

  static bool isSongKey(String key) => key.startsWith(songKeyPrefix);

  /// Strips [songKeyPrefix], yielding the bare identity key.
  static String identityKeyOf(String key) =>
      isSongKey(key) ? key.substring(songKeyPrefix.length) : key;

  Map<String, Object?> toChannelMap() => <String, Object?>{
    'key': key,
    'albumId': albumMediaStoreId,
    'audioId': audioMediaStoreId,
    'path': path,
    'preferEmbedded': preferEmbedded,
  };

  @override
  bool operator ==(Object other) =>
      other is ArtworkTarget &&
      other.key == key &&
      other.albumMediaStoreId == albumMediaStoreId &&
      other.audioMediaStoreId == audioMediaStoreId &&
      other.path == path &&
      other.preferEmbedded == preferEmbedded;

  @override
  int get hashCode =>
      Object.hash(key, albumMediaStoreId, audioMediaStoreId, path, preferEmbedded);
}

/// ReplayGain information extracted from audio metadata.
final class ReplayGainInfo {
  const ReplayGainInfo({
    this.trackGainDb,
    this.trackPeak,
    this.albumGainDb,
    this.albumPeak,
  });

  /// Track gain in dB (e.g., -3.5). Apply as volume multiplier: 10^(gain/20)
  final double? trackGainDb;

  /// Track peak as linear amplitude (0.0-1.0 or higher)
  final double? trackPeak;

  /// Album gain in dB (for album-level normalization)
  final double? albumGainDb;

  /// Album peak as linear amplitude
  final double? albumPeak;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayGainInfo &&
          runtimeType == other.runtimeType &&
          trackGainDb == other.trackGainDb &&
          trackPeak == other.trackPeak &&
          albumGainDb == other.albumGainDb &&
          albumPeak == other.albumPeak;

  @override
  int get hashCode => Object.hash(trackGainDb, trackPeak, albumGainDb, albumPeak);

  bool get hasTrackGain => trackGainDb != null;
  bool get hasAlbumGain => albumGainDb != null;

  /// Compute volume multiplier for track gain (clamped to prevent clipping)
  double trackGainMultiplier({
    double preampDb = 0.0,
    bool preventClipping = true,
  }) {
    if (trackGainDb == null) return 1.0;
    var gainDb = trackGainDb! + preampDb;
    if (preventClipping && trackPeak != null) {
      // 0 dBFS = 1.0 linear. If applying gain would exceed 1.0, reduce.
      final peakAfterGain = trackPeak! * pow(10.0, gainDb / 20.0);
      if (peakAfterGain > 1.0) {
        gainDb = 20.0 * log(1.0 / trackPeak!) / ln10;
      }
    }
    return pow(10.0, gainDb / 20.0).toDouble();
  }

  /// Compute volume multiplier for album gain
  double albumGainMultiplier({
    double preampDb = 0.0,
    bool preventClipping = true,
  }) {
    if (albumGainDb == null) return 1.0;
    var gainDb = albumGainDb! + preampDb;
    if (preventClipping && albumPeak != null) {
      final peakAfterGain = albumPeak! * pow(10.0, gainDb / 20.0);
      if (peakAfterGain > 1.0) {
        gainDb = 20.0 * log(1.0 / albumPeak!) / ln10;
      }
    }
    return pow(10.0, gainDb / 20.0).toDouble();
  }
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
    this.replayGain,
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
  final ReplayGainInfo? replayGain;
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
    this.replayGain,
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
  final ReplayGainInfo? replayGain;

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

  /// Resolves artwork for [targets], keyed by [ArtworkTarget.key].
  ///
  /// A key is absent from the result when the platform could not be reached at
  /// all; it maps to `null` when every strategy was tried and none produced an
  /// image. Callers must treat those two cases differently — the first is
  /// retryable, the second should be recorded so the same failure is not
  /// retried on every scan.
  Future<Map<String, ResolvedArtwork?>> resolveArtwork(
    List<ArtworkTarget> targets,
  );

  Future<List<PickedImportFile>> pickImportFiles();

  Future<ProcessedImport> processImportFile(PickedImportFile file);

  Future<Directory?> importedFilesRoot();
}

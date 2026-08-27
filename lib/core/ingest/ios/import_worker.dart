import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../ingest_service.dart';
import '../metadata/metadata_reader.dart';
import '../../../core/utils/string_utils.dart';

/// Extensions VoraTube accepts on iOS import. OGG/Vorbis is deliberately
/// absent: iOS system decoders cannot play it, so ingesting it would
/// produce entries that can never be played. ALAC arrives as `.m4a`.
const supportedImportExtensions = <String>{
  'mp3',
  'm4a',
  'm4b',
  'aac',
  'flac',
  'wav',
  'aif',
  'aiff',
};

final class ProcessImportRequest {
  const ProcessImportRequest({
    required this.tempPath,
    required this.fileName,
    required this.libraryRootPath,
    required this.fileId,
  });

  final String tempPath;
  final String fileName;
  final String libraryRootPath;
  final String fileId;
}

String sanitizeFileName(String raw, String fallbackExt) {
  final cleaned = raw
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty || cleaned == '_') {
    return 'audio.$fallbackExt';
  }
  return cleaned;
}

String? albumKeyFor(String? album, String? albumArtist, String? artist) {
  final name = album?.trim().toLowerCase();
  if (name == null || name.isEmpty) {
    return null;
  }
  final group = (albumArtist ?? artist)?.trim().toLowerCase() ?? '';
  final digest = sha256.convert(utf8.encode('$name|$group'));
  return 'n:${digest.toString().substring(0, 24)}';
}

String? artistKeyFor(String? artist) {
  final name = artist?.trim().toLowerCase();
  if (name == null || name.isEmpty) {
    return null;
  }
  final digest = sha256.convert(utf8.encode(name));
  return 'a:${digest.toString().substring(0, 24)}';
}

Future<ProcessedImport> processPickedImportFile(
  ProcessImportRequest request, {
  MetadataReader? reader,
}) async {
  final dot = request.fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : request.fileName.substring(dot + 1).toLowerCase();
  if (!supportedImportExtensions.contains(ext)) {
    throw ImportProcessingException('Unsupported format (.$ext)');
  }

  final sourceFile = File(request.tempPath);
  if (!sourceFile.existsSync()) {
    throw const ImportProcessingException(
      'The selected file is no longer available',
    );
  }

  final destDir = Directory(
    '${request.libraryRootPath}${request.libraryRootPath.endsWith('/') ? '' : '/'}${request.fileId}',
  );
  await destDir.create(recursive: true);

  final safeName = sanitizeFileName(request.fileName, ext);
  final destPath = '${destDir.path}/$safeName';

  var sizeBytes = 0;
  final digestSink = _DigestSink();
  final hasher = sha256.startChunkedConversion(digestSink);
  final output = File(destPath).openWrite();
  try {
    await for (final chunk in sourceFile.openRead()) {
      hasher.add(chunk);
      output.add(chunk);
      sizeBytes += chunk.length;
    }
    await output.flush();
  } catch (_) {
    hasher.close();
    await output.close().catchError((_) {});
    try {
      await File(destPath).delete();
    } catch (_) {}
    rethrow;
  }
  await output.close();
  hasher.close();
  final hashHex = digestSink.digest.toString();

  final metadataReader = reader ?? const AudioMetadataReaderImpl();
  ExtractedMetadata meta;
  try {
    meta = metadataReader.read(destPath);
  } catch (_) {
    try {
      Directory(destDir.path).deleteSync(recursive: true);
    } catch (_) {}
    throw const ImportProcessingException('The audio data could not be read');
  }

  final stat = await File(destPath).stat();
  final modifiedSec = stat.modified.millisecondsSinceEpoch ~/ 1000;

  final title = (meta.title != null && meta.title!.trim().isNotEmpty)
      ? meta.title!.trim()
      : (fallbackTitleFromPath(safeName) ?? 'Untitled');

  final track = IngestTrack(
    source: IngestSource.imported,
    contentHash: hashHex,
    contentUri: 'file://$destPath',
    path: destPath,
    title: title,
    artist: meta.artist,
    albumArtist: meta.albumArtist,
    album: meta.album,
    genre: meta.genre,
    year: meta.year,
    trackNumber: meta.trackNumber,
    discNumber: meta.discNumber,
    durationMs: meta.durationMs ?? 0,
    dateModifiedSec: modifiedSec,
    dateAddedSec: modifiedSec,
    sizeBytes: sizeBytes,
    albumKey: albumKeyFor(meta.album, meta.albumArtist, meta.artist),
    artistKey: artistKeyFor(meta.artist),
    replayGain: meta.replayGain,
  );

  return ProcessedImport(track: track, artworkBytes: meta.pictureBytes);
}

final class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}

  Digest get digest => _digest!;
}

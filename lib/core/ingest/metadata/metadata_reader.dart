import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart' as amr;

import '../ingest_service.dart';

/// VoraTube metadata abstraction.
///
/// The concrete implementation wraps `package:audio_metadata_reader`
/// (pure Dart, isolate-safe). Swapping the reader later only requires
/// changing this file â€” nothing else in the app knows which parser runs.
class AudioMetadataReaderImpl implements MetadataReader {
  const AudioMetadataReaderImpl();

  @override
  ExtractedMetadata read(String filePath) {
    final AudioMetadata meta;
    try {
      meta = amr.readMetadata(File(filePath), getImage: true);
    } on amr.MetadataParserException catch (e) {
      throw ImportProcessingException(e.message);
    } catch (_) {
      throw const ImportProcessingException('Unreadable audio file');
    }

    final picture = _bestPicture(meta.pictures);

    return ExtractedMetadata(
      title: meta.title,
      artist: meta.artist,
      album: meta.album,
      albumArtist: null,
      genre: meta.genres.isEmpty ? null : meta.genres.first,
      year: _parseYear(meta.year),
      trackNumber: meta.trackNumber,
      discNumber: meta.discNumber,
      durationMs: meta.duration?.inMilliseconds,
      pictureBytes: picture,
    );
  }

  Uint8List? _bestPicture(List<amr.Picture> pictures) {
    if (pictures.isEmpty) {
      return null;
    }
    for (final p in pictures) {
      if (p.pictureType == amr.PictureType.coverFront) {
        return p.bytes;
      }
    }
    return pictures.first.bytes;
  }

  int? _parseYear(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is String) {
      final m = RegExp(r'^(\d{4})').firstMatch(raw.trim());
      if (m != null) {
        return int.tryParse(m.group(1)!);
      }
    }
    return null;
  }
}

typedef AudioMetadata = amr.AudioMetadata;

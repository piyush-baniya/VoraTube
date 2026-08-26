import 'dart:io';

import 'package:flutter/services.dart';

import '../ingest_service.dart';

class AndroidIngestService implements IngestService {
  AndroidIngestService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('voratube/ingest_v1');

  final MethodChannel _channel;

  static const _unsupported = 'Android ingest supports MediaStore scans only';

  @override
  IngestCapabilities get capabilities =>
      const IngestCapabilities({IngestCapability.scan});
  @override
  Future<void> prepareScan() async {
    await _channel.invokeMethod<void>('prepareScan');
  }

  @override
  Future<List<IngestTrack>> getAudioBatch({
    required int afterId,
    required int limit,
  }) async {
    final Object? raw = await _channel.invokeMethod<Object?>(
      'getAudioBatch',
      <String, Object?>{'afterId': afterId, 'limit': limit.clamp(1, 1000)},
    );
    if (raw is! List<Object?>) {
      return const [];
    }
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(_parseTrack)
        .toList(growable: false);
  }

  @override
  Future<Map<String, ResolvedArtwork?>> resolveArtwork(
    Set<String> albumKeys,
  ) async {
    if (albumKeys.isEmpty) {
      return const {};
    }
    final ids = <int>[];
    for (final key in albumKeys) {
      final id = int.tryParse(key.startsWith('ms:') ? key.substring(3) : key);
      if (id != null) {
        ids.add(id);
      }
    }
    if (ids.isEmpty) {
      return const {};
    }
    final Object? raw = await _channel.invokeMethod<Object?>(
      'resolveArtwork',
      <String, Object?>{'albumIds': ids},
    );
    if (raw is! Map<Object?, Object?>) {
      return const {};
    }
    return {
      for (final entry in raw.entries)
        'ms:${(entry.key as num).toInt()}': _parseArtwork(entry.value),
    };
  }

  @override
  Future<List<PickedImportFile>> pickImportFiles() async {
    throw UnsupportedError(_unsupported);
  }

  @override
  Future<ProcessedImport> processImportFile(PickedImportFile file) async {
    throw UnsupportedError(_unsupported);
  }

  @override
  Future<Directory?> importedFilesRoot() async {
    throw UnsupportedError(_unsupported);
  }

  IngestTrack _parseTrack(Map<Object?, Object?> row) {
    final mediaStoreId = _reqInt(row, 'id');
    final albumMsId = _reqInt(row, 'albumId');
    final artistMsId = _reqInt(row, 'artistId');
    return IngestTrack(
      source: IngestSource.mediastore,
      mediaStoreId: mediaStoreId,
      albumMediaStoreId: albumMsId,
      artistMediaStoreId: artistMsId,
      albumKey: albumMsId > 0 ? 'ms:$albumMsId' : null,
      artistKey: artistMsId > 0 ? 'ms:$artistMsId' : null,
      contentUri: _reqStr(row, 'contentUri'),
      durationMs: _reqInt(row, 'durationMs'),
      dateModifiedSec: _reqInt(row, 'dateModifiedSec'),
      path: _str(row, 'path'),
      title: _str(row, 'title'),
      artist: _str(row, 'artist'),
      albumArtist: _str(row, 'albumArtist'),
      album: _str(row, 'album'),
      genre: _str(row, 'genre'),
      year: _intOrNull(row, 'year'),
      trackNumber: _intOrNull(row, 'track'),
      discNumber: _intOrNull(row, 'disc'),
      dateAddedSec: _intOrNull(row, 'dateAddedSec'),
      sizeBytes: _intOrNull(row, 'sizeBytes'),
    );
  }

  ResolvedArtwork? _parseArtwork(Object? value) {
    if (value is! Map<Object?, Object?>) {
      return null;
    }
    return ResolvedArtwork(
      smallPath: _str(value, 'small'),
      largePath: _str(value, 'large'),
    );
  }

  String _reqStr(Map<Object?, Object?> row, String key) =>
      row[key] as String? ?? '';

  int _reqInt(Map<Object?, Object?> row, String key) {
    final value = row[key];
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  int? _intOrNull(Map<Object?, Object?> row, String key) {
    final value = row[key];
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  String? _str(Map<Object?, Object?> row, String key) => row[key] as String?;
}

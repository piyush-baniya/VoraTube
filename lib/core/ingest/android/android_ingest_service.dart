import 'package:flutter/services.dart';

import '../ingest_service.dart';

class AndroidIngestService implements IngestService {
  AndroidIngestService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('voratube/ingest_v1');

  final MethodChannel _channel;

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
  Future<Map<int, ResolvedArtwork?>> resolveArtwork(Set<int> albumIds) async {
    if (albumIds.isEmpty) {
      return const {};
    }
    final Object? raw = await _channel.invokeMethod<Object?>(
      'resolveArtwork',
      <String, Object?>{'albumIds': albumIds.toList(growable: false)},
    );
    if (raw is! Map<Object?, Object?>) {
      return const {};
    }
    return {
      for (final entry in raw.entries)
        (entry.key as num).toInt(): _parseArtwork(entry.value),
    };
  }

  IngestTrack _parseTrack(Map<Object?, Object?> row) {
    return IngestTrack(
      mediaStoreId: _reqInt(row, 'id'),
      contentUri: _reqStr(row, 'contentUri'),
      durationMs: _reqInt(row, 'durationMs'),
      dateModifiedSec: _reqInt(row, 'dateModifiedSec'),
      albumMediaStoreId: _reqInt(row, 'albumId'),
      artistMediaStoreId: _reqInt(row, 'artistId'),
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

import 'dart:io';

import 'package:flutter/foundation.dart';
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
    final List<IngestTrack> result;
    try {
      final Object? raw = await _channel.invokeMethod<Object?>(
        'getAudioBatch',
        <String, Object?>{'afterId': afterId, 'limit': limit.clamp(1, 1000)},
      );
      if (raw is! List<Object?>) {
        _scanLog('QUERY_SUCCESS count=0 (non-list payload)');
        return const [];
      }
      result = raw
          .whereType<Map<Object?, Object?>>()
          .map(_parseTrack)
          .toList(growable: false);
    } catch (e, st) {
      // A genuine scan failure (e.g. SecurityException on the native query, a
      // revoked permission, or an unsupported MediaStore column) must surface
      // as an error, NOT be swallowed and shown as an empty library. The UI
      // distinguishes an empty success (empty state) from this (retry/error
      // state) exactly because we keep throwing.
      _scanLog('QUERY_FAILED exception=$e');
      Error.throwWithStackTrace(e, st);
    }
    // An empty cursor/result is SUCCESS with 0 songs — never an error here.
    // The scanner breaks out of its pagination loop and finalises the empty
    // library, which the UI renders as the empty state.
    _scanLog('QUERY_SUCCESS count=${result.length}');
    return result;
  }

  void _scanLog(String message) {
    if (kDebugMode) {
      debugPrint('VoraTube scan: $message');
    }
  }

  @override
  Future<Map<String, ResolvedArtwork?>> resolveArtwork(
    List<ArtworkTarget> targets,
  ) async {
    if (targets.isEmpty) {
      return const {};
    }
    final Object? raw = await _channel.invokeMethod<Object?>(
      'resolveArtwork',
      <String, Object?>{
        'targets': [for (final target in targets) target.toChannelMap()],
      },
    );
    if (raw is! Map<Object?, Object?>) {
      return const {};
    }
    // Keys come back verbatim as the strings we sent, so no reconstruction is
    // needed. The old code rebuilt `'ms:$id'` from an integer key, which quietly
    // dropped every non-MediaStore target.
    return <String, ResolvedArtwork?>{
      for (final entry in raw.entries)
        if (entry.key case final String key) key: _parseArtwork(entry.value),
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
    // Android audio lives in MediaStore (no app-controlled import folder), so
    // there is never an imported-files root. Returning null (instead of
    // throwing) lets read-side callers like missing-file reconciliation and
    // storage measurement treat "no such root" as simply nothing to reconcile —
    // reporting 0 files cleaned rather than a spurious failure.
    return null;
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
    final small = _str(value, 'small');
    final large = _str(value, 'large');
    // The native side answers with `{small: null, large: null}` when every
    // strategy failed. Collapsing that to null keeps the interface contract
    // honest: a present-but-empty ResolvedArtwork would read as success.
    if (small == null && large == null) {
      return null;
    }
    return ResolvedArtwork(smallPath: small, largePath: large);
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

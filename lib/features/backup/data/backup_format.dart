import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Public container for a VoraTube backup: `.vtb`.
///
/// Layout: magic (15 B) | formatVersion (u32 LE) | payloadLength (u64 LE) |
/// sha256 (32 B) | gzip(JSON payload).
///
/// The checksum covers the stored (compressed) payload bytes exactly, so a
/// truncated or corrupted file is always rejected before anything is parsed.
/// A raw SQLite/Drift page dump is deliberately never used: a structured JSON
/// payload can be migrated forward, a database file image cannot.
const backupMagic = 'VORATUBE-BACKUP';
const backupFormatVersion = 1;
const backupFileExtension = '.vtb';
const _digestLength = 32; // SHA-256
const _magicLength = 15;
const _headerLength = _magicLength + 4 + 8 + _digestLength;

/// Thrown for every rejectable backup problem: wrong magic, unsupported
/// version, truncation, checksum mismatch, malformed payload or missing
/// required fields. Carries a concise, user-showable reason.
class BackupFormatException implements Exception {
  BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Wraps a payload JSON map into the `.vtb` container.
Uint8List composeBackupBytes(Map<String, dynamic> json) {
  final encoded = utf8.encode(jsonEncode(json));
  final compressed = Uint8List.fromList(GZipCodec(level: 9).encode(encoded));
  final head = BytesBuilder();
  head.add(ascii.encode(backupMagic));
  head.add(_u32(backupFormatVersion));
  head.add(_u64(compressed.length));
  head.add(_digest(compressed));
  head.add(compressed);
  return head.toBytes();
}

/// Full structural + integrity validation of raw `.vtb` bytes, returning the
/// decoded payload JSON. Everything rejectable (magic, version, truncation,
/// checksum, malformed JSON, non-object payload) throws before a caller can
/// touch app state.
Map<String, dynamic> decodeBackupBytes(Uint8List bytes) {
  if (bytes.length < _headerLength) {
    throw BackupFormatException('File is too short to be a VoraTube backup');
  }
  if (!_bytesEqual(bytes.sublist(0, _magicLength), ascii.encode(backupMagic))) {
    throw BackupFormatException('Not a VoraTube backup file');
  }
  final view = ByteData.sublistView(bytes);
  final version = view.getUint32(_magicLength, Endian.little);
  final length = _u64At(view, _magicLength + 4);
  final checksumStart = _magicLength + 12;
  final payloadStart = checksumStart + _digestLength;
  if (version < 1 || version > backupFormatVersion) {
    throw BackupFormatException(
      version > backupFormatVersion
          ? 'Backup was made by a newer VoraTube version'
          : 'Backup has an unsupported format',
    );
  }
  if (bytes.length - payloadStart != length) {
    throw BackupFormatException('Backup is truncated or has extra data');
  }
  final payload = bytes.sublist(payloadStart);
  final stored = bytes.sublist(checksumStart, checksumStart + _digestLength);
  final computed = Uint8List.fromList(sha256.convert(payload).bytes);
  if (!_bytesEqual(stored, computed)) {
    throw BackupFormatException('Backup failed its integrity check');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(_inflate(payload), allowMalformed: false));
  } on BackupFormatException {
    rethrow;
  } catch (_) {
    throw BackupFormatException('Backup payload is malformed');
  }
  if (decoded is! Map<String, dynamic>) {
    throw BackupFormatException('Backup payload is malformed');
  }
  if (decoded['v'] is! int || decoded['v'] != version) {
    throw BackupFormatException('Backup header and payload disagree');
  }
  return decoded;
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Uint8List _digest(List<int> payload) =>
    Uint8List.fromList(sha256.convert(payload).bytes);

Uint8List _u32(int value) =>
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();

Uint8List _u64(int value) =>
    (ByteData(8)
          ..setUint32(0, value & 0xFFFFFFFF, Endian.little)
          ..setUint32(4, value >> 32, Endian.little))
        .buffer
        .asUint8List();

int _u64At(ByteData view, int offset) =>
    view.getUint32(offset + 4, Endian.little) * 0x100000000 +
    view.getUint32(offset, Endian.little);

/// `VoraTube Backup 2026-09-18 151533.vtb` — filesystem-safe, sortable, and
/// unique per minute so a new backup never overwrites the previous valid one.
String backupFileNameFor(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'VoraTube Backup '
      '${at.year}-${two(at.month)}-${two(at.day)} '
      '${two(at.hour)}${two(at.minute)}${two(at.second)}-${at.microsecondsSinceEpoch}$backupFileExtension';
}

List<int> _inflate(List<int> payload) {
  final output = _BoundedBytes();
  final decoder = gzip.decoder.startChunkedConversion(output);
  for (var offset = 0; offset < payload.length; offset += 65536) {
    decoder.add(
      payload.sublist(offset, (offset + 65536).clamp(0, payload.length)),
    );
  }
  decoder.close();
  return output.bytes.takeBytes();
}

class _BoundedBytes implements Sink<List<int>> {
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> data) {
    if (bytes.length + data.length > 128 * 1024 * 1024) {
      throw BackupFormatException('Backup payload exceeds 128 MB');
    }
    bytes.add(data);
  }

  @override
  void close() {}
}
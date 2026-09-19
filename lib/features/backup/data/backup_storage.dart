import 'package:flutter/services.dart';

/// App-private UI for the native SAF bridge, so the UI layer only ever deals
/// with opaque directory/file URIs and bytes.
class BackupStorage {
  const BackupStorage();
  static const _channel = MethodChannel('voratube/backup_storage_v1');
  Future<String?> pickDirectory() =>
      _channel.invokeMethod<String>('pickDirectory');
  Future<String?> pickBackupFile() => _channel.invokeMethod<String>('pickFile');
  Future<bool> hasPermission(String dirUri) async =>
      await _channel.invokeMethod<bool>('hasPermission', {'dirUri': dirUri}) ??
      false;
  Future<String> writeFile({
    required String dirUri,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final uri = await _channel.invokeMethod<String>('writeFile', {
      'dirUri': dirUri,
      'fileName': fileName,
      'bytes': bytes,
    });
    if (uri == null) throw StateError('Backup file was not created');
    return uri;
  }

  Future<Uint8List> readFile(String fileUri) async {
    final bytes = await _channel.invokeMethod<Uint8List>('readFile', {
      'fileUri': fileUri,
    });
    if (bytes == null) throw StateError('Backup file could not be read');
    return bytes;
  }

  Future<String?> displayName(String uri) =>
      _channel.invokeMethod<String>('displayName', {'uri': uri});
}
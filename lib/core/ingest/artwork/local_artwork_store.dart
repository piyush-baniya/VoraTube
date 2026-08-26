import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';

import '../ingest_service.dart';

final class SavedArtwork {
  const SavedArtwork({required this.smallPath, required this.largePath});

  final String? smallPath;
  final String? largePath;

  ResolvedArtwork? get asResolved => smallPath == null && largePath == null
      ? null
      : ResolvedArtwork(smallPath: smallPath, largePath: largePath);
}

/// Writes display-ready artwork tiers into application storage.
///
/// ANDROID note: MediaStore artwork is resolved natively (content URIs are
/// not readable from Dart), so Android uses its Kotlin pipeline in
/// VoraTubeIngestBridge instead of this class. This store serves imported
/// files whose embedded artwork bytes already live in Dart.
class LocalArtworkStore {
  LocalArtworkStore(this._baseDirPath);

  final String _baseDirPath;

  Directory get _baseDir => Directory(_baseDirPath);

  /// Stable key derived purely from payload content: identical artwork
  /// across songs/albums/imports is written exactly once.
  static String keyFor(Uint8List bytes) =>
      sha256.convert(bytes).toString().substring(0, 24);

  /// Saves one artwork payload under its content-derived key.
  ///
  /// Large tier keeps the original encoded bytes verbatim; small tier is a
  /// downscaled decode. Either tier may be null when generation fails —
  /// missing artwork must never break an import.
  Future<SavedArtwork?> save(Uint8List bytes) async {
    final artKey = keyFor(bytes);
    final ext = _extensionFor(bytes);
    await _baseDir.create(recursive: true);

    String? largePath;
    String? smallPath;

    try {
      final largeFile = File('${_baseDir.path}/${artKey}_l$ext');
      if (!largeFile.existsSync()) {
        await largeFile.writeAsBytes(bytes, flush: true);
      }
      largePath = largeFile.path;
    } catch (_) {
      largePath = null;
    }

    try {
      smallPath = await _writeSmallTier(bytes, artKey);
    } catch (_) {
      smallPath = null;
    }

    return SavedArtwork(smallPath: smallPath, largePath: largePath);
  }

  Future<String> _writeSmallTier(Uint8List bytes, String artKey) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 256);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    if (data == null) {
      throw StateError('small tier encoding failed');
    }
    final file = File('${_baseDir.path}/${artKey}_s.png');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return file.path;
  }

  String _extensionFor(Uint8List bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return '.png';
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return '.jpg';
    }
    return '.img';
  }
}

import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../ingest_service.dart';
import 'import_worker.dart';

/// IOS ingestion: user-initiated import into VoraTube-owned storage.
///
/// Pipeline per file:
///   1. document picker (temporary copy)
///   2. streamed copy into `Documents/Library/<id>/<name>` with SHA-256
///      computed over the same stream (no second read pass)
///   3. metadata extraction (pure-Dart reader, short-lived background
///      isolate)
///   4. embedded artwork bytes returned to the caller for tiered saving
///
/// No MPMediaLibrary access, no NSAppleMusicUsageDescription, no
/// security-scoped bookmarks: VoraTube owns every imported byte after the
/// copy completes.
class IosIngestService implements IngestService {
  const IosIngestService();

  static const _unsupported = 'IOS ingest supports imports only';

  @override
  IngestCapabilities get capabilities =>
      const IngestCapabilities({IngestCapability.import});

  @override
  Future<void> prepareScan() async {
    throw UnsupportedError(_unsupported);
  }

  @override
  Future<List<IngestTrack>> getAudioBatch({
    required int afterId,
    required int limit,
  }) async {
    throw UnsupportedError(_unsupported);
  }

  @override
  Future<Map<String, ResolvedArtwork?>> resolveArtwork(
    Set<String> albumKeys,
  ) async {
    throw UnsupportedError(_unsupported);
  }

  @override
  Future<List<PickedImportFile>> pickImportFiles() async {
    final result = await FilePicker.pickFiles(type: FileType.audio);
    if (result.isEmpty) {
      return const [];
    }
    return result
        .where((f) => f.path != null && f.name.isNotEmpty)
        .map((f) => PickedImportFile(tempPath: f.path!, fileName: f.name))
        .toList(growable: false);
  }

  @override
  Future<ProcessedImport> processImportFile(PickedImportFile file) async {
    final root = await importedFilesRoot();
    if (root == null) {
      throw const ImportProcessingException('Storage is not available');
    }
    final request = ProcessImportRequest(
      tempPath: file.tempPath,
      fileName: file.fileName,
      libraryRootPath: root.path,
      fileId: _newId(),
    );
    try {
      return await Isolate.run(() => processPickedImportFile(request));
    } on ImportProcessingException {
      rethrow;
    } catch (_) {
      throw const ImportProcessingException('The file could not be imported');
    }
  }

  @override
  Future<Directory?> importedFilesRoot() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final library = Directory('${docs.path}/Library');
      await library.create(recursive: true);
      return library;
    } catch (_) {
      return null;
    }
  }

  String _newId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rnd = Random.secure().nextInt(1 << 32).toRadixString(36);
    return '$now-$rnd';
  }
}

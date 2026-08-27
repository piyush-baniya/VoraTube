import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/core/ingest/ios/import_worker.dart';

final class _FakeReader implements MetadataReader {
  const _FakeReader({this.metadata, this.throwOnRead = false});

  final ExtractedMetadata? metadata;
  final bool throwOnRead;

  @override
  ExtractedMetadata read(String filePath) {
    if (throwOnRead) {
      throw const ImportProcessingException('Unreadable audio file');
    }
    return metadata!;
  }
}

ExtractedMetadata _meta({
  String? title,
  String? artist = 'Fake Artist',
  String? album = 'Fake Album',
  List<int> picture = const [],
}) {
  return ExtractedMetadata(
    title: title,
    artist: artist,
    album: album,
    durationMs: 99000,
    year: 2001,
    trackNumber: 3,
    pictureBytes: picture.isEmpty ? null : Uint8List.fromList(picture),
  );
}

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('vt_import_test');
  });

  tearDown(() {
    tempRoot.deleteSync(recursive: true);
  });

  ProcessImportRequest requestFor(String fileName, {String? sourcePath}) {
    return ProcessImportRequest(
      tempPath: sourcePath ?? '',
      fileName: fileName,
      libraryRootPath: '${tempRoot.path}/Library',
      fileId: 'id-${fileName.hashCode.abs()}',
    );
  }

  test(
    'copies file into permanent storage and computes content hash',
    () async {
      final source = File('${tempRoot.path}/source.mp3');
      source.writeAsBytesSync([1, 2, 3, 4, 5, 6, 7, 8]);

      final result = await processPickedImportFile(
        requestFor('song.mp3', sourcePath: source.path),
        reader: _FakeReader(metadata: _meta(title: 'T')),
      );

      expect(File(result.track.path!).existsSync(), isTrue);
      expect(result.track.path, contains('/Library/'));
      expect(result.track.contentHash, hasLength(64));
      expect(result.track.sizeBytes, 8);
      expect(result.track.source, IngestSource.imported);
      expect(result.track.title, 'T');
      expect(result.track.albumKey, startsWith('n:'));
      expect(result.track.artistKey, startsWith('a:'));
      // The worker must not leave anything under the picker's temp location.
      expect(result.track.path, isNot(equals(source.path)));
    },
  );

  test(
    'identical content yields identical hashes regardless of name',
    () async {
      final a = File('${tempRoot.path}/a.mp3')..writeAsBytesSync([9, 9, 9]);
      final b = File('${tempRoot.path}/b.mp3')..writeAsBytesSync([9, 9, 9]);

      final r1 = await processPickedImportFile(
        requestFor('first.mp3', sourcePath: a.path),
        reader: _FakeReader(metadata: _meta()),
      );
      final r2 = await processPickedImportFile(
        requestFor('second_name.mp3', sourcePath: b.path),
        reader: _FakeReader(metadata: _meta()),
      );

      expect(r1.track.identityKey, r2.track.identityKey);
    },
  );

  test('missing title falls back to filename', () async {
    final source = File('${tempRoot.path}/src.mp3')..writeAsBytesSync([1]);
    final result = await processPickedImportFile(
      requestFor('Cool Song Name.mp3', sourcePath: source.path),
      reader: _FakeReader(metadata: _meta(title: null)),
    );
    expect(result.track.title, 'Cool Song Name');
  });

  test('unsupported extension is rejected before any copy', () async {
    final source = File('${tempRoot.path}/v.ogg')..writeAsBytesSync([1]);
    await expectLater(
      processPickedImportFile(
        requestFor('v.ogg', sourcePath: source.path),
        reader: _FakeReader(metadata: _meta()),
      ),
      throwsA(isA<ImportProcessingException>()),
    );
    // Nothing was copied into the library.
    final libDir = Directory('${tempRoot.path}/Library');
    if (libDir.existsSync()) {
      expect(libDir.listSync(recursive: true), isEmpty);
    }
  });

  test(
    'unreadable metadata fails that file only and cleans its copy',
    () async {
      final good = File('${tempRoot.path}/good.mp3')
        ..writeAsBytesSync([1, 2, 3]);
      final bad = File('${tempRoot.path}/bad.mp3')..writeAsBytesSync([4, 5]);

      final badRequest = requestFor('bad.mp3', sourcePath: bad.path);
      await expectLater(
        processPickedImportFile(
          badRequest,
          reader: const _FakeReader(throwOnRead: true),
        ),
        throwsA(isA<ImportProcessingException>()),
      );

      final badDestDir = Directory(
        '${tempRoot.path}/Library/${badRequest.fileId}',
      );
      expect(badDestDir.existsSync(), isFalse);

      final goodResult = await processPickedImportFile(
        requestFor('good.mp3', sourcePath: good.path),
        reader: _FakeReader(metadata: _meta()),
      );
      expect(File(goodResult.track.path!).existsSync(), isTrue);
    },
  );

  test('embedded artwork bytes are surfaced for tiered saving', () async {
    final source = File('${tempRoot.path}/art.mp3')
      ..writeAsBytesSync([7, 7, 7]);
    final result = await processPickedImportFile(
      requestFor('art.mp3', sourcePath: source.path),
      reader: _FakeReader(metadata: _meta(picture: [255, 216, 255, 224])),
    );
    expect(result.artworkBytes, isNotNull);
    expect(result.artworkBytes, [255, 216, 255, 224]);
  });

  test('null artist or album produce null keys without crashing', () async {
    final source = File('${tempRoot.path}/bare.mp3')..writeAsBytesSync([1]);
    final result = await processPickedImportFile(
      requestFor('bare.mp3', sourcePath: source.path),
      reader: const _FakeReader(
        metadata: ExtractedMetadata(
          title: 'Only Title',
          artist: null,
          album: null,
          durationMs: 1000,
        ),
      ),
    );
    expect(result.track.albumKey, isNull);
    expect(result.track.artistKey, isNull);
    expect(result.track.title, 'Only Title');
  });
}

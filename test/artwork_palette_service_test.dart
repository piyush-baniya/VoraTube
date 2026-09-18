import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/core/artwork_palette/artwork_palette_cache.dart';
import 'package:vora_tube/core/artwork_palette/artwork_palette_extractor.dart';
import 'package:vora_tube/core/artwork_palette/artwork_palette_service.dart';

import 'fakes/tiny_png.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('palette_service_test');
  });
  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // best effort cleanup on Windows
    }
  });

  Future<File> artwork(String name, {int seed = 40}) {
    return writeTempFile(
      tempDir,
      name,
      encodePng(
        width: 128,
        height: 128,
        rgba: regionsRgba(
          width: 128,
          height: 128,
          regions: [
            (0, 0, 96, 128, 20 + seed, 80, 180, 255),
            (96, 0, 32, 128, 220 - seed, 160, 40, 255),
          ],
        ),
      ),
    );
  }

  ArtworkPaletteService service({ArtworkPaletteCache? cache}) {
    return ArtworkPaletteService(
      cache: cache ?? ArtworkPaletteCache(),
      extractor: const ArtworkPaletteExtractor(),
    );
  }

  test('resolves a real artwork and stamps the cache key', () async {
    final file = await artwork('a.png');
    final svc = service();
    final result = await svc.resolve(
      descriptor: ArtworkDescriptor(songIdentityKey: 's1', artPath: file.path),
    );
    expect(result, isNotNull);
    expect(result!.fromCache, isFalse);
    expect(result.palette.sourceArtworkKey, isNotNull);
    expect(result.palette.wasFallback, isFalse);
    expect(result.palette.isFromArtwork, isTrue);
    expect(result.generation, 1);
    expect(svc.isCurrent(result.generation), isTrue);
  });

  test(
    'repeated resolution is an in-memory cache hit with no re-extraction',
    () async {
      final file = await artwork('a.png');
      final svc = service();
      final descriptor = ArtworkDescriptor(
        songIdentityKey: 's1',
        artPath: file.path,
      );
      final first = await svc.resolve(descriptor: descriptor);
      final second = await svc.resolve(descriptor: descriptor);
      expect(first!.fromCache, isFalse);
      expect(second!.fromCache, isTrue);
      expect(identical(first.palette, second.palette), isTrue);
    },
  );

  test('disk cache lets a fresh service avoid re-extraction', () async {
    final file = await artwork('b${DateTime.now().microsecondsSinceEpoch}.png');
    final descriptor = ArtworkDescriptor(
      songIdentityKey: 's2',
      artPath: file.path,
    );
    ArtworkPaletteCache diskCache() =>
        ArtworkPaletteCache(directory: () async => tempDir);
    final first = await service(cache: diskCache())
        .resolve(descriptor: descriptor);
    final second = await service(cache: diskCache())
        .resolve(descriptor: descriptor);
    expect(first!.fromCache, isFalse);
    expect(second!.fromCache, isTrue);
    expect(second.palette, first.palette);
  });

  test('changing artwork identity invalidates the cached key', () async {
    final a = await artwork('a.png');
    final b = await artwork('b.png', seed: 120);
    final svc = service();
    final keyA = await ArtworkCacheKey.forFile(a);
    final keyB = await ArtworkCacheKey.forFile(b);
    expect(keyA, isNot(keyB));
    await svc.resolve(
      descriptor: ArtworkDescriptor(songIdentityKey: 's1', artPath: a.path),
    );
    final cached = await svc.resolve(
      descriptor: ArtworkDescriptor(songIdentityKey: 's2', artPath: b.path),
    );
    expect(
      cached!.fromCache,
      isFalse,
      reason: 'different artwork must re-extract',
    );
  });

  test(
    'descriptor without artwork or with a missing file returns null',
    () async {
      final svc = service();
      expect(
        await svc.resolve(
          descriptor: const ArtworkDescriptor(songIdentityKey: 'x'),
        ),
        isNull,
      );
      final gone = '${tempDir.path}${Platform.pathSeparator}gone.png';
      expect(
        await svc.resolve(
          descriptor: ArtworkDescriptor(songIdentityKey: 'x', artPath: gone),
        ),
        isNull,
      );
    },
  );

  test(
    'rapid track changes leave only the newest generation current',
    () async {
      final a = await artwork('a.png');
      final b = await artwork('b.png', seed: 200);
      final svc = service();
      final ra = svc.resolve(
        descriptor: ArtworkDescriptor(songIdentityKey: 'A', artPath: a.path),
      );
      final rb = svc.resolve(
        descriptor: ArtworkDescriptor(songIdentityKey: 'B', artPath: b.path),
      );
      final resA = await ra;
      final resB = await rb;
      expect(resA, isNotNull);
      expect(resB, isNotNull);
      expect(svc.isCurrent(resA!.generation), isFalse);
      expect(svc.isCurrent(resB!.generation), isTrue);
    },
  );

  test('cancelPending invalidates in-flight generations', () async {
    final a = await artwork('a.png');
    final svc = service();
    final ra = svc.resolve(
      descriptor: ArtworkDescriptor(songIdentityKey: 'A', artPath: a.path),
    );
    svc.cancelPending();
    final resA = await ra;
    expect(svc.isCurrent(resA!.generation), isFalse);
  });

  test(
    'full resolution on a warm cache stays under the frame budget',
    () async {
      final file = await artwork('a.png');
      final svc = service();
      final descriptor = ArtworkDescriptor(
        songIdentityKey: 's1',
        artPath: file.path,
      );
      await svc.resolve(descriptor: descriptor); // warm it up
      final sw = Stopwatch()..start();
      final hit = await svc.resolve(descriptor: descriptor);
      sw.stop();
      expect(hit!.fromCache, isTrue);
      expect(
        sw.elapsed,
        lessThan(const Duration(milliseconds: 250)),
        reason: 'warm cache resolve took ${sw.elapsedMilliseconds}ms',
      );
    },
  );
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/ingest/artwork/artwork_file_cache.dart';
import 'package:vora_tube/shared/widgets/artwork_view.dart';

// NOTE: this environment's flutter tester cannot complete (or even fail) an
// `Image.file` decode — any test that mounts a resolvable artwork file hangs
// forever. Widget tests here therefore only exercise paths that mount NO
// image (missing/null artwork -> the default fallback), and the decoded-image
// behaviour is guarded by unit tests on [ArtworkFileCache] plus a source-level
// regression guard against reintroducing `gaplessPlayback: true`, whose whole
// purpose is keeping the previous song's bitmap visible while a new provider
// loads — i.e. cross-song artwork contamination.

void main() {
  late String dir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    dir =
        '${Directory.systemTemp.path}${Platform.pathSeparator}vora_art_${DateTime.now().microsecondsSinceEpoch}';
    await Directory(dir).create(recursive: true);
    ArtworkFileCache.invalidate();
  });

  tearDown(() {
    ArtworkFileCache.invalidate();
    Directory(dir).deleteSync(recursive: true);
  });

  testWidgets('song without artwork shows the default fallback', (
    tester,
  ) async {
    await tester.pumpWidget(await _host(const ArtworkView(path: null)));
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
  });

  testWidgets('a missing artwork file falls back instead of erroring', (
    tester,
  ) async {
    await tester.pumpWidget(
      await _host(ArtworkView(path: '$dir/does_not_exist.png')),
    );
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
  });

  testWidgets('CompactArtwork falls back for null and missing artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      await _host(const CompactArtwork(path: null, size: 44)),
    );
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);

    await tester.pumpWidget(
      await _host(CompactArtwork(path: '$dir/nope.png', size: 44)),
    );
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
  });

  group('ArtworkFileCache key correctness', () {
    test('two different songs resolve to their own distinct files', () async {
      final a = await _write(dir, 'song_a');
      final b = await _write(dir, 'song_b');

      final resolvedA = ArtworkFileCache.resolve(a.path);
      final resolvedB = ArtworkFileCache.resolve(b.path);

      expect(resolvedA!.path, a.path);
      expect(resolvedB!.path, b.path);
      expect(resolvedA.path, isNot(resolvedB.path));
      // Repeated lookups stay bound to the same song — a reordered list must
      // never swap which file a path resolves to.
      expect(ArtworkFileCache.resolve(a.path)!.path, a.path);
      expect(ArtworkFileCache.resolve(b.path)!.path, b.path);
    });

    test(
      'a song with no artwork file resolves to null, never to a sibling',
      () async {
        final a = await _write(dir, 'song_a');

        expect(ArtworkFileCache.resolve(a.path), isNotNull);
        expect(
          ArtworkFileCache.resolve('$dir/song_b.png'),
          isNull,
          reason: 'A missing path must not fall back to another song\'s file.',
        );
        expect(ArtworkFileCache.resolve(null), isNull);
        expect(ArtworkFileCache.resolve(''), isNull);
      },
    );

    test('forget and invalidate keep resolution correct', () async {
      final a = await _write(dir, 'song_a');
      expect(ArtworkFileCache.resolve(a.path), isNotNull);
      ArtworkFileCache.forget(a.path);
      expect(ArtworkFileCache.resolve(a.path), isNotNull);
      ArtworkFileCache.invalidate();
      expect(ArtworkFileCache.resolve(a.path), isNotNull);
    });
  });

  test('artwork widgets keep gapless playback disabled (regression guard)', () {
    const files = [
      'lib/shared/widgets/artwork_view.dart',
      'lib/features/player/presentation/widgets/queue_sheet.dart',
      'lib/features/player/presentation/widgets/rotating_artwork.dart',
      'lib/features/player/presentation/widgets/player_artwork.dart',
      'lib/features/smart_music/presentation/widgets/mix_card.dart',
      'lib/features/smart_music/presentation/screens/smart_mix_detail_screen.dart',
    ];
    for (final f in files) {
      final source = File(f).readAsStringSync();
      expect(
        source.contains('gaplessPlayback: true'),
        isFalse,
        reason:
            '$f re-enabled gaplessPlayback. It keeps the PREVIOUS song\'s '
            'image visible while a new song\'s artwork loads — exactly the '
            'cross-song artwork contamination this fix removes.',
      );
    }
  });
}

Future<File> _write(String dir, String name) async {
  final file = File('$dir/$name.png');
  // Content is irrelevant for the existence-based cache; the tester cannot
  // decode real images anyway.
  await file.writeAsBytes(const <int>[1, 2, 3], flush: true);
  return file;
}

Future<Widget> _host(Widget child) async => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

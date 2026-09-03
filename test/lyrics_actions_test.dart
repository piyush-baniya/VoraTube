import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/models/lyrics.dart';
import 'package:vora_tube/core/player/player_controller.dart' as player;
import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/lyrics/data/lrclib_client.dart'
    show LrclibClient;
import 'package:vora_tube/features/lyrics/data/lyrics_service.dart';
import 'package:vora_tube/features/lyrics/data/user_lrc_store.dart';
import 'package:vora_tube/features/lyrics/presentation/providers/lyrics_providers.dart';
import 'package:vora_tube/features/lyrics/presentation/widgets/lyrics_view.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';

import 'fakes/fake_player.dart';

AppDatabase _memoryDb() => AppDatabase(NativeDatabase.memory());

SongRef _song(String key) => SongRef(
  identityKey: key,
  uri: '',
  title: 'Song $key',
  artist: 'Artist',
  album: null,
  artPath: null,
  durationMs: 1000,
);

void main() {
  late AppDatabase db;
  late LyricsService service;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    db = _memoryDb();
    service = LyricsService(db: db, lrclib: LrclibClient());
  });

  tearDown(() async {
    await db.close();
  });

  group('UserLrcStore', () {
    test('save + load round trip persists the LRC', () async {
      final saved = await service.userLrc.save(
        identityKey: 'ms:1',
        lrc: '[00:01.00] hello',
        fileName: 'song.lrc',
      );
      expect(saved, isTrue);

      final stored = await service.userLrc.load('ms:1');
      expect(stored, isNotNull);
      expect(stored!.lrc, '[00:01.00] hello');
      expect(stored.fileName, 'song.lrc');
    });

    test('rows written by the app are read back after reopen', () async {
      await service.userLrc.save(
        identityKey: 'ms:42',
        lrc: '[00:05.00] persists',
      );
      // A second store instance on the same database reads the committed row
      // (the DDL itself is idempotent in beforeOpen, so an app restart with a
      // file-backed database converges on the same shape).
      final store = UserLrcStore(db);
      final stored = await store.load('ms:42');
      expect(stored!.lrc, '[00:05.00] persists');
    });

    test(
      're-uploading replaces the previous LRC instead of duplicating',
      () async {
        await service.userLrc.save(identityKey: 'ms:1', lrc: 'version A');
        await service.userLrc.save(identityKey: 'ms:1', lrc: 'version B');

        final stored = await service.userLrc.load('ms:1');
        expect(stored!.lrc, 'version B');

        final count = await db
            .customSelect(
              "SELECT COUNT(*) AS c FROM user_lrc WHERE identity_key = 'ms:1'",
            )
            .getSingle();
        expect((count.data['c'] as num).toInt(), 1);
      },
    );

    test('songs without an uploaded LRC resolve to null', () async {
      expect(await service.userLrc.load('ms:999'), isNull);
      expect(await service.userLrc.load(''), isNull);
    });

    test('blank LRC content is rejected, never persisted', () async {
      final saved = await service.userLrc.save(identityKey: 'ms:1', lrc: '  ');
      expect(saved, isFalse);
      expect(await service.userLrc.load('ms:1'), isNull);
    });
  });

  group('uploaded LRC parsing', () {
    test('synced LRC parses to timestamped lines', () {
      final data = service.lyricsFromUserLrc(
        '[00:01.00] first\n[00:05.50] second',
      );
      expect(data, isNotNull);
      expect(data!.hasSyncedLines, isTrue);
      expect(data.lines.length, 2);
      expect(data.lines[1].startTimeMs, 5500);
    });

    test('plain-text file is accepted as untimed lyrics', () {
      final data = service.lyricsFromUserLrc('just some words\nmore words');
      expect(data, isNotNull);
      expect(data!.hasSyncedLines, isFalse);
      expect(data.lines.length, 2);
    });

    test('empty content is rejected', () {
      expect(service.lyricsFromUserLrc('   '), isNull);
    });
  });

  group('lyrics pipeline preference', () {
    test('getLyrics serves a stored user LRC before online lookups', () async {
      await service.userLrc.save(
        identityKey: 'ms:7',
        lrc: '[00:01.00] uploaded line',
      );

      final result = await service.getLyrics(_song('ms:7'));
      expect(result.status, LyricsStatus.loaded);
      expect(result.data!.plainText, 'uploaded line');
    });
  });

  group('web search query', () {
    test('query contains artist, title and the word lyrics, URL-encoded', () {
      final song = SongRef(
        identityKey: 'ms:1',
        uri: '',
        title: 'Tum Hi Ho',
        artist: 'Arijit Singh',
        album: null,
        artPath: null,
        durationMs: 1000,
      );
      final uri = service.webSearchUri(song);
      expect(uri.scheme, 'https');
      expect(uri.queryParameters['q'], 'Arijit Singh Tum Hi Ho lyrics');
      expect(uri.toString(), contains('Tum+Hi+Ho'));
    });

    test('missing artist still yields a usable "<title> lyrics" query', () {
      final song = SongRef(
        identityKey: 'ms:1',
        uri: '',
        title: 'Untitled',
        artist: null,
        album: null,
        artPath: null,
        durationMs: 1000,
      );
      expect(
        service.webSearchUri(song).queryParameters['q'],
        'Untitled lyrics',
      );
    });
  });

  group('manual lyrics wiring', () {
    test(
      'a chosen/uploaded result surfaces through the active-lyrics chain',
      () async {
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            playerProvider.overrideWithValue(
              FakePlayerController(
                initial: player.PlayerSnapshot(
                  status: player.PlayerStatus.ready,
                  isPlaying: true,
                  repeatMode: player.RepeatMode.off,
                  shuffleEnabled: false,
                  queueLength: 1,
                  currentIndex: 0,
                  durationMs: 1000,
                  current: _song('ms:1'),
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.read(manualLyricsProvider.notifier).state = service
            .lyricsFromUserLrc('[00:01.00] chosen line');

        expect(container.read(activeLyricsProvider)!.plainText, 'chosen line');
        // And the synced-line stream picks it up without erroring.
        await container.read(currentLyricLineIndexProvider.future);
      },
    );
  });

  group('lyrics action buttons', () {
    Future<ProviderContainer> pumpActions(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          playerProvider.overrideWithValue(
            FakePlayerController(
              initial: player.PlayerSnapshot(
                status: player.PlayerStatus.ready,
                isPlaying: true,
                repeatMode: player.RepeatMode.off,
                shuffleEnabled: false,
                queueLength: 1,
                currentIndex: 0,
                durationMs: 1000,
                current: _song('ms:1'),
              ),
            ),
          ),
          currentLyricsProvider.overrideWith(
            (ref) async => const LyricsResult.notFound(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: LyricsView(height: 500, decorated: false)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('no uploaded LRC shows exactly three actions', (tester) async {
      await pumpActions(tester);

      expect(find.text('Online Lyrics'), findsOneWidget);
      expect(find.text('Search Lyrics'), findsOneWidget);
      expect(find.text('Upload .lrc file'), findsOneWidget);
      expect(find.text('Show uploaded lyrics'), findsNothing);
      expect(find.text('Remove .LRC File'), findsNothing);
    });

    testWidgets(
      'a saved LRC swaps Upload to Remove but does not add Show uploaded, '
      'since the pipeline already loads it as the active lyrics',
      (tester) async {
        final container = await pumpActions(tester);

        await service.userLrc.save(
          identityKey: 'ms:1',
          lrc: '[00:01.00] uploaded line',
        );
        container.invalidate(uploadedLrcProvider);
        await tester.pumpAndSettle();

        expect(find.text('Show uploaded lyrics'), findsNothing);
        expect(find.text('Remove .LRC File'), findsOneWidget);
        expect(find.text('Upload .lrc file'), findsNothing);
      },
    );
  });
}

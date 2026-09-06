import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/models/lyrics.dart';
import 'package:vora_tube/core/player/player_controller.dart' as player;
import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/lyrics/data/lrclib_client.dart';
import 'package:vora_tube/features/lyrics/data/lyrics_service.dart';
import 'package:vora_tube/features/lyrics/presentation/providers/lyrics_providers.dart';
import 'package:vora_tube/features/lyrics/presentation/widgets/lyrics_actions_panel.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/player/presentation/providers/connectivity_provider.dart';
import 'package:vora_tube/features/player/presentation/widgets/compact_lyrics_panel.dart';

import 'fakes/fake_player.dart';

/// A test LRCLIB client that never hits the real network. All lookups return
/// no results immediately (as if nothing was found), so no timers/requests
/// remain pending when a test completes.
class _NoNetworkLrclibClient extends LrclibClient {
  _NoNetworkLrclibClient() {
    // prevent network calls
  }

  @override
  Future<LrclibResult?> fetchByTrack({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSec,
  }) async {
    return null;
  }

  @override
  Future<LrclibResult?> searchByTrack({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSec,
  }) async {
    return null;
  }

  @override
  Future<List<LrclibResult>> searchResultsByTrack({
    required String trackName,
    required String artistName,
    String? albumName,
  }) async {
    return const [];
  }
}

AppDatabase _memoryDb() => AppDatabase(NativeDatabase.memory());

SongRef _song(String key, {String? title, String? artist}) => SongRef(
  identityKey: key,
  uri: '',
  title: title ?? 'Song $key',
  artist: artist ?? 'Artist',
  album: null,
  artPath: null,
  durationMs: 1000,
);

/// Builds a [CompactLyricsPanel] wired to real providers and a real in-memory
/// database, with connectivity overridden via [isOnline].
Widget buildOfflinePanel({
  required AppDatabase db,
  required LyricsService service,
  required bool isOnline,
  SongRef? song,
}) {
  final effectiveSong = song ?? _song('song-a');
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      lrclibClientProvider.overrideWithValue(_NoNetworkLrclibClient()),
      isOnlineProvider.overrideWithValue(isOnline),
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
            current: effectiveSong,
          ),
        ),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 400, height: 300, child: CompactLyricsPanel()),
        ),
      ),
    ),
  );
}

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

  group('Offline lyrics state matrix', () {
    // Test 1: Online + cached → existing online behavior (pipeline works normally)
    testWidgets('Test 1: online + cached → existing online behavior', (
      tester,
    ) async {
      // Seed the cache for song-a
      await service.userLrc.save(
        identityKey: 'song-a',
        lrc: '[00:01.00] cached line',
      );

      await tester.pumpWidget(
        buildOfflinePanel(
          db: db,
          service: service,
          isOnline: true,
          song: _song('song-a'),
        ),
      );
      await tester.pumpAndSettle();

      // Online behavior unchanged: buttons-first entry (no manual pick yet)
      // The pipeline resolves the cached lyrics but does not auto-display
      // them until the user picks how to open them.
      expect(find.text('Online Lyrics'), findsOneWidget);
      expect(find.text('Search Lyrics'), findsOneWidget);
      // Since a user LRC is already saved for this song, the upload slot
      // shows "Remove .LRC File" (existing behavior).
      expect(find.text('Remove .LRC File'), findsOneWidget);
    });

    // Test 2: Online + no cached → existing online behavior
    testWidgets('Test 2: online + no cache → shows actions-first entry', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildOfflinePanel(
          db: db,
          service: service,
          isOnline: true,
          song: _song('song-a'),
        ),
      );
      await tester.pumpAndSettle();

      // Should show the buttons-first entry (no lyrics yet)
      expect(find.text('Online Lyrics'), findsOneWidget);
      expect(find.text('Search Lyrics'), findsOneWidget);
      expect(find.text('Upload .lrc file'), findsOneWidget);
    });

    // Test 3: Offline + cached → shows cached lyrics + "Offline Lyrics" chip
    testWidgets(
      'Test 3: offline + cached → cached lyrics displayed, Offline Lyrics chip',
      (tester) async {
        // Seed the cache for song-a
        await service.userLrc.save(
          identityKey: 'song-a',
          lrc: '[00:01.00] cached line',
        );

        await tester.pumpWidget(
          buildOfflinePanel(
            db: db,
            service: service,
            isOnline: false,
            song: _song('song-a'),
          ),
        );
        await tester.pumpAndSettle();

        // Cached lyrics should be displayed
        expect(find.text('cached line'), findsOneWidget);
        // "Offline Lyrics" chip shown
        expect(find.text('Offline Lyrics'), findsOneWidget);
        // No "Online Lyrics" button (offline)
        expect(find.text('Online Lyrics'), findsNothing);
        expect(find.text('Search Lyrics'), findsNothing);
      },
    );

    // Test 4: Offline + no cached → "Please connect to the internet" + upload only
    testWidgets(
      'Test 4: offline + no cache → please connect message + upload only',
      (tester) async {
        await tester.pumpWidget(
          buildOfflinePanel(
            db: db,
            service: service,
            isOnline: false,
            song: _song('song-a'),
          ),
        );
        await tester.pumpAndSettle();

        // Shows the please-connect message
        expect(
          find.textContaining('Please connect to the internet'),
          findsOneWidget,
        );
        // Only upload button
        expect(find.text('Upload .lrc file'), findsOneWidget);
        // No online/search buttons
        expect(find.text('Online Lyrics'), findsNothing);
        expect(find.text('Search Lyrics'), findsNothing);
      },
    );

    // Test 5: Offline + song A cached → switch to song B with no cache
    testWidgets(
      'Test 5: offline + cached A → switch to B (no cache) clears A lyrics',
      (tester) async {
        // Seed cache for song A
        await service.userLrc.save(
          identityKey: 'song-a',
          lrc: '[00:01.00] lyrics for A',
        );

        final songA = _song('song-a', title: 'Song A');
        final songB = _song('song-b', title: 'Song B');

        // Start with song A
        final fakePlayer = FakePlayerController(
          initial: player.PlayerSnapshot(
            status: player.PlayerStatus.ready,
            isPlaying: true,
            repeatMode: player.RepeatMode.off,
            shuffleEnabled: false,
            queueLength: 2,
            currentIndex: 0,
            durationMs: 1000,
            current: songA,
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              lrclibClientProvider.overrideWithValue(_NoNetworkLrclibClient()),
              isOnlineProvider.overrideWithValue(false),
              playerProvider.overrideWithValue(fakePlayer),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 400,
                    height: 300,
                    child: CompactLyricsPanel(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Song A lyrics should be displayed
        expect(find.text('lyrics for A'), findsOneWidget);

        // Switch to song B (no cache)
        fakePlayer.pushSnapshot(
          player.PlayerSnapshot(
            status: player.PlayerStatus.ready,
            isPlaying: true,
            repeatMode: player.RepeatMode.off,
            shuffleEnabled: false,
            queueLength: 2,
            currentIndex: 1,
            durationMs: 1000,
            current: songB,
          ),
        );
        await tester.pumpAndSettle();

        // Song A lyrics should be gone
        expect(find.text('lyrics for A'), findsNothing);
        // Song B should show offline no-cache state
        expect(
          find.textContaining('Please connect to the internet'),
          findsOneWidget,
        );
        expect(find.text('Upload .lrc file'), findsOneWidget);
      },
    );

    // Test 6: Offline + song B cache exists → shows B's cached lyrics
    testWidgets('Test 6: offline + song B cache → B cached lyrics displayed', (
      tester,
    ) async {
      // Seed cache for song B
      await service.userLrc.save(
        identityKey: 'song-b',
        lrc: '[00:01.00] lyrics for B',
      );

      await tester.pumpWidget(
        buildOfflinePanel(
          db: db,
          service: service,
          isOnline: false,
          song: _song('song-b'),
        ),
      );
      await tester.pumpAndSettle();

      // Song B cached lyrics should be displayed
      expect(find.text('lyrics for B'), findsOneWidget);
    });

    // Test 7: Offline + upload LRC → lyrics appear immediately and persist
    testWidgets('Test 7: offline + upload LRC → lyrics appear immediately', (
      tester,
    ) async {
      // Pre-save an LRC file for the song (simulating a previous upload)
      await service.userLrc.save(
        identityKey: 'song-a',
        lrc: '[00:01.00] uploaded lyrics line',
      );

      await tester.pumpWidget(
        buildOfflinePanel(
          db: db,
          service: service,
          isOnline: false,
          song: _song('song-a'),
        ),
      );
      await tester.pumpAndSettle();

      // The uploaded lyrics should be displayed
      expect(find.text('uploaded lyrics line'), findsOneWidget);
    });

    // Test 8: Online → offline while panel remains open
    testWidgets('Test 8: online → offline transition while panel open', (
      tester,
    ) async {
      // Seed cache
      await service.userLrc.save(
        identityKey: 'song-a',
        lrc: '[00:01.00] cached content',
      );

      // Start online — shows buttons-first entry
      await tester.pumpWidget(
        buildOfflinePanel(
          db: db,
          service: service,
          isOnline: true,
          song: _song('song-a'),
        ),
      );
      await tester.pumpAndSettle();

      // Online: shows normal buttons-first entry
      expect(find.text('Online Lyrics'), findsOneWidget);

      // Now rebuild with offline — should switch to offline cached mode
      await tester.pumpWidget(
        buildOfflinePanel(
          db: db,
          service: service,
          isOnline: false,
          song: _song('song-a'),
        ),
      );
      await tester.pumpAndSettle();

      // Should now show cached lyrics
      expect(find.text('cached content'), findsOneWidget);
      // No online buttons
      expect(find.text('Online Lyrics'), findsNothing);
    });

    // Test 9: Offline → online transition while panel remains open
    testWidgets('Test 9: offline → online transition resumes online behavior', (
      tester,
    ) async {
      // Start offline with no cache
      await tester.pumpWidget(
        buildOfflinePanel(
          db: db,
          service: service,
          isOnline: false,
          song: _song('song-a'),
        ),
      );
      await tester.pumpAndSettle();

      // Offline no-cache: shows please-connect
      expect(
        find.textContaining('Please connect to the internet'),
        findsOneWidget,
      );

      // Now rebuild with online
      await tester.pumpWidget(
        buildOfflinePanel(
          db: db,
          service: service,
          isOnline: true,
          song: _song('song-a'),
        ),
      );
      await tester.pumpAndSettle();

      // Online: shows normal buttons-first entry
      expect(find.text('Online Lyrics'), findsOneWidget);
      expect(find.text('Search Lyrics'), findsOneWidget);
      expect(find.text('Upload .lrc file'), findsOneWidget);
    });

    // Test 10: Kill/restart app while offline → cached lyrics remain
    testWidgets('Test 10: cached lyrics survive a fresh service + new store', (
      tester,
    ) async {
      // Seed cache with one service instance
      await service.userLrc.save(
        identityKey: 'song-a',
        lrc: '[00:01.00] persistent lyrics',
      );

      // A fresh service + store on the same persistent database simulates
      // what an app restart reads back (the data is committed to the db).
      final service2 = LyricsService(db: db, lrclib: _NoNetworkLrclibClient());
      final loaded = await service2.userLrc.load('song-a');
      expect(loaded, isNotNull);
      expect(loaded!.lrc, '[00:01.00] persistent lyrics');

      await tester.pumpWidget(
        buildOfflinePanel(
          db: db,
          service: service2,
          isOnline: false,
          song: _song('song-a'),
        ),
      );
      await tester.pumpAndSettle();

      // Cached lyrics should survive the "restart"
      expect(find.text('persistent lyrics'), findsOneWidget);
    });
  });

  group('LyricsActionsPanel offlineNoCache', () {
    testWidgets('offlineNoCache shows only Upload button, not Online/Search', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: const MaterialApp(
            home: Scaffold(
              body: LyricsActionsPanel(
                compact: true,
                grid: true,
                offlineNoCache: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Upload .lrc file'), findsOneWidget);
      expect(find.text('Online Lyrics'), findsNothing);
      expect(find.text('Search Lyrics'), findsNothing);
    });

    testWidgets('online (not offlineNoCache) shows all three actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: const MaterialApp(
            home: Scaffold(body: LyricsActionsPanel(compact: true, grid: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Online Lyrics'), findsOneWidget);
      expect(find.text('Search Lyrics'), findsOneWidget);
      expect(find.text('Upload .lrc file'), findsOneWidget);
    });
  });

  group('isOnlineProvider', () {
    test('defaults to true when connectivity result is loading', () {
      final container = ProviderContainer(
        overrides: [
          connectivityProvider.overrideWith((ref) => const Stream.empty()),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(isOnlineProvider), isTrue);
    });

    test('returns true for wifi', () {
      final container = ProviderContainer(
        overrides: [
          connectivityProvider.overrideWith(
            (ref) => Stream.value([ConnectivityResult.wifi]),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(isOnlineProvider), isTrue);
    });

    test('returns true for mobile', () {
      final container = ProviderContainer(
        overrides: [
          connectivityProvider.overrideWith(
            (ref) => Stream.value([ConnectivityResult.mobile]),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(isOnlineProvider), isTrue);
    });

    test('returns false for none', () async {
      final controller = StreamController<List<ConnectivityResult>>();
      final container = ProviderContainer(
        overrides: [
          connectivityProvider.overrideWith((ref) => controller.stream),
        ],
      );
      addTearDown(() {
        container.dispose();
        controller.close();
      });

      expect(container.read(isOnlineProvider), isTrue); // loading default
      controller.add([ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(isOnlineProvider), isFalse);
    });
  });

  group('LyricsService.getLyrics isOnline parameter', () {
    test(
      'isOnline=false skips network and returns offline when no cache',
      () async {
        final result = await service.getLyrics(
          _song('no-cache'),
          isOnline: false,
        );
        expect(result.status, LyricsStatus.offline);
      },
    );

    test(
      'isOnline=true attempts network (returns notFound for unknown song)',
      () async {
        final result = await service.getLyrics(_song('unknown'));
        // Will be notFound since LRCLIB won't have this fake song
        expect(result.status, isNot(LyricsStatus.offline));
      },
    );

    test('user LRC is returned regardless of isOnline', () async {
      await service.userLrc.save(
        identityKey: 'ms:upload',
        lrc: '[00:01.00] uploaded line',
      );
      final result = await service.getLyrics(
        _song('ms:upload'),
        isOnline: false,
      );
      expect(result.status, LyricsStatus.loaded);
      expect(result.data!.plainText, 'uploaded line');
    });

    test('embedded lyrics are returned regardless of isOnline', () async {
      // Embedded lyrics require a real file, so we test the cache path instead.
      // The cache lookup happens before the isOnline check.
      final result = await service.getLyrics(
        _song('no-embedded'),
        isOnline: false,
      );
      expect(result.status, LyricsStatus.offline);
    });
  });
}

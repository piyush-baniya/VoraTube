import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/models/lyrics.dart';
import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/features/lyrics/presentation/providers/lyrics_providers.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/player/presentation/screens/full_player_screen.dart';
import 'package:vora_tube/features/player/presentation/widgets/compact_lyrics_panel.dart';
import 'package:vora_tube/features/player/presentation/widgets/rotating_artwork.dart';

import 'fakes/fake_player.dart';

SongRef _testSong({
  int id = 1,
  String title = 'Test Song',
  String? artist = 'Test Artist',
}) {
  return SongRef(
    identityKey: 'ms:$id',
    uri: 'content://media/external/audio/media/$id',
    title: title,
    artist: artist,
    album: 'Test Album',
    durationMs: 200000,
  );
}

void main() {
  late AppDatabase db;
  late LibraryRepository repository;

  setUpAll(() {
    disableBackgroundPulseForTesting();
    disableRotatingArtworkForTesting();
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = LibraryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  ProviderScope wrap(Widget child, {List<Override> extra = const []}) {
    return ProviderScope(
      overrides: [
        ...extra,
        appDatabaseProvider.overrideWithValue(db),
        libraryRepositoryProvider.overrideWithValue(repository),
        playerProvider.overrideWithValue(
          FakePlayerController(
            initial: PlayerSnapshot(
              status: PlayerStatus.ready,
              isPlaying: false,
              repeatMode: RepeatMode.off,
              shuffleEnabled: false,
              queueLength: 2,
              currentIndex: 0,
              durationMs: 200000,
              current: _testSong(),
            ),
            queue: [
              _testSong(id: 1),
              _testSong(id: 2, title: 'Song 2'),
            ],
          ),
        ),
      ],
      child: MaterialApp(home: child),
    );
  }

  Future<void> pumpLandscape(
    WidgetTester tester, {
    required double width,
    required double height,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(const FullPlayerScreen()));
    await tester.pumpAndSettle();
  }

  group('FullPlayerScreen landscape', () {
    testWidgets(
      'player mode has no overflow on a small landscape phone (640x360)',
      (tester) async {
        await pumpLandscape(tester, width: 640, height: 360);
        expect(tester.takeException(), isNull);
        // Controls must remain accessible.
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'player mode has no overflow on a larger landscape phone (800x360)',
      (tester) async {
        await pumpLandscape(tester, width: 800, height: 360);
        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'lyrics mode has no overflow and stays scrollable on landscape',
      (tester) async {
        await pumpLandscape(tester, width: 640, height: 360);
        expect(tester.takeException(), isNull);

        // Toggle lyrics via the top-bar lyrics button. Fixed pumps: the lyrics
        // panel runs an indefinite loading animation, so settle() never ends.
        await tester.tap(find.byIcon(Icons.lyrics_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull);
        // Lyrics panel is laid out and playback controls remain accessible.
        expect(find.byIcon(Icons.lyrics_rounded), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

        // Regression: the panel must fit entirely inside the viewport. The old
        // implementation rendered it at a fixed 280 dp centered in a much
        // shorter landscape region, clipping the lyrics without any exception.
        final panelRect = tester.getRect(find.byType(CompactLyricsPanel));
        expect(panelRect.top, greaterThanOrEqualTo(0));
        expect(panelRect.bottom, lessThanOrEqualTo(360));
        expect(panelRect.height, lessThanOrEqualTo(360));
      },
    );

    testWidgets('lyrics mode has no overflow with very long song metadata', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            libraryRepositoryProvider.overrideWithValue(repository),
            playerProvider.overrideWithValue(
              FakePlayerController(
                initial: PlayerSnapshot(
                  status: PlayerStatus.ready,
                  isPlaying: false,
                  repeatMode: RepeatMode.off,
                  shuffleEnabled: false,
                  queueLength: 1,
                  currentIndex: 0,
                  durationMs: 200000,
                  current: _testSong(
                    title: 'A Really Extremely Long Song Title That Will Not Fit On One Landscape Line At All',
                    artist: 'An Equally Extremely Long Artist Name That Keeps Going And Going',
                  ),
                ),
                queue: const [],
              ),
            ),
          ],
          child: const MaterialApp(home: FullPlayerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.lyrics_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'lyrics mode with synced lyrics fits and scrolls at short landscape heights',
      (tester) async {
        final synced = LyricsResult.loaded(
          const LyricsData(
            plainText: 'First line\nSecond line\nThird line',
            lines: [
              LyricsLine(text: 'First line', startTimeMs: 0),
              LyricsLine(text: 'Second line', startTimeMs: 3000),
              LyricsLine(text: 'Third line', startTimeMs: 6000),
              LyricsLine(text: 'Fourth line', startTimeMs: 9000),
              LyricsLine(text: 'Fifth line', startTimeMs: 12000),
            ],
          ),
          LyricsSource.lrclib,
        );
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(640, 320);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          wrap(
            const FullPlayerScreen(),
            extra: [
              currentLyricsProvider.overrideWith((ref) async => synced),
              currentLyricLineIndexProvider.overrideWith(
                (ref) => Stream.value(0),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.lyrics_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull);

        // The lyrics list must be scrollable and entirely on-screen.
        final panelRect = tester.getRect(find.byType(CompactLyricsPanel));
        expect(panelRect.top, greaterThanOrEqualTo(0));
        expect(panelRect.bottom, lessThanOrEqualTo(320));
        expect(find.text('First line'), findsOneWidget);
      },
    );
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/models/lyrics.dart';
import 'package:vora_tube/core/player/player_controller.dart' as player;
import 'package:vora_tube/features/lyrics/presentation/providers/lyrics_providers.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/player/presentation/widgets/compact_lyrics_panel.dart';

import 'fakes/fake_player.dart';

/// Responsive regression tests for the lyrics card:
///
/// * portrait and tight (landscape-height) viewports render without
///   RenderFlex overflow;
/// * the active synced line stays visible and updates through the existing
///   single position subscription (no duplicate timers/listeners);
/// * changing songs resets the scroll position to the top of the new lyrics.
final mutableManualProvider = StateProvider<LyricsData?>((ref) => null);

LyricsData syncedData(String prefix, int count) {
  final lines = [
    for (var i = 0; i < count; i++)
      LyricsLine(text: '$prefix line ${i + 1}', startTimeMs: i * 3000),
  ];
  return LyricsData(
    lines: lines,
    plainText: lines.map((l) => l.text).join('\n'),
    source: LyricsSource.lrclib,
  );
}

void main() {
  late StreamController<int> activeIndex;
  late ProviderContainer container;

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        playerProvider.overrideWithValue(
          FakePlayerController(
            initial: const player.PlayerSnapshot(
              status: player.PlayerStatus.ready,
              isPlaying: true,
              repeatMode: player.RepeatMode.off,
              shuffleEnabled: false,
              queueLength: 1,
              currentIndex: 0,
              durationMs: 200000,
            ),
          ),
        ),
        currentLyricsProvider.overrideWith(
          (ref) async => const LyricsResult.notFound(),
        ),
        currentLyricLineIndexProvider.overrideWith(
          (ref) => activeIndex.stream,
        ),
        manualLyricsProvider.overrideWith(
          (ref) => ref.watch(mutableManualProvider),
        ),
      ],
    );
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    required double width,
    required double height,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: height,
                child: const CompactLyricsPanel(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  setUp(() {
    activeIndex = StreamController<int>.broadcast();
    container = makeContainer();
    addTearDown(() async {
      await activeIndex.close();
      container.dispose();
    });
  });

  group('CompactLyricsPanel responsive', () {
    testWidgets('portrait shows header, list and active line', (tester) async {
      container.read(mutableManualProvider.notifier).state =
          syncedData('P', 10);
      await pumpPanel(tester, width: 400, height: 600);
      activeIndex.add(2);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('LYRICS'), findsOneWidget);
      expect(find.text('P line 3'), findsOneWidget);
      expect(find.text('P line 1'), findsWidgets);
    });

    testWidgets('tight landscape height clamps without overflow',
        (tester) async {
      container.read(mutableManualProvider.notifier).state =
          syncedData('L', 10);
      await pumpPanel(tester, width: 400, height: 150);
      activeIndex.add(4);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Header stays reachable and the active line is on stage.
      expect(find.text('LYRICS'), findsOneWidget);
      expect(find.text('L line 5', skipOffstage: false), findsOneWidget);
    });

    testWidgets('plain lyrics render without overflow at tight height',
        (tester) async {
      container.read(mutableManualProvider.notifier).state = const LyricsData(
        lines: [
          LyricsLine(text: 'Plain one'),
          LyricsLine(text: 'Plain two'),
          LyricsLine(text: 'Plain three'),
        ],
        plainText: 'Plain one\nPlain two\nPlain three',
      );
      await pumpPanel(tester, width: 400, height: 150);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Plain one', skipOffstage: false), findsOneWidget);
    });

    testWidgets('changing songs resets the scroll to the top', (tester) async {
      container.read(mutableManualProvider.notifier).state =
          syncedData('A', 30);
      await pumpPanel(tester, width: 400, height: 300);
      activeIndex.add(20);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Auto-follow centred line 21, pushing the first line off stage.
      expect(find.text('A line 1', skipOffstage: true), findsNothing);
      expect(find.text('A line 21', skipOffstage: true), findsOneWidget);

      // Switch songs: new lyrics must start at the top, not inherit the old
      // track's scroll offset.
      container.read(mutableManualProvider.notifier).state =
          syncedData('B', 10);
      activeIndex.add(0);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('B line 1', skipOffstage: true), findsOneWidget);
      expect(find.text('A line 21', skipOffstage: true), findsNothing);
    });

    testWidgets('seeking updates the active line through the same stream',
        (tester) async {
      container.read(mutableManualProvider.notifier).state =
          syncedData('S', 10);
      await pumpPanel(tester, width: 400, height: 300);
      activeIndex.add(1);
      await tester.pump();
      expect(find.text('S line 2', skipOffstage: false), findsOneWidget);

      // A seek is just another position event on the shared stream.
      activeIndex.add(7);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('S line 8', skipOffstage: false), findsOneWidget);
    });
  });
}

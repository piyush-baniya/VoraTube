import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/models/lyrics.dart';
import 'package:vora_tube/core/player/player_controller.dart' as player;
import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/features/lyrics/presentation/providers/lyrics_providers.dart';
import 'package:vora_tube/features/lyrics/presentation/widgets/lyrics_actions_panel.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/player/presentation/widgets/compact_lyrics_panel.dart';

import 'fakes/fake_player.dart';

void main() {
  final synced = LyricsResult.loaded(
    const LyricsData(
      lines: [
        LyricsLine(text: 'Line one', startTimeMs: 0),
        LyricsLine(text: 'Line two', startTimeMs: 3000),
        LyricsLine(text: 'Line three', startTimeMs: 6000),
      ],
      plainText: 'Line one\nLine two\nLine three',
      source: LyricsSource.lrclib,
    ),
    LyricsSource.lrclib,
  );
  final manualData = LyricsData(
    lines: synced.data!.lines,
    plainText: synced.data!.plainText,
    source: LyricsSource.lrclib,
  );

  Widget buildPanel({LyricsResult? result, LyricsData? manual}) {
    return ProviderScope(
      overrides: [
        playerProvider.overrideWithValue(
          FakePlayerController(
            initial: player.PlayerSnapshot(
              status: player.PlayerStatus.ready,
              isPlaying: false,
              repeatMode: player.RepeatMode.off,
              shuffleEnabled: false,
              queueLength: 0,
              currentIndex: -1,
              durationMs: 1000,
            ),
          ),
        ),
        currentLyricsProvider.overrideWith((ref) async => result ?? synced),
        currentLyricLineIndexProvider.overrideWith((ref) => Stream.value(0)),
        if (manual != null) manualLyricsProvider.overrideWith((ref) => manual),
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
    );
  }

  testWidgets('starts expanded showing the buttons-first entry, not lyrics', (
    tester,
  ) async {
    await tester.pumpWidget(buildPanel());
    await tester.pump();

    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    // No lyrics auto-display until the user picks where they come from.
    expect(find.text('Line one'), findsNothing);
    expect(find.text('Line two'), findsNothing);
    expect(find.text('Line three'), findsNothing);
    // The three primary actions are shown as the entry.
    expect(find.text('Show online lyrics'), findsOneWidget);
    expect(find.text('Search lyrics online'), findsOneWidget);
    expect(find.text('Upload .lrc file'), findsOneWidget);
  });

  testWidgets('chosen lyrics display immediately in the panel', (tester) async {
    await tester.pumpWidget(buildPanel(manual: manualData));
    await tester.pump();

    expect(find.text('Line one'), findsOneWidget);
    expect(find.text('Line two'), findsOneWidget);
    expect(find.text('Line three'), findsOneWidget);
    // The always-on compact action row stays reachable under the list.
    expect(find.byType(LyricsActionsPanel), findsWidgets);
  });

  testWidgets('offline shows the buttons-first intro with a no-internet hint', (
    tester,
  ) async {
    await tester.pumpWidget(buildPanel(result: const LyricsResult.offline()));
    await tester.pump();

    expect(find.text('Show online lyrics'), findsOneWidget);
    expect(find.textContaining('offline'), findsOneWidget);
  });

  testWidgets(
    'not found shows a distinct empty-state hint, not the offline message',
    (tester) async {
      await tester.pumpWidget(
        buildPanel(result: const LyricsResult.notFound()),
      );
      await tester.pump();

      expect(find.textContaining('offline'), findsNothing);
      expect(find.textContaining('No lyrics for this track'), findsOneWidget);
    },
  );

  testWidgets('collapses to a preview of the current line', (tester) async {
    await tester.pumpWidget(buildPanel(manual: manualData));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
    expect(find.text('Lyrics'), findsOneWidget);
    // Preview shows the active synced line (index 0).
    expect(find.text('Line one'), findsOneWidget);
    // The rest of the list is hidden.
    expect(find.text('Line three'), findsNothing);
    // The compact action chips stay reachable while collapsed.
    expect(find.text('Show online'), findsOneWidget);
  });

  testWidgets('tapping the collapsed preview expands the panel again', (
    tester,
  ) async {
    await tester.pumpWidget(buildPanel(manual: manualData));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(find.text('Line three'), findsOneWidget);
  });
}
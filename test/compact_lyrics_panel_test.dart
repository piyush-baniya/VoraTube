import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/models/lyrics.dart';
import 'package:vora_tube/features/lyrics/presentation/providers/lyrics_providers.dart';
import 'package:vora_tube/features/player/presentation/widgets/compact_lyrics_panel.dart';

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

  Widget buildPanel({LyricsResult? result}) {
    return ProviderScope(
      overrides: [
        currentLyricsProvider.overrideWith((ref) async => result ?? synced),
        currentLyricLineIndexProvider.overrideWith((ref) => Stream.value(0)),
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

  testWidgets('starts expanded showing the full lyrics list', (tester) async {
    await tester.pumpWidget(buildPanel());
    await tester.pump();

    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(find.text('Line one'), findsOneWidget);
    expect(find.text('Line two'), findsOneWidget);
    expect(find.text('Line three'), findsOneWidget);
    expect(find.text('Lyrics'), findsNothing);
  });

  testWidgets('offline shows an explicit no-internet message', (tester) async {
    await tester.pumpWidget(buildPanel(result: const LyricsResult.offline()));
    await tester.pump();

    expect(find.text('No internet connection available.'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
  });

  testWidgets('not found shows a distinct empty state, not the offline message', (
    tester,
  ) async {
    await tester.pumpWidget(buildPanel(result: const LyricsResult.notFound()));
    await tester.pump();

    expect(find.text('No internet connection available.'), findsNothing);
    expect(find.text('No lyrics found'), findsOneWidget);
  });

  testWidgets('collapses to a preview of the current line', (tester) async {
    await tester.pumpWidget(buildPanel());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
    expect(find.text('Lyrics'), findsOneWidget);
    // Preview shows the active synced line (index 0).
    expect(find.text('Line one'), findsOneWidget);
    // The rest of the list is hidden.
    expect(find.text('Line three'), findsNothing);
  });

  testWidgets('tapping the collapsed preview expands the panel again', (
    tester,
  ) async {
    await tester.pumpWidget(buildPanel());
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

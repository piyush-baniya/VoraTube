import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/features/library/presentation/widgets/song_actions.dart';

Widget _wrap(GenreSuggestSheet sheet) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: FilledButton(
            onPressed: () async {
              final picked = await showModalBottomSheet<String>(
                context: ctx,
                isScrollControlled: true,
                builder: (_) => sheet,
              );
              result = picked;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

String? result;

Future<void> openSheet(WidgetTester tester, GenreSuggestSheet sheet) async {
  await tester.pumpWidget(_wrap(sheet));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => result = null);

  testWidgets('displays EVERY generated option — no cap, no hardcoding', (
    tester,
  ) async {
    // A 7-genre list that is NOT part of any universal genre list; whatever
    // the engine produces must appear in full.
    const generated = [
      'Bollywood',
      'Indian Pop',
      'Romantic',
      'Pop',
      'Dance',
      'Filmi',
      'Sufi Rock',
    ];
    await openSheet(
      tester,
      GenreSuggestSheet(
        currentGenre: 'Pop',
        suggestionsLoader: () async => generated,
      ),
    );
    for (final genre in generated) {
      expect(find.text(genre), findsOneWidget, reason: '$genre must be shown');
    }
    // Cancel + Apply actions exist.
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);
  });

  testWidgets('user can select one generated genre and Apply returns it', (
    tester,
  ) async {
    await openSheet(
      tester,
      GenreSuggestSheet(
        currentGenre: null,
        suggestionsLoader: () async => ['Bollywood', 'Indian Pop', 'Romantic'],
      ),
    );
    // Apply is disabled before a selection.
    final applyBefore = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Apply'),
    );
    expect(applyBefore.onPressed, isNull);

    await tester.tap(find.text('Indian Pop'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(result, 'Indian Pop');
  });

  testWidgets('Cancel does not return a genre', (tester) async {
    await openSheet(
      tester,
      GenreSuggestSheet(
        currentGenre: null,
        suggestionsLoader: () async => ['Rock', 'Jazz'],
      ),
    );
    // Select something, then cancel — result must still be null.
    await tester.tap(find.text('Rock'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('empty suggestions show the empty state, no fake genres', (
    tester,
  ) async {
    await openSheet(
      tester,
      GenreSuggestSheet(
        currentGenre: null,
        suggestionsLoader: () async => const [],
      ),
    );
    expect(
      find.text('No genre suggestions available for this song.'),
      findsOneWidget,
    );
    // No radio options invented.
    expect(find.byType(RadioListTile<String>), findsNothing);
    // Sheet can still be closed.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}

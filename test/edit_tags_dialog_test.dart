import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/features/library/presentation/widgets/song_actions.dart';

/// Regression tests for the Edit Tags lifecycle assertion crash.
///
/// The old implementation disposed the dialog's TextEditingControllers
/// synchronously as soon as showDialog's future resolved — i.e. while the
/// dialog's exit transition was still animating its TextFields. The fields
/// then used their controllers after disposal, tripping Flutter's framework
/// lifecycle assertion. The controllers are now owned by the dialog State and
/// disposed only when the route is fully unmounted.
void main() {
  testWidgets(
    'edit genre and save: returns values and unmounts without assertions',
    (tester) async {
      EditTagsResult? popped;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (homeContext) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    popped = await showDialog<EditTagsResult>(
                      context: homeContext,
                      builder: (_) => const EditTagsDialog(
                        initialTitle: 'Old Title',
                        initialArtist: 'Old Artist',
                        initialAlbum: 'Old Album',
                        initialGenre: 'Rock',
                        initialYear: '1999',
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Edit tags'), findsOneWidget);

      // Pre-populated values are shown.
      expect(find.widgetWithText(TextField, 'Genre'), findsOneWidget);

      // Change the genre.
      await tester.enterText(find.widgetWithText(TextField, 'Genre'), 'Jazz');
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'New Title',
      );

      // Save.
      await tester.tap(find.text('Save'));
      // Let the dialog's exit transition run to completion — this is exactly
      // the window in which the old code disposed the controllers and crashed.
      await tester.pumpAndSettle();

      expect(popped, isNotNull);
      expect(popped!.confirmed, isTrue);
      expect(popped!.title, 'New Title');
      expect(popped!.genre, 'Jazz');
      expect(popped!.year, 1999);
      // The dialog route is fully gone.
      expect(find.text('Edit tags'), findsNothing);
      // No framework lifecycle assertion was recorded.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancel returns confirmed=false and no fields leak', (
    tester,
  ) async {
    EditTagsResult? popped;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (homeContext) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  popped = await showDialog<EditTagsResult>(
                    context: homeContext,
                    builder: (_) => const EditTagsDialog(
                      initialTitle: 'T',
                      initialArtist: 'A',
                      initialAlbum: 'Al',
                      initialGenre: 'G',
                      initialYear: '2001',
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.confirmed, isFalse);
    expect(find.text('Edit tags'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

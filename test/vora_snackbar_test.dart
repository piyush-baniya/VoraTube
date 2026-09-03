import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/app/widgets/vora_snackbar.dart';
import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';

import 'fakes/fake_player.dart';

AppDatabase _memoryDb() => AppDatabase(NativeDatabase.memory());

void main() {
  late AppDatabase db;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    db = _memoryDb();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpApp(
    WidgetTester tester,
    void Function(BuildContext) onTap,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          playerProvider.overrideWithValue(FakePlayerController()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => onTap(context),
                  child: const Text('Show'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('VoraSnackbar', () {
    testWidgets('success variant renders title and message', (tester) async {
      await pumpApp(tester, (context) {
        VoraSnackbar.success(context, 'Song Name', title: 'Added to favorites');
      });

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Added to favorites'), findsOneWidget);
      expect(find.text('Song Name'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('error variant renders with retry action', (tester) async {
      var retried = false;
      await pumpApp(tester, (context) {
        VoraSnackbar.error(
          context,
          "Couldn't load lyrics right now.",
          title: "Couldn't load lyrics",
          retryLabel: 'RETRY',
          onRetry: () => retried = true,
        );
      });

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text("Couldn't load lyrics"), findsOneWidget);
      expect(find.text("Couldn't load lyrics right now."), findsOneWidget);
      expect(find.text('RETRY'), findsOneWidget);

      final textButton = tester.widget<TextButton>(find.byType(TextButton));
      textButton.onPressed?.call();
      await tester.pumpAndSettle();
      expect(retried, isTrue);
    });

    testWidgets('progress variant renders progress indicator', (tester) async {
      await pumpApp(tester, (context) {
        VoraSnackbar.showProgress(
          context,
          'Looking for music on your device…',
          title: 'Scanning music',
          progress: 0.5,
        );
      });

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Scanning music'), findsOneWidget);
      expect(find.text('Looking for music on your device…'), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('warning variant renders correctly', (tester) async {
      await pumpApp(tester, (context) {
        VoraSnackbar.warning(
          context,
          'This song is already in the playlist.',
          title: 'Already in playlist',
        );
      });

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Already in playlist'), findsOneWidget);
      expect(
        find.text('This song is already in the playlist.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
    });

    testWidgets('info variant renders correctly', (tester) async {
      await pumpApp(tester, (context) {
        VoraSnackbar.info(
          context,
          'Music access is required to scan your library.',
          title: 'Permission required',
        );
      });

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Permission required'), findsOneWidget);
      expect(
        find.text('Music access is required to scan your library.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.info_rounded), findsOneWidget);
    });

    testWidgets('snackbar hides previous before showing new', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            playerProvider.overrideWithValue(FakePlayerController()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    ElevatedButton(
                      onPressed: () =>
                          VoraSnackbar.info(context, 'First message'),
                      child: const Text('First'),
                    ),
                    ElevatedButton(
                      onPressed: () =>
                          VoraSnackbar.info(context, 'Second message'),
                      child: const Text('Second'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('First'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('First message'), findsOneWidget);

      await tester.tap(find.text('Second'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Second message'), findsOneWidget);
      expect(find.text('First message'), findsNothing);
    });

    testWidgets('snackbar dismisses after duration', (tester) async {
      await pumpApp(tester, (context) {
        VoraSnackbar.show(
          context,
          variant: VoraSnackbarVariant.info,
          message: 'Temporary message',
          duration: const Duration(milliseconds: 500),
        );
      });

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Temporary message'), findsOneWidget);

      // Let the entry animation complete (250ms) so the auto-dismiss timer
      // gets scheduled inside ScaffoldMessenger.build(). The timer starts
      // from this point, not from when the snackbar was first shown.
      await tester.pump(const Duration(milliseconds: 300));

      // Advance past the 500ms auto-dismiss timer and the 250ms exit
      // animation so the snackbar is removed from the overlay.
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();

      expect(find.text('Temporary message'), findsNothing);
    });
  });
}

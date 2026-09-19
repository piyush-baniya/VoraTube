import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/player/presentation/screens/equalizer_screen.dart';
import 'package:vora_tube/features/player/presentation/screens/full_player_screen.dart';

import 'fakes/fake_player.dart';

SongRef _song() => const SongRef(
  identityKey: 'ms:1',
  uri: 'content://media/external/audio/media/1',
  title: 'Test Song',
  artist: 'Test Artist',
  album: 'Test Album',
  durationMs: 200000,
);

void main() {
  late AppDatabase db;
  late LibraryRepository repository;

  setUpAll(() {
    disableBackgroundPulseForTesting();
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = LibraryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Widget wrap() => ProviderScope(
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
            current: _song(),
          ),
          queue: [_song()],
        ),
      ),
    ],
    child: const MaterialApp(home: EqualizerScreen()),
  );

  testWidgets('graphic mode is the default view', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Graphic'), findsOneWidget);
    expect(find.text('Parametric'), findsOneWidget);
    expect(find.text('Bands'), findsNothing);
  });

  testWidgets('switching to Parametric reveals the band editor', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Parametric'));
    await tester.pumpAndSettle();

    expect(find.text('Bands'), findsOneWidget);
    expect(find.text('Save bands'), findsOneWidget);
    expect(find.textContaining('No bands yet'), findsOneWidget);
  });

  testWidgets('tapping Add inserts a peaking band', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Parametric'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No bands yet'), findsNothing);
    expect(find.textContaining('Peaking'), findsWidgets);
  });

  testWidgets('switching back to Graphic hides the parametric editor', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Parametric'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Graphic'));
    await tester.pumpAndSettle();

    expect(find.text('Bands'), findsNothing);
    expect(find.text('Save bands'), findsNothing);
  });
}

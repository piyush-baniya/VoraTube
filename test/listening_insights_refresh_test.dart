import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/features/collections/presentation/widgets/listening_insights.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/library/presentation/providers/library_view_providers.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';

import 'fakes/fake_player.dart';

IngestTrack _track(int id) {
  return IngestTrack(
    source: IngestSource.mediastore,
    mediaStoreId: id,
    albumMediaStoreId: 10 + id,
    artistMediaStoreId: 20 + id,
    albumKey: 'ms:${10 + id}',
    artistKey: 'ms:${20 + id}',
    contentUri: 'content://media/external/audio/media/$id',
    path: '/storage/emulated/0/Music/song_$id.mp3',
    title: 'Song $id',
    artist: 'Artist $id',
    album: 'Album X',
    durationMs: 180000,
    dateModifiedSec: 100,
    year: 2020,
    trackNumber: 1,
    sizeBytes: 5000 + id,
    dateAddedSec: 90,
  );
}

void main() {
  late AppDatabase db;
  late LibraryRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = LibraryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  ProviderScope wrap(Widget child) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        libraryRepositoryProvider.overrideWithValue(repo),
        playerProvider.overrideWithValue(FakePlayerController()),
      ],
      child: MaterialApp(home: child),
    );
  }

  group('"Your Listening" strip — stale-while-refresh', () {
    testWidgets(
      'a stats refresh tick never blanks the section (the playback '
      'footer/5s-flush flicker fix)',
      (tester) async {
        final y = DateTime.now().year;
        await repo.syncTracks([_track(1), _track(2)]);
        await repo.recordPlayback([1], DateTime(y, 6, 1, 10));
        await repo.addPlaybackListenedMs(
          songRowId: 1,
          listenedMs: 120000,
          at: DateTime(y, 6, 1, 10, 30),
        );

        await tester.pumpWidget(
          wrap(const Scaffold(body: ListeningInsightsStrip())),
        );
        await tester.pumpAndSettle();

        // Header and cards are on screen.
        expect(find.text('YOUR LISTENING'), findsOneWidget);
        expect(find.text('Songs played'), findsOneWidget);
        expect(find.text('Duration listened'), findsOneWidget);
        expect(find.text('2m'), findsOneWidget);

        final element = tester.element(find.text('YOUR LISTENING'));
        final container = ProviderScope.containerOf(element);

        // Simulate the playback flush path: a listening-time write lands, then
        // the stats tick bumps. The frame immediately after the tick is the one
        // that used to blank the section — it must still render the header.
        await repo.addPlaybackListenedMs(
          songRowId: 1,
          listenedMs: 60000,
          at: DateTime.now(),
        );
        container.read(statsRefreshTickProvider.notifier).state++;
        await tester.pump();

        expect(find.text('YOUR LISTENING'), findsOneWidget);
        expect(find.text('Songs played'), findsOneWidget);
        expect(find.text('Duration listened'), findsOneWidget);

        // The refreshed numbers land once the recompute settles.
        await tester.pumpAndSettle();
        expect(find.text('3m'), findsOneWidget);
        expect(find.text('YOUR LISTENING'), findsOneWidget);
      },
    );

    testWidgets('first load with an empty library still hides the section', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const Scaffold(body: ListeningInsightsStrip())),
      );
      await tester.pumpAndSettle();

      expect(find.text('YOUR LISTENING'), findsNothing);
    });
  });
}
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/features/ads/premium_providers.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/library/presentation/screens/library_screen.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';

import 'fakes/fake_player.dart';

/// Records every shuffle toggle and queued playback so tests can assert what
/// the Library's floating Play/Shuffle buttons actually handed to the player.
class _RecordingPlayer extends FakePlayerController {
  final List<bool> shuffleCalls = [];
  final List<List<SongRef>> playedQueues = [];

  @override
  Future<void> setShuffle(bool enabled) async {
    shuffleCalls.add(enabled);
  }

  @override
  Future<void> playQueue(List<SongRef> songs, {int startIndex = 0}) async {
    playedQueues.add(List.of(songs));
  }
}

IngestTrack _msTrack(int id) {
  return IngestTrack(
    source: IngestSource.mediastore,
    mediaStoreId: id,
    albumMediaStoreId: 11,
    artistMediaStoreId: 21,
    albumKey: 'ms:11',
    artistKey: 'ms:21',
    contentUri: 'content://media/external/audio/media/$id',
    path: '/storage/emulated/0/Music/song_$id.mp3',
    title: 'Song $id',
    artist: 'Artist A',
    album: 'Album X',
    durationMs: 180000 + id,
    dateModifiedSec: 100,
    year: 2020,
    trackNumber: 1,
    sizeBytes: 5000 + id,
    dateAddedSec: 90,
  );
}

void main() {
  group('Library Songs Play/Shuffle buttons', () {
    late AppDatabase db;
    late LibraryRepository repository;
    late _RecordingPlayer player;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repository = LibraryRepository(db);
      player = _RecordingPlayer();
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> seed(int count) async {
      await repository.syncTracks([for (var i = 1; i <= count; i++) _msTrack(i)]);
    }

    Widget buildApp() {
      return ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          libraryRepositoryProvider.overrideWithValue(repository),
          playerProvider.overrideWithValue(player),
          // Premium active so the banner widgets collapse without touching the
          // ad SDK (they read isPremiumProvider, not premiumProvider directly).
          isPremiumProvider.overrideWithValue(true),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      );
    }

    testWidgets(
      'Shuffle hands the player a fully randomised queue and enables '
      'shuffle mode (not Play with the first song on top)',
      (tester) async {
        await seed(10);
        await tester.pumpWidget(buildApp());
        await tester.pumpAndSettle();

        // The prominent buttons above the Mini Player replace the old tiny
        // toolbar icons and are the only Play/Shuffle controls on this page.
        expect(find.text('Shuffle'), findsOneWidget);
        expect(find.text('Play'), findsOneWidget);

        await tester.tap(find.text('Shuffle'));
        await tester.pumpAndSettle();

        expect(player.shuffleCalls, [true]);
        expect(player.playedQueues, hasLength(1));
        final shuffled = player.playedQueues.single;
        expect(shuffled, hasLength(10));
        // Every library song made it into the queue...
        expect(shuffled.map((s) => s.identityKey).toSet(), hasLength(10));

        // Plain play resets shuffle off and queues the exact, unrandomised
        // list, which also supplies the deterministic "ordered" reference.
        await tester.tap(find.text('Play'));
        await tester.pumpAndSettle();

        expect(player.shuffleCalls, [true, false]);
        expect(player.playedQueues, hasLength(2));
        final ordered = player.playedQueues[1];
        expect(ordered.map((s) => s.identityKey).toSet(),
            shuffled.map((s) => s.identityKey).toSet());
        // Randomising 10 unique songs produces the identical order with
        // probability 1/10!, so a mismatch is the expected, intended outcome.
        expect(shuffled, isNot(equals(ordered)));
      },
    );

    testWidgets('the floating buttons only appear in the Songs section',
        (tester) async {
      await seed(2);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Shuffle'), findsOneWidget);

      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();

      expect(find.text('Play'), findsNothing);
      expect(find.text('Shuffle'), findsNothing);
    });
  });
}
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/library/presentation/providers/library_view_providers.dart';
import 'package:vora_tube/features/library/presentation/widgets/song_tile.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/search/presentation/screens/search_screen.dart';

import 'fakes/fake_player.dart';

IngestTrack _msTrack(int id) {
  return IngestTrack(
    source: IngestSource.mediastore,
    mediaStoreId: id,
    albumMediaStoreId: 100 + id,
    artistMediaStoreId: 200 + id,
    albumKey: 'ms:${100 + id}',
    artistKey: 'ms:${200 + id}',
    contentUri: 'content://media/external/audio/media/$id',
    path: '/storage/emulated/0/Music/song_$id.mp3',
    title: 'Song $id',
    artist: 'Artist ${id % 3}',
    album: 'Album ${id % 2}',
    durationMs: 180000 + id,
    dateModifiedSec: 100 + id,
    year: 2020,
    trackNumber: id,
    sizeBytes: 5000 + id,
    dateAddedSec: 90 + id,
  );
}

void main() {
  group(
    'Batch 10 — Task 1: Home curated preview decoupled from Library filter',
    () {
      test('All Songs preview stays a bounded all-songs peek and ignores the '
          'Library favorites filter', () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final repo = LibraryRepository(db);
        // Seed more than the preview cap to prove the bound holds and that the
        // library's favorite/sort toolbar state cannot silence the dashboard.
        await repo.syncTracks([for (var i = 1; i <= 14; i++) _msTrack(i)]);

        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            libraryRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        // Simulate the user having toggled the Library browser onto
        // "Favorites only" — none of the seeded songs are favorites.
        container.read(favoritesOnlyProvider.notifier).state = true;

        final preview = await container.read(homeSongsProvider.future);

        // Bound respected and the favorites filter did not empty the preview.
        expect(preview.length, 10);
        expect(preview, isNotEmpty);
      });
    },
  );

  group('Batch 10 — Task 2: consistent three-dot song menu', () {
    testWidgets('search results render the shared SongTile with an overflow '
        'menu', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LibraryRepository(db);
      await repo.syncTracks([_msTrack(1), _msTrack(2), _msTrack(3)]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            libraryRepositoryProvider.overrideWithValue(repo),
            playerProvider.overrideWithValue(FakePlayerController()),
          ],
          child: const MaterialApp(home: Scaffold(body: SearchScreen())),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Song');
      // Advance past SearchScreen's 250 ms debounce, then let the async DB
      // query complete.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Song results now reuse the shared SongTile (which carries the
      // three-dot song menu, favorite button and playing indicator) instead of
      // a bespoke row with no menu. The title is rendered as a highlight
      // RichText, so match it by its concatenated span text.
      expect(find.byType(SongTile), findsNWidgets(3));
      expect(find.byIcon(Icons.more_vert_rounded), findsNWidgets(3));
      final renderedTitles = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((r) => (r.text as TextSpan).toPlainText())
          .where((t) => t.contains('Song'))
          .toList();
      expect(renderedTitles, containsAll(['Song 1', 'Song 2', 'Song 3']));
    });
  });
}

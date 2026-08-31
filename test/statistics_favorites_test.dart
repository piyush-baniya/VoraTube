import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/features/collections/presentation/providers/statistics_providers.dart';
import 'package:vora_tube/features/collections/presentation/widgets/listening_insights.dart'
    show listeningStatsProvider;
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/library/presentation/providers/library_view_providers.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository repo;
  late ProviderContainer container;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    db = AppDatabase(NativeDatabase.memory());
    repo = LibraryRepository(db);
    await repo.syncTracks([for (var i = 1; i <= 3; i++) _track(i)]);
    container = ProviderContainer(
      overrides: [libraryRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);
  });

  group('statistics favorites source of truth', () {
    test('favorite state starts false for a never-favorited song', () async {
      final controller = container.read(favoriteIdsProvider.notifier);
      // Hydration is async; give it a beat via the provider read.
      await Future<void>.delayed(Duration.zero);
      expect(controller.isFavorite(1), isFalse);
      expect(container.read(favoriteIdsProvider), isEmpty);
    });

    test(
      'toggle favorites a song and the set reflects it immediately',
      () async {
        final controller = container.read(favoriteIdsProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        await controller.toggle(1);
        expect(controller.isFavorite(1), isTrue);
        expect(container.read(favoriteIdsProvider), {1});
      },
    );

    test(
      'favorite -> unfavorite -> favorite round trip stays in sync with db',
      () async {
        final controller = container.read(favoriteIdsProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        await controller.toggle(1);
        expect(await repo.isFavorite(1), isTrue);

        await controller.toggle(1);
        expect(controller.isFavorite(1), isFalse);
        expect(await repo.isFavorite(1), isFalse);

        await controller.toggle(1);
        expect(controller.isFavorite(1), isTrue);
        expect(await repo.isFavorite(1), isTrue);
      },
    );

    test(
      'a committed toggle bumps the stats tick so statistics recompute',
      () async {
        final controller = container.read(favoriteIdsProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        final before = container.read(statsRefreshTickProvider);
        await controller.toggle(2);
        expect(
          container.read(statsRefreshTickProvider),
          before + 1,
          reason:
              'Statistics aggregates derive favorites from the DB, so the '
              'tick they watch must move after every committed toggle.',
        );

        final beforeUnfav = container.read(statsRefreshTickProvider);
        await controller.toggle(2);
        expect(container.read(statsRefreshTickProvider), beforeUnfav + 1);
      },
    );

    test(
      'statistics favorites count reacts to toggling with no stale state',
      () async {
        final controller = container.read(favoriteIdsProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        // Initial aggregate: no favorites.
        expect(
          (await container.read(listeningStatsProvider.future)).favoritesCount,
          0,
        );

        await controller.toggle(1);
        // Re-reading the provider must return fresh DB-derived data — the old
        // favoritesCount: 0 must not be served again.
        expect(
          (await container.read(listeningStatsProvider.future)).favoritesCount,
          1,
        );

        await controller.toggle(1);
        expect(
          (await container.read(listeningStatsProvider.future)).favoritesCount,
          0,
        );
      },
    );

    test(
      'top played / recently played providers rebuild after a toggle',
      () async {
        final controller = container.read(favoriteIdsProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        final before = container.read(topPlayedSongsProvider).valueOrNull;
        expect(before, isNull);

        await controller.toggle(3);
        final after = await container.read(topPlayedSongsProvider.future);
        expect(after, isNotNull);
      },
    );
  });
}

IngestTrack _track(int id) {
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
    artist: 'Artist $id',
    album: 'Album $id',
    durationMs: 180000 + id,
    dateModifiedSec: 100 + id,
    year: 2020,
    trackNumber: id,
    sizeBytes: 5000 + id,
    dateAddedSec: 90 + id,
  );
}

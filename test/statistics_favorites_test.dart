import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
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
      'a committed toggle bumps the favorites tick, not the stats tick',
      () async {
        final controller = container.read(favoriteIdsProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        final statsBefore = container.read(statsRefreshTickProvider);
        final favBefore = container.read(favoritesRefreshTickProvider);
        await controller.toggle(2);
        expect(
          container.read(favoritesRefreshTickProvider),
          favBefore + 1,
          reason:
              'Favorites-derived aggregates (the Collection Favorites '
              'count/list) watch this dedicated tick, so it must move after '
              'every committed toggle.',
        );
        expect(
          container.read(statsRefreshTickProvider),
          statsBefore,
          reason:
              'Favorites do not change listening time or play counts. The '
              'stats tick must NOT move, or the Home "Your Listening" strip '
              'and Statistics listening sections would refetch and repaint on '
              'a heart tap.',
        );

        final statsBeforeUnfav = container.read(statsRefreshTickProvider);
        await controller.toggle(2);
        expect(container.read(favoritesRefreshTickProvider), favBefore + 2);
        expect(container.read(statsRefreshTickProvider), statsBeforeUnfav);
      },
    );

    test('live favorites count comes from the in-memory set', () async {
      final controller = container.read(favoriteIdsProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      // Initial aggregate: no favorites.
      expect(container.read(favoriteIdsProvider).length, 0);

      await controller.toggle(1);
      expect(container.read(favoriteIdsProvider).length, 1);

      await controller.toggle(2);
      expect(container.read(favoriteIdsProvider).length, 2);

      await controller.toggle(1);
      expect(container.read(favoriteIdsProvider).length, 1);
    });
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

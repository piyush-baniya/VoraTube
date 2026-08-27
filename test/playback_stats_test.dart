import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';

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
  late AppDatabase db;
  late LibraryRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = LibraryRepository(db);

    await repo.syncTracks([
      _msTrack(1),
      _msTrack(2),
      _msTrack(3),
      _msTrack(4),
      _msTrack(5),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  // -------------------------------------------------------------------------
  // recordPlayback
  // -------------------------------------------------------------------------

  group('recordPlayback', () {
    test('creates stats rows and increments play count', () async {
      await repo.recordPlayback([1, 2], DateTime(2025, 6, 15, 12, 0));

      final stats = await (db.select(
        db.songStats,
      )..where((t) => t.songId.isIn([1, 2]))).get();
      expect(stats, hasLength(2));

      final s1 = stats.firstWhere((s) => s.songId == 1);
      expect(s1.playCount, 1);
      expect(s1.lastPlayedAt, isNotNull);

      // Second call should increment.
      await repo.recordPlayback([1], DateTime(2025, 6, 15, 13, 0));
      final updated = await (db.select(
        db.songStats,
      )..where((t) => t.songId.equals(1))).getSingle();
      expect(updated.playCount, 2);
    });

    test('no-ops on empty list', () async {
      await repo.recordPlayback([], DateTime.now());
      final stats = await db.select(db.songStats).get();
      expect(stats, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // countCollection
  // -------------------------------------------------------------------------

  group('countCollection', () {
    test('recentlyAdded counts all songs', () async {
      final count = await repo.countCollection(CollectionKind.recentlyAdded);
      expect(count, 5);
    });

    test('favorites counts only favorite songs', () async {
      // Mark song 1 and 3 as favorites.
      await repo.recordPlayback([1, 3], DateTime.now());
      await db.customStatement(
        'UPDATE song_stats SET is_favorite = 1 WHERE song_id IN (1, 3)',
      );

      final count = await repo.countCollection(CollectionKind.favorites);
      expect(count, 2);
    });

    test('mostPlayed counts songs with playCount > 0', () async {
      await repo.recordPlayback([1, 2, 3], DateTime.now());

      final count = await repo.countCollection(CollectionKind.mostPlayed);
      expect(count, 3);
    });

    test('recentlyPlayed counts songs with non-null lastPlayedAt', () async {
      await repo.recordPlayback([1, 5], DateTime.now());

      final count = await repo.countCollection(CollectionKind.recentlyPlayed);
      expect(count, 2);
    });
  });

  // -------------------------------------------------------------------------
  // collectionSongs
  // -------------------------------------------------------------------------

  group('collectionSongs', () {
    test('recentlyAdded returns songs ordered by dateAdded desc', () async {
      final songs = await repo.collectionSongs(CollectionKind.recentlyAdded);
      expect(songs, hasLength(5));
      // Highest id has highest dateAddedSec in our test data.
      expect(songs.first.song.id, 5);
    });

    test('favorites returns only favorite songs', () async {
      await repo.recordPlayback([2, 4], DateTime.now());
      await db.customStatement(
        'UPDATE song_stats SET is_favorite = 1 WHERE song_id IN (2, 4)',
      );

      final songs = await repo.collectionSongs(CollectionKind.favorites);
      expect(songs, hasLength(2));
      expect(songs.map((s) => s.song.id).toList(), containsAll([2, 4]));
    });

    test('mostPlayed returns songs ordered by playCount desc', () async {
      await repo.recordPlayback([1], DateTime(2025, 1, 1));
      await repo.recordPlayback([1], DateTime(2025, 1, 2));
      await repo.recordPlayback([3], DateTime(2025, 1, 1));

      final songs = await repo.collectionSongs(CollectionKind.mostPlayed);
      expect(songs, hasLength(2));
      expect(songs[0].song.id, 1);
      expect(songs[1].song.id, 3);
    });

    test('recentlyPlayed returns songs ordered by lastPlayedAt desc', () async {
      await repo.recordPlayback([3], DateTime(2025, 3, 1));
      await repo.recordPlayback([1], DateTime(2025, 3, 2));

      final songs = await repo.collectionSongs(CollectionKind.recentlyPlayed);
      expect(songs, hasLength(2));
      expect(songs[0].song.id, 1);
      expect(songs[1].song.id, 3);
    });

    test('respects limit', () async {
      await repo.recordPlayback([1, 2, 3, 4, 5], DateTime.now());

      final songs = await repo.collectionSongs(
        CollectionKind.mostPlayed,
        limit: 2,
      );
      expect(songs, hasLength(2));
    });
  });

  // -------------------------------------------------------------------------
  // rowIdsByIdentityKeys
  // -------------------------------------------------------------------------

  group('rowIdsByIdentityKeys', () {
    test('maps identity keys to row ids', () async {
      final map = await repo.rowIdsByIdentityKeys({'ms:1', 'ms:5'});
      expect(map['ms:1'], isNotNull);
      expect(map['ms:5'], isNotNull);
      expect(map.length, 2);
    });

    test('returns empty map for empty keys', () async {
      final map = await repo.rowIdsByIdentityKeys({});
      expect(map, isEmpty);
    });

    test('ignores unknown keys', () async {
      final map = await repo.rowIdsByIdentityKeys({'ms:999', 'ms:1'});
      expect(map.length, 1);
      expect(map.containsKey('ms:999'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // favoritesSongRowIds
  // -------------------------------------------------------------------------

  group('favoritesSongRowIds', () {
    test('returns only favorite song ids', () async {
      await repo.recordPlayback([1, 2, 3], DateTime.now());
      await db.customStatement(
        'UPDATE song_stats SET is_favorite = 1 WHERE song_id IN (1, 3)',
      );

      final ids = await repo.favoritesSongRowIds();
      expect(ids, containsAll([1, 3]));
      expect(ids, isNot(contains(2)));
    });

    test('returns empty set when no favorites', () async {
      final ids = await repo.favoritesSongRowIds();
      expect(ids, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // PlaybackStatsBuffer
  // -------------------------------------------------------------------------

  group('PlaybackStatsBuffer', () {
    test('flushThreshold triggers immediate flush', () async {
      final buffer = PlaybackStatsBuffer(
        repo,
        flushThreshold: 3,
        flushInterval: const Duration(hours: 1),
      );

      buffer.add('ms:1');
      buffer.add('ms:2');
      expect(buffer.pendingCount, 2);

      buffer.add('ms:3'); // triggers flush at threshold
      await Future<void>.delayed(Duration.zero); // allow microtask

      expect(buffer.pendingCount, 0);

      final stats = await db.select(db.songStats).get();
      expect(stats, hasLength(3));
    });

    test('deduplicates same identity key', () {
      final buffer = PlaybackStatsBuffer(
        repo,
        flushThreshold: 100,
        flushInterval: const Duration(hours: 1),
      );

      buffer.add('ms:1');
      buffer.add('ms:1');
      buffer.add('ms:1');

      expect(buffer.pendingCount, 1);
    });

    test('flush clears pending and records', () async {
      final buffer = PlaybackStatsBuffer(
        repo,
        flushThreshold: 100,
        flushInterval: const Duration(hours: 1),
      );

      buffer.add('ms:1');
      buffer.add('ms:5');
      expect(buffer.pendingCount, 2);

      await buffer.flush();
      expect(buffer.pendingCount, 0);

      final stats = await (db.select(
        db.songStats,
      )..where((t) => t.songId.isIn([1, 5]))).get();
      expect(stats, hasLength(2));
    });

    test('flush is no-op on empty buffer', () async {
      final buffer = PlaybackStatsBuffer(
        repo,
        flushThreshold: 10,
        flushInterval: const Duration(hours: 1),
      );

      await buffer.flush(); // should not throw
      expect(buffer.pendingCount, 0);
    });
  });

  // -------------------------------------------------------------------------
  // listeningStats
  // -------------------------------------------------------------------------

  group('listeningStats', () {
    test('reports most played song and aggregate plays', () async {
      // Song 1 is played the most.
      await repo.recordPlayback([1], DateTime(2025, 1, 1));
      await repo.recordPlayback([1], DateTime(2025, 1, 2));
      await repo.recordPlayback([3], DateTime(2025, 1, 1));

      final stats = await repo.listeningStats();

      expect(stats.totalSongs, 5);
      expect(stats.totalPlays, 3);
      expect(stats.hasMostPlayedSong, isTrue);
      expect(stats.mostPlayedSongTitle, 'Song 1');
      expect(stats.mostPlayedSongArtist, 'Artist 1');
      expect(stats.mostPlayedSongCount, 2);
    });

    test('no most played song when nothing has been played', () async {
      final stats = await repo.listeningStats();

      expect(stats.hasMostPlayedSong, isFalse);
      expect(stats.mostPlayedSongCount, 0);
      expect(stats.totalPlays, 0);
      expect(stats.formattedListeningTime, '0m');
    });
  });
}

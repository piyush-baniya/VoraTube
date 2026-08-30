import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';

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
    await repo.syncTracks([for (var i = 1; i <= 5; i++) _msTrack(i)]);
  });

  tearDown(() async {
    await db.close();
  });

  group('listeningBreakdown aggregation', () {
    test('returns empty totals before any playback', () async {
      final b = await repo.listeningBreakdown(now: DateTime(2025, 6, 18, 12));

      expect(b.totalListenedMs, 0);
      expect(b.totalPlays, 0);
      expect(b.totalUniqueSongs, 0);
      expect(b.peakDay, isNull);
      expect(b.week.plays, 0);
      expect(b.week.listenedMs, 0);
      expect(b.year.plays, 0);
    });

    test(
      'real listening time accumulates; ignored time never counts',
      () async {
        await repo.recordPlayback([1], DateTime(2025, 6, 18, 14, 0));
        await repo.addPlaybackListenedMs(
          songRowId: 1,
          listenedMs: 120000,
          at: DateTime(2025, 6, 18, 14, 5),
        );

        final b = await repo.listeningBreakdown(now: DateTime(2025, 6, 18, 15));
        expect(b.totalListenedMs, 120000);
        expect(b.totalPlays, 1);
        expect(b.totalUniqueSongs, 1);
      },
    );

    test('non-positive listenedMs is a no-op', () async {
      await repo.recordPlayback([1], DateTime(2025, 6, 18, 14, 0));
      await repo.addPlaybackListenedMs(
        songRowId: 1,
        listenedMs: 0,
        at: DateTime(2025, 6, 18, 14, 5),
      );

      final b = await repo.listeningBreakdown(now: DateTime(2025, 6, 18, 15));
      expect(b.totalListenedMs, 0);
      expect(b.totalPlays, 1);
    });

    test('credits the most recent history row for a song', () async {
      await repo.recordPlayback([1], DateTime(2025, 6, 18, 14, 0));
      await repo.recordPlayback([1], DateTime(2025, 6, 18, 15, 0));
      await repo.addPlaybackListenedMs(
        songRowId: 1,
        listenedMs: 30000,
        at: DateTime(2025, 6, 18, 15, 2),
      );

      final rows = await db
          .customSelect(
            'SELECT listened_ms FROM play_history WHERE song_id = 1 ORDER BY id',
          )
          .get();
      expect(rows[0].data['listened_ms'], 0);
      expect(rows[1].data['listened_ms'], 30000);

      final b = await repo.listeningBreakdown(now: DateTime(2025, 6, 18, 16));
      expect(b.totalListenedMs, 30000);
      expect(b.totalPlays, 2);
      expect(b.totalUniqueSongs, 1);
    });

    test('daily/weekly/yearly/peak-day boundaries are correct', () async {
      await repo.recordPlayback([1], DateTime(2024, 12, 20, 12, 0));
      await repo.addPlaybackListenedMs(
        songRowId: 1,
        listenedMs: 40000,
        at: DateTime(2024, 12, 20, 12, 5),
      );
      await repo.recordPlayback([2], DateTime(2025, 6, 14, 12, 0));
      await repo.addPlaybackListenedMs(
        songRowId: 2,
        listenedMs: 30000,
        at: DateTime(2025, 6, 14, 12, 5),
      );
      await repo.recordPlayback([3], DateTime(2025, 6, 16, 10, 0));
      await repo.addPlaybackListenedMs(
        songRowId: 3,
        listenedMs: 20000,
        at: DateTime(2025, 6, 16, 10, 5),
      );
      await repo.recordPlayback([4], DateTime(2025, 6, 17, 10, 0));
      await repo.addPlaybackListenedMs(
        songRowId: 4,
        listenedMs: 50000,
        at: DateTime(2025, 6, 17, 10, 5),
      );
      await repo.recordPlayback([5], DateTime(2025, 6, 18, 10, 0));
      await repo.addPlaybackListenedMs(
        songRowId: 5,
        listenedMs: 10000,
        at: DateTime(2025, 6, 18, 10, 5),
      );

      final b = await repo.listeningBreakdown(now: DateTime(2025, 6, 18, 12));

      expect(b.totalPlays, 5);
      expect(b.totalListenedMs, 40000 + 30000 + 20000 + 50000 + 10000);
      expect(b.totalUniqueSongs, 5);

      expect(b.year.plays, 4);
      expect(b.year.listenedMs, 30000 + 20000 + 50000 + 10000);
      expect(b.year.uniqueSongs, 4);

      expect(b.week.plays, 3);
      expect(b.week.listenedMs, 20000 + 50000 + 10000);
      expect(b.week.uniqueSongs, 3);

      final peak = b.peakDay!;
      expect(peak.day.year, 2025);
      expect(peak.day.month, 6);
      expect(peak.day.day, 17);
      expect(peak.listenedMs, 50000);
      expect(peak.plays, 1);

      expect(b.weekDaily[0].listenedMs, 20000);
      expect(b.weekDaily[1].listenedMs, 50000);
      expect(b.weekDaily[2].listenedMs, 10000);
      expect(b.weekDaily[3].listenedMs, 0);

      expect(b.yearMonthly[5].listenedMs, 30000 + 20000 + 50000 + 10000);
      expect(b.yearMonthly[11].listenedMs, 0);
    });

    test('top songs and top artist within a period', () async {
      await repo.recordPlayback([1], DateTime(2025, 6, 16, 10, 0));
      await repo.recordPlayback([1], DateTime(2025, 6, 16, 11, 0));
      await repo.recordPlayback([2], DateTime(2025, 6, 17, 10, 0));

      final b = await repo.listeningBreakdown(now: DateTime(2025, 6, 18, 12));

      expect(b.week.plays, 3);
      expect(b.week.topSongs.first.label, 'Song 1');
      expect(b.week.topSongs.first.count, 2);
      expect(b.week.topArtist!.count, 2);
    });

    test('all-time top artist insight across periods', () async {
      // Song 1 -> 'Artist 1', Song 2 -> 'Artist 2'.
      await repo.recordPlayback([1], DateTime(2025, 6, 16, 10, 0));
      await repo.recordPlayback([1], DateTime(2025, 6, 17, 10, 0));
      await repo.recordPlayback([2], DateTime(2024, 12, 20, 10, 0));

      final b = await repo.listeningBreakdown(now: DateTime(2025, 6, 18, 12));

      expect(b.topArtist, isNotNull);
      // Artist 1 was played twice all-time (across both years), Artist 2 once.
      expect(b.topArtist!.label, 'artist 1');
      expect(b.topArtist!.count, 2);
    });
  });

  group('play counting', () {
    test('repeated plays increment play_count and add history rows', () async {
      await repo.recordPlayback([1], DateTime(2025, 6, 18, 10, 0));
      await repo.recordPlayback([1], DateTime(2025, 6, 18, 11, 0));
      await repo.recordPlayback([1], DateTime(2025, 6, 18, 12, 0));

      final stats = (await (db.select(
        db.songStats,
      )..where((t) => t.songId.equals(1))).get()).first;
      expect(stats.playCount, 3);

      final rows = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM play_history WHERE song_id = 1',
          )
          .get();
      expect(rows.first.data['c'], 3);
    });
  });

  group('persistence across restart', () {
    test('play history survives reopening the database', () async {
      final dir = await _tempDir();
      final file = '$dir${Platform.pathSeparator}vora_test.db';
      var d1 = AppDatabase(NativeDatabase(File(file)));
      var r1 = LibraryRepository(d1);
      await r1.syncTracks([for (var i = 1; i <= 5; i++) _msTrack(i)]);
      await r1.recordPlayback([1], DateTime(2025, 6, 18, 10, 0));
      await r1.addPlaybackListenedMs(
        songRowId: 1,
        listenedMs: 90000,
        at: DateTime(2025, 6, 18, 10, 5),
      );
      await d1.close();

      d1 = AppDatabase(NativeDatabase(File(file)));
      r1 = LibraryRepository(d1);
      final b = await r1.listeningBreakdown(now: DateTime(2025, 6, 18, 12));
      expect(b.totalPlays, 1);
      expect(b.totalListenedMs, 90000);
      await d1.close();
    });
  });

  group('top / recent song lists', () {
    test('top songs: max 5, ordered by play count, no duplicates', () async {
      // Songs 1..5 seeded by setUp. Give each a distinct play count and
      // ensure song 1 is played many times so ordering is unambiguous.
      for (var play = 0; play < 5; play++) {
        await repo.recordPlayback([1], DateTime(2025, 6, 10, 10 + play));
      }
      for (var play = 0; play < 3; play++) {
        await repo.recordPlayback([2], DateTime(2025, 6, 11, 10 + play));
      }
      await repo.recordPlayback([3], DateTime(2025, 6, 12, 10));
      await repo.recordPlayback([4], DateTime(2025, 6, 13, 10));
      await repo.recordPlayback([5], DateTime(2025, 6, 14, 10));
      // Replaying the same song must never create a duplicate entry.
      await repo.recordPlayback([1], DateTime(2025, 6, 15, 10));

      final top = await repo.topPlayedSongs(limit: 5);

      expect(top.length, 5);
      expect(top.map((t) => t.song.id).toSet().length, 5);
      // Highest play count first (song 1 has 6 plays, song 2 has 3).
      expect(top.first.song.id, 1);
      expect(top[1].song.id, 2);
    });

    test('top songs: fewer than 5 returns only what exists', () async {
      await repo.recordPlayback([1], DateTime(2025, 6, 12, 10));
      final top = await repo.topPlayedSongs(limit: 5);
      expect(top.length, 1);
      expect(top.first.song.id, 1);
    });

    test('recent songs: max 5, newest history timestamp first', () async {
      // Play songs out of order so insertion order != recency order.
      await repo.recordPlayback([1], DateTime(2025, 6, 10, 10));
      await repo.recordPlayback([2], DateTime(2025, 6, 14, 10));
      await repo.recordPlayback([3], DateTime(2025, 6, 12, 10));
      await repo.recordPlayback([4], DateTime(2025, 6, 18, 10));
      await repo.recordPlayback([5], DateTime(2025, 6, 11, 10));

      final recent = await repo.recentlyPlayedSongs(limit: 5);

      expect(recent.length, 5);
      // Newest first: song 4 (Jun 18) then 2 (Jun 14) then 3, 5, 1.
      expect(recent.map((t) => t.song.id).toList(), [4, 2, 3, 5, 1]);
    });

    test('songs never played appear in neither list', () async {
      await repo.recordPlayback([1], DateTime(2025, 6, 12, 10));
      final top = await repo.topPlayedSongs(limit: 5);
      final recent = await repo.recentlyPlayedSongs(limit: 5);
      expect(top.map((t) => t.song.id), [1]);
      expect(recent.map((t) => t.song.id), [1]);
    });
  });

  group('single source of truth: header time == graph time', () {
    test('listeningStats.totalListeningMs equals actual listened ms, not '
        'play_count x duration', () async {
      // Song 1 is played and actually heard for 120s; Song 2 heard for 30s.
      // The song durations are ~180s, so the OLD estimate
      // (play_count x duration_ms) would report ~360s — much larger than the
      // real ~150s. The header and the graphs must agree.
      await repo.recordPlayback([1], DateTime(2025, 6, 18, 10));
      await repo.addPlaybackListenedMs(
        songRowId: 1,
        listenedMs: 120000,
        at: DateTime(2025, 6, 18, 10, 2),
      );
      await repo.recordPlayback([2], DateTime(2025, 6, 18, 11));
      await repo.addPlaybackListenedMs(
        songRowId: 2,
        listenedMs: 30000,
        at: DateTime(2025, 6, 18, 11, 1),
      );

      final stats = await repo.listeningStats();
      final breakdown = await repo.listeningBreakdown(
        now: DateTime(2025, 6, 18, 12),
      );

      // Exact actual heard time, not play_count x duration.
      expect(stats.totalListeningMs, 150000);
      // Header (stats) and graph aggregate (breakdown) share one value.
      expect(stats.totalListeningMs, breakdown.totalListenedMs);
      expect(stats.formattedListeningTime, '2m');
    });

    test('week report includes early local-hours plays on the week start', () async {
      // Reference = local Wednesday 2025-06-18, so the local week starts Monday
      // 2025-06-16 at local midnight. A play at 00:30 local Monday must count
      // in "this week" and appear on the Monday graph bar.
      await repo.recordPlayback([1], DateTime(2025, 6, 16, 0, 30));
      await repo.addPlaybackListenedMs(
        songRowId: 1,
        listenedMs: 60000,
        at: DateTime(2025, 6, 16, 0, 35),
      );

      final b = await repo.listeningBreakdown(now: DateTime(2025, 6, 18, 12));
      expect(b.week.plays, 1);
      expect(b.week.listenedMs, 60000);
      final monday = b.weekDaily.firstWhere(
        (d) => d.day.year == 2025 && d.day.month == 6 && d.day.day == 16,
      );
      expect(monday.listenedMs, 60000);
    });
  });
}

Future<String> _tempDir() async {
  final base =
      '${Directory.systemTemp.path}${Platform.pathSeparator}vora_stats_${DateTime.now().microsecondsSinceEpoch}';
  await Directory(base).create(recursive: true);
  return base;
}

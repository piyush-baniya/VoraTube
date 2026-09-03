import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';

/// Regression tests for the Home/Statistics listening history semantics:
///
/// * "Today" is a window onto the current calendar day and SHOULD reset at
///   midnight — without erasing anything.
/// * "Top Day" (peakDay), "This Week" and "This Year" are aggregated from the
///   same persisted `play_history` rows and must NEVER reset just because the
///   calendar date changed.
///
/// All figures derive from `play_history`, so no destructive migration or
/// `todayDuration`-style snapshot column is involved: moving the window only
/// re-buckets rows that stay in the database.
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

  /// Records one play of [songRowId] starting at [at] with [listenedMs] of
  /// real heard time credited a few minutes later.
  Future<void> play(int songRowId, DateTime at, int listenedMs) async {
    await repo.recordPlayback([songRowId], at);
    await repo.addPlaybackListenedMs(
      songRowId: songRowId,
      listenedMs: listenedMs,
      at: at.add(const Duration(minutes: 5)),
    );
  }

  group('listening history preservation', () {
    test('today isolates the current calendar day only', () async {
      await play(1, DateTime(2025, 6, 17, 10, 0), 60000);
      await play(2, DateTime(2025, 6, 18, 10, 0), 120000);
      await play(2, DateTime(2025, 6, 18, 11, 0), 60000);

      final b = await repo.listeningBreakdown(now: DateTime(2025, 6, 18, 12));

      expect(b.today.listenedMs, 180000);
      expect(b.today.plays, 2);
      expect(b.today.day, DateTime(2025, 6, 18));
      // The underlying history still holds everything.
      expect(b.totalListenedMs, 240000);
      expect(b.totalPlays, 3);
    });

    test('crossing midnight resets today but preserves peak/week/year',
        () async {
      await play(1, DateTime(2025, 6, 16, 20, 0), 300000);
      await play(2, DateTime(2025, 6, 18, 10, 0), 60000);

      final before = await repo.listeningBreakdown(
        now: DateTime(2025, 6, 18, 12),
      );
      expect(before.today.listenedMs, 60000);
      expect(before.peakDay!.day, DateTime(2025, 6, 16));
      expect(before.peakDay!.listenedMs, 300000);
      expect(before.week.listenedMs, 360000);
      expect(before.year.listenedMs, 360000);

      // A new day begins with no new plays: today is empty, but nothing
      // historical may reset.
      final after = await repo.listeningBreakdown(
        now: DateTime(2025, 6, 19, 0, 30),
      );
      expect(after.today.listenedMs, 0);
      expect(after.today.plays, 0);
      expect(after.today.day, DateTime(2025, 6, 19));
      expect(after.peakDay!.day, DateTime(2025, 6, 16));
      expect(after.peakDay!.listenedMs, 300000);
      expect(after.week.listenedMs, 360000);
      expect(after.week.plays, 2);
      expect(after.year.listenedMs, 360000);
      expect(after.totalListenedMs, 360000);
      expect(after.totalPlays, 2);
    });

    test('a new week starts a fresh weekly window but keeps history',
        () async {
      await play(1, DateTime(2025, 6, 16, 10, 0), 200000);
      await play(2, DateTime(2025, 6, 24, 10, 0), 60000);

      final b = await repo.listeningBreakdown(now: DateTime(2025, 6, 24, 12));

      // Weekly window (Mon Jun 23 – Sun Jun 29) holds only the new play.
      expect(b.week.listenedMs, 60000);
      expect(b.week.plays, 1);
      expect(b.today.listenedMs, 60000);
      // Historical aggregates are untouched.
      expect(b.peakDay!.day, DateTime(2025, 6, 16));
      expect(b.peakDay!.listenedMs, 200000);
      expect(b.year.listenedMs, 260000);
      expect(b.totalListenedMs, 260000);
      expect(b.totalPlays, 2);
      // The previous week's daily bars are not part of this week's chart.
      expect(b.weekDaily.length, 7);
      expect(
        b.weekDaily.fold<int>(0, (sum, d) => sum + d.listenedMs),
        60000,
      );
    });

    test('a new year starts a fresh yearly window but keeps history',
        () async {
      await play(1, DateTime(2024, 12, 20, 10, 0), 200000);
      await play(2, DateTime(2025, 6, 18, 10, 0), 60000);

      final b = await repo.listeningBreakdown(now: DateTime(2025, 6, 18, 12));

      expect(b.year.listenedMs, 60000);
      expect(b.year.plays, 1);
      expect(b.today.listenedMs, 60000);
      expect(b.peakDay!.day, DateTime(2024, 12, 20));
      expect(b.peakDay!.listenedMs, 200000);
      expect(b.totalListenedMs, 260000);
      expect(b.totalPlays, 2);

      // Viewed from the old year, that year's window still holds its data.
      final old = await repo.listeningBreakdown(now: DateTime(2024, 12, 21));
      expect(old.year.listenedMs, 200000);
      expect(old.today.listenedMs, 0);
      expect(old.today.day, DateTime(2024, 12, 21));
      expect(old.peakDay!.day, DateTime(2024, 12, 20));
    });

    test('future-dated rows never leak into This Week', () async {
      await play(1, DateTime(2025, 6, 30, 10, 0), 120000);

      final b = await repo.listeningBreakdown(now: DateTime(2025, 6, 18, 12));

      expect(b.week.listenedMs, 0);
      expect(b.week.plays, 0);
      expect(b.today.listenedMs, 0);
      // All-time aggregates still account for the row.
      expect(b.totalListenedMs, 120000);
      expect(b.totalPlays, 1);
      expect(b.peakDay!.day, DateTime(2025, 6, 30));
    });

    test('history windows survive a database reopen', () async {
      final dir = await Directory.systemTemp.createTemp('vora_stats_test');
      final file = '${dir.path}${Platform.pathSeparator}vora_history.db';
      try {
        var fileDb = AppDatabase(NativeDatabase(File(file)));
        var fileRepo = LibraryRepository(fileDb);
        await fileRepo.syncTracks([for (var i = 1; i <= 5; i++) _msTrack(i)]);
        await fileRepo.recordPlayback([1], DateTime(2025, 6, 16, 10, 0));
        await fileRepo.addPlaybackListenedMs(
          songRowId: 1,
          listenedMs: 200000,
          at: DateTime(2025, 6, 16, 10, 5),
        );
        await fileRepo.recordPlayback([2], DateTime(2025, 6, 18, 10, 0));
        await fileRepo.addPlaybackListenedMs(
          songRowId: 2,
          listenedMs: 60000,
          at: DateTime(2025, 6, 18, 10, 5),
        );
        await fileDb.close();

        // Simulate an app restart: reopen the same file and re-read.
        fileDb = AppDatabase(NativeDatabase(File(file)));
        fileRepo = LibraryRepository(fileDb);
        final b = await fileRepo.listeningBreakdown(
          now: DateTime(2025, 6, 18, 12),
        );
        expect(b.totalListenedMs, 260000);
        expect(b.totalPlays, 2);
        expect(b.today.listenedMs, 60000);
        expect(b.peakDay!.day, DateTime(2025, 6, 16));
        expect(b.peakDay!.listenedMs, 200000);
        expect(b.week.listenedMs, 260000);
        expect(b.year.listenedMs, 260000);
        await fileDb.close();
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}

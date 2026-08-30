import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/playlists/presentation/widgets/home_playlist_strip.dart';

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

Future<AppDatabase> _seedDb({int songs = 0}) async {
  final db = AppDatabase(NativeDatabase.memory());
  if (songs > 0) {
    final repo = LibraryRepository(db);
    await repo.syncTracks([for (var i = 1; i <= songs; i++) _msTrack(i)]);
  }
  return db;
}

Widget _wrap(AppDatabase db, Widget child) {
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('HomePlaylistStrip empty-library gating', () {
    testWidgets('hides the strip (including Create CTA) when the library has '
        'no songs', (tester) async {
      final db = await _seedDb(songs: 0);
      addTearDown(db.close);

      await tester.pumpWidget(_wrap(db, const HomePlaylistStrip()));
      await tester.pumpAndSettle();

      expect(find.byType(HomePlaylistStrip), findsOneWidget);
      expect(
        find.text('Create your first playlist to organize your music.'),
        findsNothing,
      );
      expect(find.text('No playlists yet'), findsNothing);
    });

    testWidgets('shows the Create CTA once the library has songs', (
      tester,
    ) async {
      final db = await _seedDb(songs: 3);
      addTearDown(db.close);

      await tester.pumpWidget(_wrap(db, const HomePlaylistStrip()));
      await tester.pumpAndSettle();

      expect(
        find.text('Create your first playlist to organize your music.'),
        findsOneWidget,
      );
    });
  });
}

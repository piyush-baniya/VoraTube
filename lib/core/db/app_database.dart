import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Songs,
    Albums,
    Artists,
    SongStats,
    Playlists,
    PlaylistSongs,
    KvEntries,
    ScanStates,
    LyricsCache,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.alterTable(
          TableMigration(songs, newColumns: [songs.source, songs.contentHash]),
        );
        await m.alterTable(
          TableMigration(albums, newColumns: [albums.albumKey]),
        );
        await m.alterTable(
          TableMigration(artists, newColumns: [artists.artistKey]),
        );
        await customStatement(
          "UPDATE albums SET album_key = 'ms:' || media_store_album_id "
          'WHERE album_key IS NULL',
        );
        await customStatement(
          "UPDATE artists SET artist_key = 'ms:' || media_store_artist_id "
          'WHERE artist_key IS NULL',
        );
      }
      if (from < 3) {
        await m.createTable(lyricsCache);
      }
    },
  );
}

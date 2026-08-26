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
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Custom migration to avoid drift's full-table-copy with future columns
        await customStatement('''
          CREATE TABLE songs_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            media_store_id INTEGER,
            content_uri TEXT NOT NULL,
            path TEXT,
            title TEXT NOT NULL,
            title_search TEXT NOT NULL,
            artist TEXT,
            artist_search TEXT,
            album_name TEXT,
            album_row_id INTEGER REFERENCES albums(id),
            artist_row_id INTEGER REFERENCES artists(id),
            genre TEXT,
            year INTEGER,
            track_number INTEGER,
            disc_number INTEGER,
            duration_ms INTEGER NOT NULL,
            date_modified_sec INTEGER NOT NULL,
            date_added_sec INTEGER,
            size_bytes INTEGER,
            format TEXT,
            source TEXT NOT NULL DEFAULT 'mediastore',
            content_hash TEXT,
            replay_gain_json TEXT
          )
        ''');
        await customStatement('''
          INSERT INTO songs_new (id, media_store_id, content_uri, path, title, title_search,
            artist, artist_search, album_name, album_row_id, artist_row_id,
            genre, year, track_number, disc_number, duration_ms,
            date_modified_sec, date_added_sec, size_bytes, format)
          SELECT id, media_store_id, content_uri, path, title, title_search,
            artist, artist_search, album_name, album_row_id, artist_row_id,
            genre, year, track_number, disc_number, duration_ms,
            date_modified_sec, date_added_sec, size_bytes, format
          FROM songs
        ''');
        await customStatement('DROP TABLE songs');
        await customStatement('ALTER TABLE songs_new RENAME TO songs');

        // Add album_key and artist_key columns to albums and artists
        await customStatement('ALTER TABLE albums ADD COLUMN album_key TEXT');
        await customStatement('ALTER TABLE artists ADD COLUMN artist_key TEXT');

        await customStatement(
          "UPDATE albums SET album_key = 'ms:' || media_store_album_id "
          'WHERE album_key IS NULL',
        );
        await customStatement(
          "UPDATE artists SET artist_key = 'ms:' || media_store_artist_id "
          'WHERE artist_key IS NULL',
        );

        // Recreate indexes
        await customStatement(
          'CREATE UNIQUE INDEX songs_source_media_store_id ON songs(source, media_store_id)',
        );
        await customStatement(
          'CREATE UNIQUE INDEX songs_source_content_hash ON songs(source, content_hash)',
        );
        await customStatement(
          'CREATE INDEX songs_album ON songs(album_row_id)',
        );
        await customStatement(
          'CREATE INDEX songs_artist ON songs(artist_row_id)',
        );
        await customStatement(
          'CREATE INDEX songs_title_search ON songs(title_search)',
        );
        await customStatement(
          'CREATE INDEX songs_date_added ON songs(date_added_sec)',
        );
        await customStatement(
          'CREATE UNIQUE INDEX albums_album_key ON albums(album_key)',
        );
        await customStatement(
          'CREATE UNIQUE INDEX artists_artist_key ON artists(artist_key)',
        );
      }
      if (from < 3) {
        await m.createTable(lyricsCache);
      }
      if (from < 4) {
        await m.addColumn(songStats, songStats.mood);
      }
      if (from < 5) {
        // Column already added in v1→v2 custom migration
      }
    },
  );
}

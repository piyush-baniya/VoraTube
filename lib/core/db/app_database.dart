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
/// Per-song attributes that are maintained outside Drift's generated code.
///
/// These columns are deliberately **not** declared in `tables.dart`. Adding
/// them there would require regenerating `app_database.g.dart` with
/// `build_runner`, and every new column expands to ~48 places in that 7,000
/// line file. A plain side table reached through [AppDatabase.customStatement]
/// and `customSelect` carries the same data with none of that coupling, and
/// `ON DELETE CASCADE` keeps it in lockstep with `songs` automatically.
///
/// Created idempotently in `beforeOpen`, so fresh installs and upgrades from
/// any earlier schema all converge on the same shape.
const songExtrasDdl = '''
CREATE TABLE IF NOT EXISTS song_extras (
  song_id INTEGER PRIMARY KEY REFERENCES songs(id) ON DELETE CASCADE,
  art_small_path TEXT,
  art_large_path TEXT,
  custom_art_path TEXT,
  is_hidden INTEGER NOT NULL DEFAULT 0,
  skip_count INTEGER NOT NULL DEFAULT 0,
  total_ms_played INTEGER NOT NULL DEFAULT 0,
  user_edited INTEGER NOT NULL DEFAULT 0,
  art_resolved_at INTEGER
)
''';

const _songExtrasIndexes = <String>[
  'CREATE INDEX IF NOT EXISTS song_extras_hidden ON song_extras(is_hidden)',
  'CREATE INDEX IF NOT EXISTS song_extras_art '
      'ON song_extras(art_small_path)',
];

/// One row per reported play, timestamped, with the millisecond count the
/// engine actually heard for that play (pause/stop time is never added).
///
/// This is the time-series backing for the daily/weekly/yearly and peak-day
/// statistics. It is a plain side table (see [songExtrasDdl]) deliberately kept
/// out of drift's generated code so it can be created idempotently in
/// [AppDatabase.migration] without a schema version bump.
const _playHistoryDdl = '''
CREATE TABLE IF NOT EXISTS play_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  song_id INTEGER NOT NULL REFERENCES songs(id) ON DELETE CASCADE,
  played_at INTEGER NOT NULL,
  listened_ms INTEGER NOT NULL DEFAULT 0
)
''';

const _playHistoryIndexes = <String>[
  'CREATE INDEX IF NOT EXISTS play_history_played_at '
      'ON play_history(played_at)',
  'CREATE INDEX IF NOT EXISTS play_history_song ON play_history(song_id)',
];

/// Album-level bookkeeping that has no place on the drift-declared table.
///
/// Only [artResolvedAt]-style attempt tracking lives here. Without it, an album
/// whose artwork genuinely does not exist anywhere — no MediaStore thumbnail,
/// no embedded picture — would be re-decoded on every single scan, because the
/// only "needs artwork" signal we have is `art_small_path IS NULL`. Recording
/// the attempt lets the scanner skip known-empty albums while still leaving
/// `art_small_path` NULL so the UI shows its fallback.
const albumExtrasDdl = '''
CREATE TABLE IF NOT EXISTS album_extras (
  album_id INTEGER PRIMARY KEY REFERENCES albums(id) ON DELETE CASCADE,
  art_resolved_at INTEGER,
  art_attempts INTEGER NOT NULL DEFAULT 0,
  custom_art_path TEXT
)
''';

class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // Idempotent, and therefore correct for fresh installs (where onCreate
      // only knows about drift-declared tables) as well as upgrades.
      await customStatement(songExtrasDdl);
      await customStatement(albumExtrasDdl);
      await customStatement(_playHistoryDdl);
      for (final statement in _songExtrasIndexes) {
        await customStatement(statement);
      }
      for (final statement in _playHistoryIndexes) {
        await customStatement(statement);
      }
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

        // Recreate indexes. `IF NOT EXISTS` matters: dropping and renaming
        // `songs` leaves some SQLite versions' auto-attached indexes behind,
        // and a bare CREATE would abort the whole migration mid-way.
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS songs_source_media_store_id '
          'ON songs(source, media_store_id)',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS songs_source_content_hash '
          'ON songs(source, content_hash)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS songs_album ON songs(album_row_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS songs_artist ON songs(artist_row_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS songs_title_search '
          'ON songs(title_search)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS songs_date_added '
          'ON songs(date_added_sec)',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS albums_album_key '
          'ON albums(album_key)',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS artists_artist_key '
          'ON artists(artist_key)',
        );
      }
      if (from < 3) {
        await m.createTable(lyricsCache);
      }
      if (from < 4) {
        await _addColumnIfMissing(
          m,
          'song_stats',
          'mood',
          'ALTER TABLE song_stats ADD COLUMN mood TEXT',
        );
      }
      if (from < 5) {
        await _addColumnIfMissing(
          m,
          'songs',
          'replay_gain_json',
          'ALTER TABLE songs ADD COLUMN replay_gain_json TEXT',
        );
      }
      if (from < 6) {
        // Repair poisoned artwork rows.
        //
        // `attachArtwork` used to persist the empty string when native
        // resolution failed, which made the "needs artwork" predicate
        // (`art_small_path IS NULL`) permanently false. Every album that
        // failed once could therefore never be retried, so artwork stayed
        // missing forever even once the native bug was fixed. Restoring NULL
        // makes those albums eligible again.
        await customStatement(
          "UPDATE albums SET art_small_path = NULL WHERE art_small_path = ''",
        );
        await customStatement(
          "UPDATE albums SET art_large_path = NULL WHERE art_large_path = ''",
        );
      }
    },
  );

  /// Adds a column only when it is genuinely absent.
  ///
  /// The v1→v2 path rebuilt `songs` from a literal DDL that already contained
  /// later columns, so a plain `ALTER TABLE` succeeds on one upgrade path and
  /// fails with "duplicate column name" on another. Checking
  /// `PRAGMA table_info` first makes both paths converge, instead of relying
  /// on a swallowed exception to hide the difference — a swallowed exception
  /// would also hide a genuine failure.
  Future<void> _addColumnIfMissing(
    Migrator m,
    String table,
    String column,
    String alterStatement,
  ) async {
    final columns = await m.database
        .customSelect('PRAGMA table_info($table)')
        .get();
    final present = columns.any((row) => row.data['name'] == column);
    if (present) return;
    await customStatement(alterStatement);
  }
}

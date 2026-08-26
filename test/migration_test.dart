import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';

/// Simulates upgrading a real Phase-1 (schema v1) database file to v4 and
/// verifies user data plus identity-key backfilling survive the trip.
void main() {
  late File dbFile;

  setUp(() {
    dbFile = File(
      '${Directory.systemTemp.path}/vt_migration_'
      '${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
  });

  tearDown(() {
    if (dbFile.existsSync()) {
      dbFile.deleteSync();
    }
  });

  test('v1 library survives upgrade; keys are backfilled', () async {
    final bootstrap = AppDatabase(NativeDatabase(dbFile));
    await bootstrap.customStatement(
      'DROP INDEX IF EXISTS songs_source_media_store_id',
    );
    await bootstrap.customStatement(
      'DROP INDEX IF EXISTS songs_source_content_hash',
    );
    await bootstrap.customStatement('DROP INDEX IF EXISTS albums_album_key');
    await bootstrap.customStatement('DROP INDEX IF EXISTS artists_artist_key');

    await bootstrap.customStatement('DROP TABLE IF EXISTS songs');
    await bootstrap.customStatement('DROP TABLE IF EXISTS albums');
    await bootstrap.customStatement('DROP TABLE IF EXISTS artists');
    await bootstrap.customStatement('DROP TABLE IF EXISTS song_stats');
    await bootstrap.customStatement('DROP TABLE IF EXISTS playlists');
    await bootstrap.customStatement('DROP TABLE IF EXISTS playlist_songs');
    await bootstrap.customStatement('DROP TABLE IF EXISTS kv_entries');
    await bootstrap.customStatement('DROP TABLE IF EXISTS scan_states');

    await bootstrap.customStatement('''
      CREATE TABLE albums (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        media_store_album_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        artist_name TEXT NULL,
        art_small_path TEXT NULL,
        art_large_path TEXT NULL
      )
    ''');
    await bootstrap.customStatement('''
      CREATE TABLE artists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        media_store_artist_id INTEGER NOT NULL,
        name TEXT NOT NULL
      )
    ''');
    await bootstrap.customStatement('''
      CREATE TABLE songs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        media_store_id INTEGER NOT NULL,
        content_uri TEXT NOT NULL,
        path TEXT NULL,
        title TEXT NOT NULL,
        title_search TEXT NOT NULL,
        artist TEXT NULL,
        artist_search TEXT NULL,
        album_name TEXT NULL,
        album_row_id INTEGER NULL,
        artist_row_id INTEGER NULL,
        genre TEXT NULL,
        year INTEGER NULL,
        track_number INTEGER NULL,
        disc_number INTEGER NULL,
        duration_ms INTEGER NOT NULL,
        date_modified_sec INTEGER NOT NULL,
        date_added_sec INTEGER NULL,
        size_bytes INTEGER NULL,
        format TEXT NULL
      )
    ''');
    await bootstrap.customStatement('''
      CREATE TABLE song_stats (
        song_id INTEGER PRIMARY KEY,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        play_count INTEGER NOT NULL DEFAULT 0,
        last_played_at INTEGER NULL
      )
    ''');
    await bootstrap.customStatement('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        pinned INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
    await bootstrap.customStatement('''
      CREATE TABLE playlist_songs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id INTEGER NOT NULL REFERENCES playlists(id),
        song_row_id INTEGER NOT NULL,
        position INTEGER NOT NULL,
        UNIQUE(playlist_id, position)
      )
    ''');
    await bootstrap.customStatement('''
      CREATE TABLE kv_entries (
        key TEXT PRIMARY KEY,
        value_text TEXT NULL
      )
    ''');
    await bootstrap.customStatement('''
      CREATE TABLE scan_states (
        source TEXT PRIMARY KEY,
        last_completed_at INTEGER NULL,
        total_songs INTEGER NULL,
        schema_version INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await bootstrap.customStatement('''
      INSERT INTO albums (id, media_store_album_id, name, artist_name)
      VALUES (1, 555, 'Legacy Album', 'Legacy Artist')
    ''');
    await bootstrap.customStatement('''
      INSERT INTO artists (id, media_store_artist_id, name)
      VALUES (1, 777, 'Legacy Artist')
    ''');
    await bootstrap.customStatement('''
      INSERT INTO songs (
        id, media_store_id, content_uri, path, title, title_search,
        artist, artist_search, album_name, album_row_id, artist_row_id,
        genre, year, track_number, disc_number, duration_ms,
        date_modified_sec, date_added_sec, size_bytes, format
      ) VALUES (
        1, 9001, 'content://media/external/audio/media/9001',
        '/storage/x/song.mp3', 'Legacy Song', 'legacy song',
        'Legacy Artist', 'legacy artist', 'Legacy Album', 1, 1,
        'Rock', 1999, 3, NULL, 240000, 111, 100, 8000000, 'mp3'
      )
    ''');
    await bootstrap.customStatement('PRAGMA user_version = 1');
    await bootstrap.close();

    final upgraded = AppDatabase(NativeDatabase(dbFile));
    addTearDown(upgraded.close);

    final song = await upgraded.select(upgraded.songs).getSingle();
    expect(song.title, 'Legacy Song');
    expect(song.mediaStoreId, 9001);
    expect(song.source, 'mediastore');
    expect(song.contentHash, isNull);
    expect(song.dateModifiedSec, 111);

    final album = await upgraded.select(upgraded.albums).getSingle();
    expect(album.mediaStoreAlbumId, 555);
    expect(album.albumKey, 'ms:555');

    final artist = await upgraded.select(upgraded.artists).getSingle();
    expect(artist.artistKey, 'ms:777');

    final repository = LibraryRepository(upgraded);
    final index = await repository.existingSongIndex();
    expect(index['ms:9001'], 111);

    final resynced = await repository.syncTracks([
      const IngestTrack(
        source: IngestSource.mediastore,
        mediaStoreId: 9001,
        albumMediaStoreId: 555,
        artistMediaStoreId: 777,
        albumKey: 'ms:555',
        artistKey: 'ms:777',
        contentUri: 'content://media/external/audio/media/9001',
        title: 'Legacy Song',
        artist: 'Legacy Artist',
        album: 'Legacy Album',
        durationMs: 240000,
        dateModifiedSec: 111,
      ),
    ]);
    expect(resynced.added, 0);
    expect(resynced.updated, 0);
  });
}

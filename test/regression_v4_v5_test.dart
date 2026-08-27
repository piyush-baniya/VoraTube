import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';

void main() {
  test('v4 DB with songs survives migration to v5 and remains queryable', () async {
    final dbFile = File(
      '${Directory.systemTemp.path}/vt_v4_v5_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(() async {
      try {
        if (dbFile.existsSync()) dbFile.deleteSync();
      } catch (_) {}
    });

    final bootstrap = AppDatabase(NativeDatabase(dbFile));
    await bootstrap.customStatement('DROP TABLE IF EXISTS songs');
    await bootstrap.customStatement('DROP TABLE IF EXISTS albums');
    await bootstrap.customStatement('DROP TABLE IF EXISTS artists');
    await bootstrap.customStatement('DROP TABLE IF EXISTS song_stats');
    await bootstrap.customStatement('DROP TABLE IF EXISTS playlists');
    await bootstrap.customStatement('DROP TABLE IF EXISTS playlist_songs');
    await bootstrap.customStatement('DROP TABLE IF EXISTS kv_entries');
    await bootstrap.customStatement('DROP TABLE IF EXISTS scan_states');
    await bootstrap.customStatement('DROP TABLE IF EXISTS lyrics_cache');

    await bootstrap.customStatement('''
      CREATE TABLE albums (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        media_store_album_id INTEGER,
        album_key TEXT,
        name TEXT NOT NULL,
        artist_name TEXT,
        art_small_path TEXT,
        art_large_path TEXT
      )
    ''');
    await bootstrap.customStatement(
      'CREATE UNIQUE INDEX albums_album_key ON albums(album_key)',
    );
    await bootstrap.customStatement('''
      CREATE TABLE artists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        media_store_artist_id INTEGER,
        name TEXT NOT NULL,
        artist_key TEXT
      )
    ''');
    await bootstrap.customStatement(
      'CREATE UNIQUE INDEX artists_artist_key ON artists(artist_key)',
    );
    await bootstrap.customStatement('''
      CREATE TABLE songs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        media_store_id INTEGER,
        source TEXT NOT NULL DEFAULT 'mediastore',
        content_hash TEXT,
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
        format TEXT
      )
    ''');
    await bootstrap.customStatement(
      'CREATE UNIQUE INDEX songs_source_media_store_id ON songs(source, media_store_id)',
    );
    await bootstrap.customStatement(
      'CREATE UNIQUE INDEX songs_source_content_hash ON songs(source, content_hash)',
    );
    await bootstrap.customStatement(
      'CREATE INDEX songs_album ON songs(album_row_id)',
    );
    await bootstrap.customStatement(
      'CREATE INDEX songs_artist ON songs(artist_row_id)',
    );
    await bootstrap.customStatement(
      'CREATE INDEX songs_title_search ON songs(title_search)',
    );
    await bootstrap.customStatement(
      'CREATE INDEX songs_date_added ON songs(date_added_sec)',
    );
    await bootstrap.customStatement('''
      CREATE TABLE song_stats (
        song_id INTEGER PRIMARY KEY,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        play_count INTEGER NOT NULL DEFAULT 0,
        last_played_at INTEGER,
        mood TEXT
      )
    ''');
    await bootstrap.customStatement('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        pinned INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )
    ''');
    await bootstrap.customStatement('''
      CREATE TABLE playlist_songs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id INTEGER NOT NULL REFERENCES playlists(id),
        song_row_id INTEGER NOT NULL REFERENCES songs(id),
        position INTEGER NOT NULL,
        UNIQUE(playlist_id, position)
      )
    ''');
    await bootstrap.customStatement(
      'CREATE TABLE kv_entries (key TEXT PRIMARY KEY, value_text TEXT)',
    );
    await bootstrap.customStatement(
      'CREATE TABLE scan_states (source TEXT PRIMARY KEY, last_completed_at INTEGER, total_songs INTEGER, schema_version INTEGER NOT NULL DEFAULT 1)',
    );
    await bootstrap.customStatement(
      'CREATE TABLE lyrics_cache (content_hash TEXT PRIMARY KEY, identity_key TEXT NOT NULL, lyrics_json TEXT NOT NULL, source TEXT NOT NULL, fetched_at INTEGER NOT NULL)',
    );

    await bootstrap.customStatement(
      "INSERT INTO albums (id, album_key, name) VALUES (1, 'ms:1', 'Album A')",
    );
    await bootstrap.customStatement(
      "INSERT INTO artists (id, artist_key, name) VALUES (1, 'a:1', 'Artist A')",
    );
    await bootstrap.customStatement(
      "INSERT INTO songs (id, media_store_id, content_uri, title, title_search, duration_ms, date_modified_sec, album_row_id, artist_row_id) VALUES (1, 101, 'content://1', 'Song One', 'song one', 200000, 1000, 1, 1)",
    );
    await bootstrap.customStatement(
      "INSERT INTO songs (id, media_store_id, content_uri, title, title_search, duration_ms, date_modified_sec, album_row_id, artist_row_id) VALUES (2, 102, 'content://2', 'Song Two', 'song two', 200000, 1000, 1, 1)",
    );
    await bootstrap.customStatement(
      "INSERT INTO songs (id, media_store_id, content_uri, title, title_search, duration_ms, date_modified_sec, album_row_id, artist_row_id) VALUES (3, 103, 'content://3', 'Song Three', 'song three', 200000, 1000, 1, 1)",
    );
    await bootstrap.customStatement('PRAGMA user_version = 4');
    await bootstrap.close();

    final upgraded = AppDatabase(NativeDatabase(dbFile));
    addTearDown(upgraded.close);

    final count = await upgraded
        .customSelect('SELECT COUNT(*) as c FROM songs')
        .getSingle();
    final c = count.read<int>('c');
    expect(c, 3, reason: 'songs must survive v4->v5, got $c');

    final cols = await upgraded.customSelect("PRAGMA table_info(songs)").get();
    final hasReplay = cols.any(
      (r) => r.read<String>('name') == 'replay_gain_json',
    );
    expect(
      hasReplay,
      isTrue,
      reason: 'replay_gain_json must exist after v4->v5',
    );

    final repo = LibraryRepository(upgraded);
    final page = await repo.songsPage(limit: 10, offset: 0);
    expect(
      page.songs.length,
      3,
      reason: 'songsPage must return 3, got ${page.songs.length}',
    );
  });
}

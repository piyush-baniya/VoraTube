import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/ingest/ingest_service.dart';
import '../../../core/player/player_controller.dart';
import '../../../core/utils/string_utils.dart';
import 'library_models.dart';

class SyncBatchResult {
  const SyncBatchResult({
    required this.added,
    required this.updated,
    required this.dirtyAlbumKeys,
  });

  final int added;
  final int updated;
  final Set<String> dirtyAlbumKeys;
}

class LibraryCounts {
  const LibraryCounts({
    required this.songs,
    required this.albums,
    required this.artists,
  });

  final int songs;
  final int albums;
  final int artists;
}

final class StoredImportedSong {
  const StoredImportedSong({required this.rowId, required this.path});

  final int rowId;
  final String path;
}

class LibraryRepository {
  LibraryRepository(this._db);

  final AppDatabase _db;

  static const int _deleteChunkSize = 400;

  /// Identity map used for change detection: track identityKey ->
  /// stored dateModifiedSec. Works uniformly across platforms because
  /// both produce stable [IngestTrack.identityKey]s.
  Future<Map<String, int>> existingSongIndex() async {
    final query = _db.selectOnly(_db.songs)
      ..addColumns([
        _db.songs.source,
        _db.songs.mediaStoreId,
        _db.songs.contentHash,
        _db.songs.dateModifiedSec,
      ]);
    final rows = await query.get();
    final index = <String, int>{};
    for (final row in rows) {
      final source = row.read(_db.songs.source)!;
      final modified = row.read(_db.songs.dateModifiedSec)!;
      if (source == IngestSource.mediastore.name) {
        final msId = row.read(_db.songs.mediaStoreId);
        if (msId != null) {
          index['ms:$msId'] = modified;
        }
      } else {
        final hash = row.read(_db.songs.contentHash);
        if (hash != null) {
          index['h:$hash'] = modified;
        }
      }
    }
    return index;
  }

  Future<SyncBatchResult> syncTracks(List<IngestTrack> tracks) {
    return _db.transaction(() async {
      var added = 0;
      var updated = 0;
      final dirtyAlbums = <String>{};

      final existingSongs =
          await (_db.select(_db.songs)..where(
                (tbl) =>
                    tbl.source.isIn(tracks.map((tr) => tr.source.name).toSet()),
              ))
              .get();
      final songByIdentityKey = <String, Song>{};
      for (final row in existingSongs) {
        final key = row.source == IngestSource.mediastore.name
            ? 'ms:${row.mediaStoreId}'
            : 'h:${row.contentHash}';
        songByIdentityKey[key] = row;
      }

      final albumKeys = tracks
          .map((tr) => tr.albumKey)
          .whereType<String>()
          .where((k) => k.isNotEmpty)
          .toSet();
      final existingAlbums = await (_db.select(
        _db.albums,
      )..where((tbl) => tbl.albumKey.isIn(albumKeys))).get();
      final albumRowIdByKey = {
        for (final row in existingAlbums)
          if (row.albumKey != null) row.albumKey!: row.id,
      };

      final artistKeys = tracks
          .map((tr) => tr.artistKey)
          .whereType<String>()
          .where((k) => k.isNotEmpty)
          .toSet();
      final existingArtists = await (_db.select(
        _db.artists,
      )..where((tbl) => tbl.artistKey.isIn(artistKeys))).get();
      final artistRowIdByKey = {
        for (final row in existingArtists)
          if (row.artistKey != null) row.artistKey!: row.id,
      };

      for (final track in tracks) {
        final albumRowId = await _ensureAlbum(
          track: track,
          rowIdByKey: albumRowIdByKey,
        );
        final artistRowId = await _ensureArtist(
          track: track,
          rowIdByKey: artistRowIdByKey,
        );

        final title = _resolveTitle(track);
        final companion =
            SongsCompanion.insert(
              contentUri: track.contentUri,
              title: title,
              titleSearch: title.toLowerCase(),
              durationMs: track.durationMs,
              dateModifiedSec: track.dateModifiedSec,
              source: Value(track.source.name),
              mediaStoreId: Value(track.mediaStoreId),
              contentHash: Value(track.contentHash),
              path: Value(track.path),
              artist: Value(track.artist),
              artistSearch: Value(track.artist?.toLowerCase()),
              albumName: Value(track.album),
              genre: Value(track.genre),
              year: Value(track.year),
              trackNumber: Value(track.trackNumber),
              discNumber: Value(track.discNumber),
              dateAddedSec: Value(track.dateAddedSec),
              sizeBytes: Value(track.sizeBytes),
              format: Value(formatFromPath(track.path)),
            ).copyWith(
              albumRowId: Value(albumRowId),
              artistRowId: Value(artistRowId),
            );

        final existing = songByIdentityKey[track.identityKey];
        if (existing == null) {
          await _db.into(_db.songs).insert(companion);
          added++;
          if (albumRowId != null && track.albumKey != null) {
            dirtyAlbums.add(track.albumKey!);
          }
        } else if (existing.dateModifiedSec != track.dateModifiedSec) {
          await (_db.update(
            _db.songs,
          )..where((tbl) => tbl.id.equals(existing.id))).write(companion);
          updated++;
          if (albumRowId != null && track.albumKey != null) {
            dirtyAlbums.add(track.albumKey!);
          }
        }

        if (track.album != null && albumRowId != null) {
          await (_db.update(_db.albums)
                ..where((tbl) => tbl.id.equals(albumRowId)))
              .write(AlbumsCompanion(name: Value(track.album!)));
        }
      }

      return SyncBatchResult(
        added: added,
        updated: updated,
        dirtyAlbumKeys: dirtyAlbums,
      );
    });
  }

  Future<int?> _ensureAlbum({
    required IngestTrack track,
    required Map<String, int> rowIdByKey,
  }) async {
    final key = track.albumKey;
    if (key == null || key.isEmpty) {
      return null;
    }
    if (rowIdByKey.containsKey(key)) {
      return rowIdByKey[key];
    }
    final name = track.album?.trim();
    if (name == null || name.isEmpty) {
      return null;
    }
    await _db
        .into(_db.albums)
        .insert(
          AlbumsCompanion.insert(
            name: name,
            albumKey: Value(key),
            mediaStoreAlbumId: Value(track.albumMediaStoreId),
            artistName: Value(track.albumArtist ?? track.artist),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    final created = await (_db.select(
      _db.albums,
    )..where((tbl) => tbl.albumKey.equals(key))).getSingleOrNull();
    if (created == null) {
      return null;
    }
    rowIdByKey[key] = created.id;
    return created.id;
  }

  Future<int?> _ensureArtist({
    required IngestTrack track,
    required Map<String, int> rowIdByKey,
  }) async {
    final key = track.artistKey;
    if (key == null || key.isEmpty) {
      return null;
    }
    if (rowIdByKey.containsKey(key)) {
      return rowIdByKey[key];
    }
    final name = track.artist?.trim();
    if (name == null || name.isEmpty) {
      return null;
    }
    await _db
        .into(_db.artists)
        .insert(
          ArtistsCompanion.insert(
            name: name,
            artistKey: Value(key),
            mediaStoreArtistId: Value(track.artistMediaStoreId),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    final created = await (_db.select(
      _db.artists,
    )..where((tbl) => tbl.artistKey.equals(key))).getSingleOrNull();
    if (created == null) {
      return null;
    }
    rowIdByKey[key] = created.id;
    return created.id;
  }

  Future<List<String>> albumsNeedingArt(Set<String> dirtyAlbumKeys) async {
    if (dirtyAlbumKeys.isEmpty) {
      return const [];
    }
    final query = _db.selectOnly(_db.albums)
      ..addColumns([_db.albums.albumKey])
      ..where(_db.albums.albumKey.isIn(dirtyAlbumKeys))
      ..where(
        _db.albums.artSmallPath.isNull() | _db.albums.artLargePath.isNull(),
      );
    final rows = await query.get();
    return rows
        .map((row) => row.read(_db.albums.albumKey))
        .whereType<String>()
        .toList();
  }

  Future<void> attachArtwork(Map<String, ResolvedArtwork?> resolved) async {
    if (resolved.isEmpty) {
      return;
    }
    await _db.transaction(() async {
      for (final entry in resolved.entries) {
        final artwork = entry.value;
        await (_db.update(
          _db.albums,
        )..where((tbl) => tbl.albumKey.equals(entry.key))).write(
          AlbumsCompanion(
            artSmallPath: Value(artwork?.smallPath ?? ''),
            artLargePath: Value(artwork?.largePath ?? ''),
          ),
        );
      }
    });
  }

  Future<int> removeAbsentMediaStore(Set<int> seenMediaStoreIds) async {
    final doomedRows = seenMediaStoreIds.isEmpty
        ? await (_db.select(_db.songs)..where(
                (tbl) => tbl.source.equals(IngestSource.mediastore.name),
              ))
              .get()
        : await (_db.select(_db.songs)..where(
                (tbl) =>
                    tbl.source.equals(IngestSource.mediastore.name) &
                    tbl.mediaStoreId.isNotIn(seenMediaStoreIds),
              ))
              .get();
    final doomedIds = doomedRows.map((r) => r.id).toList();

    await _deleteSongRows(doomedIds);
    await _cleanupOrphans();
    return doomedIds.length;
  }

  Future<List<StoredImportedSong>> importedSongsForReconciliation() async {
    final rows = await (_db.select(
      _db.songs,
    )..where((tbl) => tbl.source.equals(IngestSource.imported.name))).get();
    return rows
        .map((row) => StoredImportedSong(rowId: row.id, path: row.path ?? ''))
        .where((s) => s.path.isNotEmpty)
        .toList(growable: false);
  }

  Future<int> deleteSongsByRowIds(Set<int> rowIds) async {
    if (rowIds.isEmpty) {
      return 0;
    }
    await _deleteSongRows(rowIds.toList());
    await _cleanupOrphans();
    return rowIds.length;
  }

  Future<void> _deleteSongRows(List<int> ids) async {
    for (var i = 0; i < ids.length; i += _deleteChunkSize) {
      final chunk = ids.sublist(i, (i + _deleteChunkSize).clamp(0, ids.length));
      await (_db.delete(_db.songs)..where((tbl) => tbl.id.isIn(chunk))).go();
    }
  }

  Future<void> _cleanupOrphans() async {
    await _db.customStatement(
      'DELETE FROM albums WHERE id NOT IN '
      '(SELECT DISTINCT album_row_id FROM songs WHERE album_row_id IS NOT NULL)',
    );
    await _db.customStatement(
      'DELETE FROM artists WHERE id NOT IN '
      '(SELECT DISTINCT artist_row_id FROM songs WHERE artist_row_id IS NOT NULL)',
    );
    await _db.customStatement(
      'DELETE FROM playlist_songs WHERE song_row_id NOT IN '
      '(SELECT id FROM songs)',
    );
  }

  Future<LibraryCounts> currentCounts() async {
    final songsExp = _db.songs.id.count();
    final albumsExp = _db.albums.id.count();
    final artistsExp = _db.artists.id.count();

    final songRow = await (_db.selectOnly(
      _db.songs,
    )..addColumns([songsExp])).getSingle();
    final albumRow = await (_db.selectOnly(
      _db.albums,
    )..addColumns([albumsExp])).getSingle();
    final artistRow = await (_db.selectOnly(
      _db.artists,
    )..addColumns([artistsExp])).getSingle();

    return LibraryCounts(
      songs: songRow.read(songsExp)!,
      albums: albumRow.read(albumsExp)!,
      artists: artistRow.read(artistsExp)!,
    );
  }

  Future<void> completeScan({required int totalSongs}) async {
    await _db
        .into(_db.scanStates)
        .insertOnConflictUpdate(
          ScanStatesCompanion.insert(
            source: 'mediastore',
            lastCompletedAt: Value(DateTime.now()),
            totalSongs: Value(totalSongs),
          ),
        );
  }

  Future<ScanStateEntry?> lastScanEntry() {
    return (_db.select(
      _db.scanStates,
    )..where((tbl) => tbl.source.equals('mediastore'))).getSingleOrNull();
  }

  String _resolveTitle(IngestTrack track) {
    final raw = track.title?.trim();
    if (raw != null && raw.isNotEmpty) {
      return raw;
    }
    final fallback = fallbackTitleFromPath(track.path);
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }
    return 'Untitled';
  }
}

// ---------------------------------------------------------------------------
// Playback support: KV access and song resolution for the player layer.
// ---------------------------------------------------------------------------

extension LibraryPlaybackData on LibraryRepository {
  Future<String?> kvGet(String key) async {
    final query = _db.selectOnly(_db.kvEntries)
      ..addColumns([_db.kvEntries.valueText])
      ..where(_db.kvEntries.key.equals(key));
    final row = await query.getSingleOrNull();
    return row?.read(_db.kvEntries.valueText);
  }

  Future<void> kvSet(String key, String value) async {
    await _db
        .into(_db.kvEntries)
        .insertOnConflictUpdate(
          KvEntriesCompanion.insert(key: key, valueText: Value(value)),
        );
  }

  Future<List<SongRef>> allSongRefs({int limit = 1000}) async {
    final rows =
        await (_db.select(_db.songs)
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.titleSearch)])
              ..limit(limit))
            .get();
    return _rowsToRefs(rows);
  }

  Future<List<SongRef>> resolveSongsByIdentityKeys(
    List<String> identityKeys,
  ) async {
    if (identityKeys.isEmpty) {
      return const [];
    }
    final rows = await (_db.select(_db.songs)..limit(2000)).get();
    final refs = await _rowsToRefs(rows);
    final wanted = identityKeys.toSet();
    final matches = <SongRef>[];
    final byKey = <String, SongRef>{};
    for (final ref in refs) {
      if (wanted.contains(ref.identityKey)) {
        byKey[ref.identityKey] = ref;
      }
    }
    for (final key in identityKeys) {
      final ref = byKey[key];
      if (ref != null) {
        matches.add(ref);
      }
    }
    return matches;
  }
}

extension on LibraryRepository {
  Future<List<SongRef>> _rowsToRefs(List<Song> rows) async {
    final albumIds = rows.map((r) => r.albumRowId).whereType<int>().toSet();
    final artByAlbumRowId = <int, String?>{};
    if (albumIds.isNotEmpty) {
      final albums = await (_db.select(
        _db.albums,
      )..where((tbl) => tbl.id.isIn(albumIds))).get();
      for (final a in albums) {
        artByAlbumRowId[a.id] = (a.artLargePath?.isNotEmpty ?? false)
            ? a.artLargePath
            : (a.artSmallPath?.isNotEmpty ?? false ? a.artSmallPath : null);
      }
    }
    return [
      for (final r in rows)
        SongRef(
          identityKey: r.source == IngestSource.mediastore.name
              ? 'ms:${r.mediaStoreId}'
              : 'h:${r.contentHash}',
          uri: r.contentUri,
          title: r.title,
          artist: r.artist,
          album: r.albumName,
          artPath: r.albumRowId == null ? null : artByAlbumRowId[r.albumRowId!],
          durationMs: r.durationMs,
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Library browsing queries: paginated, indexed, never whole-table watches.
// ---------------------------------------------------------------------------

extension LibraryQueries on LibraryRepository {
  Future<SongPage> songsPage({
    required int limit,
    int offset = 0,
    SongSort sort = SongSort.recentlyAdded,
    bool favoritesOnly = false,
  }) async {
    final stats = _db.songStats;
    final albums = _db.albums;
    final favoriteExp = stats.isFavorite;

    final query = _db.select(_db.songs).join([
      leftOuterJoin(stats, stats.songId.equalsExp(_db.songs.id)),
      leftOuterJoin(albums, albums.id.equalsExp(_db.songs.albumRowId)),
    ]);

    if (favoritesOnly) {
      query.where(favoriteExp.equals(true));
    }

    switch (sort) {
      case SongSort.recentlyAdded:
        query.orderBy([
          OrderingTerm.desc(_db.songs.dateAddedSec),
          OrderingTerm.desc(_db.songs.id),
        ]);
      case SongSort.title:
        query.orderBy([OrderingTerm.asc(_db.songs.titleSearch)]);
      case SongSort.artist:
        query.orderBy([
          OrderingTerm.asc(
            coalesce([_db.songs.artistSearch, const Variable('')]),
          ),
          OrderingTerm.asc(_db.songs.titleSearch),
        ]);
      case SongSort.album:
        query.orderBy([
          OrderingTerm.asc(coalesce([_db.songs.albumName, const Variable('')])),
          OrderingTerm.asc(_db.songs.trackNumber),
        ]);
      case SongSort.duration:
        query.orderBy([OrderingTerm.desc(_db.songs.durationMs)]);
    }

    query.limit(limit, offset: offset);
    final rows = await query.get();

    final songs = [
      for (final row in rows)
        SongTileData(
          song: row.readTable(_db.songs),
          artPath: _pickArt(
            row.read(albums.artLargePath),
            row.read(albums.artSmallPath),
          ),
        ),
    ];
    final next = songs.length < limit ? -1 : offset + limit;
    return SongPage(songs: songs, nextOffset: next);
  }

  Future<List<AlbumSummary>> albumOverview({int limit = 500}) async {
    final albums = _db.albums;
    final songs = _db.songs;
    final songCount = songs.id.count();
    final totalDur = songs.durationMs.sum();

    final query = _db.selectOnly(albums).join([
      innerJoin(songs, songs.albumRowId.equalsExp(albums.id)),
    ]);
    query
      ..addColumns([
        albums.id,
        albums.albumKey,
        albums.name,
        albums.artistName,
        albums.artSmallPath,
        albums.artLargePath,
        songCount,
        totalDur,
      ])
      ..groupBy([albums.id])
      ..orderBy([OrderingTerm.desc(totalDur)]);

    query.limit(limit);
    final rows = await query.get();
    return [
      for (final row in rows)
        AlbumSummary(
          albumRowId: row.read(albums.id)!,
          key: row.read(albums.albumKey) ?? '',
          name: row.read(albums.name)!,
          artistName: row.read(albums.artistName),
          artPath: _pickArt(
            row.read(albums.artLargePath),
            row.read(albums.artSmallPath),
          ),
          songCount: row.read(songCount) ?? 0,
          totalDurationMs: row.read(totalDur) ?? 0,
        ),
    ];
  }

  Future<List<ArtistSummary>> artistOverview({int limit = 500}) async {
    final artists = _db.artists;
    final songs = _db.songs;
    final songCount = songs.id.count();

    final query = _db.selectOnly(artists).join([
      innerJoin(songs, songs.artistRowId.equalsExp(artists.id)),
    ]);
    query
      ..addColumns([artists.id, artists.artistKey, artists.name, songCount])
      ..groupBy([artists.id])
      ..orderBy([OrderingTerm.desc(songCount)]);

    query.limit(limit);
    final rows = await query.get();
    return [
      for (final row in rows)
        ArtistSummary(
          artistRowId: row.read(artists.id)!,
          key: row.read(artists.artistKey) ?? '',
          name: row.read(artists.name)!,
          songCount: row.read(songCount) ?? 0,
        ),
    ];
  }

  Future<List<GenreSummary>> genreOverview({int limit = 100}) async {
    final genreExp = _db.songs.genre;
    final countExp = _db.songs.id.count();
    final query = _db.selectOnly(_db.songs)
      ..addColumns([genreExp, countExp])
      ..where(genreExp.isNotNull() & genreExp.equals('').not())
      ..groupBy([genreExp])
      ..orderBy([OrderingTerm.desc(countExp)]);

    query.limit(limit);
    final rows = await query.get();
    return [
      for (final row in rows)
        GenreSummary(
          genre: row.read(genreExp)!,
          songCount: row.read(countExp) ?? 0,
        ),
    ];
  }

  Future<int> toggleFavorite(int songRowId) async {
    return _db.transaction(() async {
      final existing = await (_db.select(
        _db.songStats,
      )..where((tbl) => tbl.songId.equals(songRowId))).getSingleOrNull();
      if (existing == null) {
        await _db
            .into(_db.songStats)
            .insert(
              SongStatsCompanion(
                songId: Value(songRowId),
                isFavorite: const Value(true),
              ),
            );
        return 1;
      }
      final newValue = !existing.isFavorite;
      await (_db.update(_db.songStats)
            ..where((tbl) => tbl.songId.equals(songRowId)))
          .write(SongStatsCompanion(isFavorite: Value(newValue)));
      return newValue ? 1 : 0;
    });
  }

  Future<bool> isFavorite(int songRowId) async {
    final row = await (_db.select(
      _db.songStats,
    )..where((tbl) => tbl.songId.equals(songRowId))).getSingleOrNull();
    return row?.isFavorite ?? false;
  }

  /// Local search across songs, albums, artists and playlists using the
  /// existing normalized search columns and indexes. No FTS, no network.
  Future<SearchResults> searchAll(
    String rawQuery, {
    int perSectionLimit = 20,
  }) async {
    final q = rawQuery.trim();
    if (q.isEmpty) {
      return SearchResults(
        query: q,
        songs: const [],
        albums: const [],
        artists: const [],
        playlists: const [],
      );
    }
    final needle = '%${q.toLowerCase()}%';

    final songRows =
        await (_db.select(_db.songs)
              ..where(
                (tbl) =>
                    tbl.titleSearch.like(needle) |
                    tbl.artistSearch.like(needle) |
                    tbl.albumName.lower().like(needle),
              )
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.titleSearch)])
              ..limit(perSectionLimit))
            .get();

    final albums = _db.albums;
    final albumNameLower = albums.name.lower();
    final albumRows =
        await (_db.selectOnly(albums)
              ..addColumns([
                albums.id,
                albums.albumKey,
                albums.name,
                albums.artistName,
                albums.artSmallPath,
                albums.artLargePath,
              ])
              ..where(albumNameLower.like(needle))
              ..limit(perSectionLimit))
            .get();

    final artists = _db.artists;
    final artistRows =
        await (_db.selectOnly(artists)
              ..addColumns([artists.id, artists.artistKey, artists.name])
              ..where(artists.name.lower().like(needle))
              ..limit(perSectionLimit))
            .get();

    final playlistRows =
        await (_db.select(_db.playlists)
              ..where((tbl) => tbl.name.lower().like(needle))
              ..limit(perSectionLimit))
            .get();

    return SearchResults(
      query: q,
      songs: await _decorate(songRows),
      albums: [
        for (final row in albumRows)
          AlbumSummary(
            albumRowId: row.read(albums.id)!,
            key: row.read(albums.albumKey) ?? '',
            name: row.read(albums.name)!,
            artistName: row.read(albums.artistName),
            artPath: _pickArt(
              row.read(albums.artLargePath),
              row.read(albums.artSmallPath),
            ),
            songCount: 0,
          ),
      ],
      artists: [
        for (final row in artistRows)
          ArtistSummary(
            artistRowId: row.read(artists.id)!,
            key: row.read(artists.artistKey) ?? '',
            name: row.read(artists.name)!,
            songCount: 0,
          ),
      ],
      playlists: playlistRows,
    );
  }
}

String? _pickArt(String? large, String? small) {
  if (large != null && large.isNotEmpty && large != '') return large;
  if (small != null && small.isNotEmpty) return small;
  return null;
}

extension FilteredSongQueries on LibraryRepository {
  Future<List<SongTileData>> songsForAlbum(
    int albumRowId, {
    int limit = 500,
  }) async {
    final rows =
        await (_db.select(_db.songs)
              ..where((tbl) => tbl.albumRowId.equals(albumRowId))
              ..orderBy([
                (t) => OrderingTerm.asc(t.discNumber),
                (t) => OrderingTerm.asc(t.trackNumber),
                (t) => OrderingTerm.asc(t.titleSearch),
              ])
              ..limit(limit))
            .get();
    return _decorate(rows);
  }

  Future<List<SongTileData>> songsForArtist(
    int artistRowId, {
    int limit = 1000,
  }) async {
    final rows =
        await (_db.select(_db.songs)
              ..where((tbl) => tbl.artistRowId.equals(artistRowId))
              ..orderBy([
                (t) => OrderingTerm.desc(t.dateAddedSec),
                (t) => OrderingTerm.asc(t.titleSearch),
              ])
              ..limit(limit))
            .get();
    return _decorate(rows);
  }

  Future<List<SongTileData>> _decorate(List<Song> rows) async {
    if (rows.isEmpty) {
      return const [];
    }
    final albums =
        await (_db.select(_db.albums)..where(
              (tbl) => tbl.id.isIn(
                rows.map((r) => r.albumRowId).whereType<int>().toSet(),
              ),
            ))
            .get();
    final artById = {
      for (final a in albums) a.id: _pickArt(a.artLargePath, a.artSmallPath),
    };
    return [
      for (final r in rows)
        SongTileData(
          song: r,
          artPath: r.albumRowId == null ? null : artById[r.albumRowId!],
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Collections + playback statistics (read-side; writes via recordPlayback).
// ---------------------------------------------------------------------------

enum CollectionKind { recentlyAdded, favorites, mostPlayed, recentlyPlayed }

extension CollectionQueries on LibraryRepository {
  Future<List<SongTileData>> collectionSongs(
    CollectionKind kind, {
    int limit = 300,
  }) async {
    final stats = _db.songStats;
    switch (kind) {
      case CollectionKind.recentlyAdded:
        final rows =
            await (_db.select(_db.songs)
                  ..orderBy([
                    (t) => OrderingTerm.desc(t.dateAddedSec),
                    (t) => OrderingTerm.desc(t.id),
                  ])
                  ..limit(limit))
                .get();
        return _decorate(rows);
      case CollectionKind.favorites:
        return _collectionJoined(
          where: (songsTbl, st) => st.isFavorite.equals(true),
          orderTerms: [OrderingTerm.desc(_db.songs.dateAddedSec)],
          limit: limit,
        );
      case CollectionKind.mostPlayed:
        return _collectionJoined(
          where: (songsTbl, st) => st.playCount.isBiggerThanValue(0),
          orderTerms: [
            OrderingTerm.desc(stats.playCount),
            OrderingTerm.desc(stats.lastPlayedAt),
          ],
          limit: limit,
        );
      case CollectionKind.recentlyPlayed:
        return _collectionJoined(
          where: (songsTbl, st) => st.lastPlayedAt.isNotNull(),
          orderTerms: [OrderingTerm.desc(stats.lastPlayedAt)],
          limit: limit,
        );
    }
  }

  Future<List<SongTileData>> _collectionJoined({
    required Expression<bool> Function($SongsTable, $SongStatsTable) where,
    required List<OrderingTerm> orderTerms,
    required int limit,
  }) async {
    final stats = _db.songStats;
    final query = _db.select(_db.songs).join([
      innerJoin(stats, stats.songId.equalsExp(_db.songs.id)),
    ]);
    query.where(where(_db.songs, stats));
    query.orderBy(orderTerms);
    query.limit(limit);
    final rows = await query.get();
    return _decorate(rows.map((r) => r.readTable(_db.songs)).toList());
  }

  Future<Map<String, int>> rowIdsByIdentityKeys(Set<String> keys) async {
    if (keys.isEmpty) {
      return const {};
    }
    final rows = await (_db.select(_db.songs)..limit(5000)).get();
    final out = <String, int>{};
    for (final r in rows) {
      final key = r.source == IngestSource.mediastore.name
          ? 'ms:${r.mediaStoreId}'
          : 'h:${r.contentHash}';
      if (keys.contains(key)) {
        out[key] = r.id;
      }
    }
    return out;
  }

  /// Increments play_count and stamps last_played_at per song. Creates the
  /// stats row when absent.
  Future<void> recordPlayback(List<int> songRowIds, DateTime at) async {
    if (songRowIds.isEmpty) {
      return;
    }
    final millis = at.millisecondsSinceEpoch;
    await _db.batch((b) {
      for (final id in songRowIds) {
        b.customStatement(
          'INSERT INTO song_stats (song_id, play_count, last_played_at) '
          'VALUES (?, 1, ?) '
          'ON CONFLICT(song_id) DO UPDATE SET '
          'play_count = play_count + 1, last_played_at = excluded.last_played_at',
          [id, millis],
        );
      }
    });
  }

  Future<Set<int>> favoritesSongRowIds() async {
    final rows = await (_db.select(
      _db.songStats,
    )..where((tbl) => tbl.isFavorite.equals(true))).get();
    return rows.map((r) => r.songId).toSet();
  }

  Future<int> countCollection(CollectionKind kind) async {
    final stats = _db.songStats;
    switch (kind) {
      case CollectionKind.recentlyAdded:
        final countExp = _db.songs.id.count();
        final row = await (_db.selectOnly(
          _db.songs,
        )..addColumns([countExp])).getSingle();
        return row.read(countExp) ?? 0;
      case CollectionKind.favorites:
        final countExp = stats.songId.count();
        final row =
            await (_db.selectOnly(stats)
                  ..addColumns([countExp])
                  ..where(stats.isFavorite.equals(true)))
                .getSingle();
        return row.read(countExp) ?? 0;
      case CollectionKind.mostPlayed:
        final countExp = stats.songId.count();
        final row =
            await (_db.selectOnly(stats)
                  ..addColumns([countExp])
                  ..where(stats.playCount.isBiggerThanValue(0)))
                .getSingle();
        return row.read(countExp) ?? 0;
      case CollectionKind.recentlyPlayed:
        final countExp = stats.songId.count();
        final row =
            await (_db.selectOnly(stats)
                  ..addColumns([countExp])
                  ..where(stats.lastPlayedAt.isNotNull()))
                .getSingle();
        return row.read(countExp) ?? 0;
    }
  }
}

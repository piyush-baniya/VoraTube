import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/ingest/ingest_service.dart';
import '../../../core/utils/string_utils.dart';

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

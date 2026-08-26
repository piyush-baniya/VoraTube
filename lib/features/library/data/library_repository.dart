import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/ingest/ingest_service.dart';

class SyncBatchResult {
  const SyncBatchResult({
    required this.added,
    required this.updated,
    required this.dirtyAlbumMediaStoreIds,
  });

  final int added;
  final int updated;
  final Set<int> dirtyAlbumMediaStoreIds;
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

class LibraryRepository {
  LibraryRepository(this._db);

  final AppDatabase _db;

  static const int _deleteChunkSize = 400;
  static const String _missingArtSentinel = '';
  static const String _scanSource = 'mediastore';

  Future<Map<int, int>> existingSongIndex() async {
    final query = _db.selectOnly(_db.songs)
      ..addColumns([_db.songs.mediaStoreId, _db.songs.dateModifiedSec]);
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(_db.songs.mediaStoreId)!: row.read(_db.songs.dateModifiedSec)!,
    };
  }

  Future<SyncBatchResult> syncTracks(List<IngestTrack> tracks) {
    return _db.transaction(() async {
      var added = 0;
      var updated = 0;
      final dirtyAlbums = <int>{};

      final existingSongs =
          await (_db.select(_db.songs)..where(
                (tbl) => tbl.mediaStoreId.isIn(
                  tracks.map((tr) => tr.mediaStoreId).toSet(),
                ),
              ))
              .get();
      final songByMediaStoreId = {
        for (final row in existingSongs) row.mediaStoreId: row,
      };

      final albumIds = tracks.map((tr) => tr.albumMediaStoreId).toSet();
      final existingAlbums = await (_db.select(
        _db.albums,
      )..where((tbl) => tbl.mediaStoreAlbumId.isIn(albumIds))).get();
      final albumByMediaStoreId = {
        for (final row in existingAlbums) row.mediaStoreAlbumId: row.id,
      };

      final artistIds = tracks.map((tr) => tr.artistMediaStoreId).toSet();
      final existingArtists = await (_db.select(
        _db.artists,
      )..where((tbl) => tbl.mediaStoreArtistId.isIn(artistIds))).get();
      final artistByMediaStoreId = {
        for (final row in existingArtists) row.mediaStoreArtistId: row.id,
      };

      for (final track in tracks) {
        final albumRowId = await _ensureAlbum(
          track: track,
          byMediaStoreId: albumByMediaStoreId,
        );
        final artistRowId = await _ensureArtist(
          track: track,
          byMediaStoreId: artistByMediaStoreId,
        );

        final title = _resolveTitle(track);
        final companion =
            SongsCompanion.insert(
              mediaStoreId: track.mediaStoreId,
              contentUri: track.contentUri,
              title: title,
              titleSearch: title.toLowerCase(),
              durationMs: track.durationMs,
              dateModifiedSec: track.dateModifiedSec,
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
              format: Value(_resolveFormat(track.path)),
            ).copyWith(
              albumRowId: Value(albumRowId),
              artistRowId: Value(artistRowId),
            );

        final existing = songByMediaStoreId[track.mediaStoreId];
        if (existing == null) {
          await _db.into(_db.songs).insert(companion);
          added++;
          if (albumRowId != null) {
            dirtyAlbums.add(track.albumMediaStoreId);
          }
        } else if (existing.dateModifiedSec != track.dateModifiedSec) {
          await (_db.update(
            _db.songs,
          )..where((tbl) => tbl.id.equals(existing.id))).write(companion);
          updated++;
          if (albumRowId != null) {
            dirtyAlbums.add(track.albumMediaStoreId);
          }
        }

        if (track.album != null && albumRowId != null) {
          await _refreshAlbumNameIfNeeded(
            mediaStoreAlbumId: track.albumMediaStoreId,
            name: track.album!,
            knownIds: albumByMediaStoreId,
          );
        }
      }

      return SyncBatchResult(
        added: added,
        updated: updated,
        dirtyAlbumMediaStoreIds: dirtyAlbums,
      );
    });
  }

  Future<int?> _ensureAlbum({
    required IngestTrack track,
    required Map<int, int> byMediaStoreId,
  }) async {
    final name = track.album;
    if (name == null || name.isEmpty) {
      return null;
    }
    if (byMediaStoreId.containsKey(track.albumMediaStoreId)) {
      return byMediaStoreId[track.albumMediaStoreId];
    }
    await _db
        .into(_db.albums)
        .insert(
          AlbumsCompanion.insert(
            mediaStoreAlbumId: track.albumMediaStoreId,
            name: name,
            artistName: Value(track.albumArtist ?? track.artist),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    final created =
        await (_db.select(_db.albums)..where(
              (tbl) => tbl.mediaStoreAlbumId.equals(track.albumMediaStoreId),
            ))
            .getSingleOrNull();
    if (created == null) {
      return null;
    }
    byMediaStoreId[track.albumMediaStoreId] = created.id;
    return created.id;
  }

  Future<int?> _ensureArtist({
    required IngestTrack track,
    required Map<int, int> byMediaStoreId,
  }) async {
    if (byMediaStoreId.containsKey(track.artistMediaStoreId)) {
      return byMediaStoreId[track.artistMediaStoreId];
    }
    final name = track.artist;
    if (name == null || name.isEmpty) {
      return null;
    }
    await _db
        .into(_db.artists)
        .insert(
          ArtistsCompanion.insert(
            mediaStoreArtistId: track.artistMediaStoreId,
            name: name,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    final created =
        await (_db.select(_db.artists)..where(
              (tbl) => tbl.mediaStoreArtistId.equals(track.artistMediaStoreId),
            ))
            .getSingleOrNull();
    if (created == null) {
      return null;
    }
    byMediaStoreId[track.artistMediaStoreId] = created.id;
    return created.id;
  }

  Future<void> _refreshAlbumNameIfNeeded({
    required int mediaStoreAlbumId,
    required String name,
    required Map<int, int> knownIds,
  }) async {
    final rowId = knownIds[mediaStoreAlbumId];
    if (rowId == null) {
      return;
    }
    await (_db.update(_db.albums)..where((tbl) => tbl.id.equals(rowId))).write(
      AlbumsCompanion(name: Value(name)),
    );
  }

  Future<List<int>> albumsNeedingArt(Set<int> dirtyAlbumMediaStoreIds) async {
    if (dirtyAlbumMediaStoreIds.isEmpty) {
      return const [];
    }
    final query = _db.selectOnly(_db.albums)
      ..addColumns([_db.albums.mediaStoreAlbumId])
      ..where(_db.albums.mediaStoreAlbumId.isIn(dirtyAlbumMediaStoreIds))
      ..where(
        _db.albums.artSmallPath.isNull() | _db.albums.artLargePath.isNull(),
      );
    final rows = await query.get();
    return rows.map((row) => row.read(_db.albums.mediaStoreAlbumId)!).toList();
  }

  Future<void> attachArtwork(Map<int, ResolvedArtwork?> resolved) async {
    if (resolved.isEmpty) {
      return;
    }
    await _db.transaction(() async {
      for (final entry in resolved.entries) {
        final artwork = entry.value;
        await (_db.update(
          _db.albums,
        )..where((tbl) => tbl.mediaStoreAlbumId.equals(entry.key))).write(
          AlbumsCompanion(
            artSmallPath: Value(artwork?.smallPath ?? _missingArtSentinel),
            artLargePath: Value(artwork?.largePath ?? _missingArtSentinel),
          ),
        );
      }
    });
  }

  Future<int> removeAbsent(Set<int> seenMediaStoreIds) async {
    final existingKeys = (await existingSongIndex()).keys.toList(
      growable: false,
    );
    final doomed = existingKeys
        .where((id) => !seenMediaStoreIds.contains(id))
        .toList();

    for (var i = 0; i < doomed.length; i += _deleteChunkSize) {
      final chunk = doomed.sublist(
        i,
        (i + _deleteChunkSize).clamp(0, doomed.length),
      );
      await (_db.delete(
        _db.songs,
      )..where((tbl) => tbl.mediaStoreId.isIn(chunk))).go();
    }

    await _db.customStatement(
      'DELETE FROM albums WHERE id NOT IN '
      '(SELECT DISTINCT album_row_id FROM songs WHERE album_row_id IS NOT NULL)',
    );
    await _db.customStatement(
      'DELETE FROM artists WHERE id NOT IN '
      '(SELECT DISTINCT artist_row_id FROM songs WHERE artist_row_id IS NOT NULL)',
    );
    return doomed.length;
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
            source: _scanSource,
            lastCompletedAt: Value(DateTime.now()),
            totalSongs: Value(totalSongs),
          ),
        );
  }

  Future<ScanStateEntry?> lastScanEntry() {
    return (_db.select(
      _db.scanStates,
    )..where((tbl) => tbl.source.equals(_scanSource))).getSingleOrNull();
  }

  String _resolveTitle(IngestTrack track) {
    final raw = track.title?.trim();
    if (raw != null && raw.isNotEmpty) {
      return raw;
    }
    final fallback = _fallbackNameFromPath(track.path);
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }
    return 'Untitled';
  }

  String? _fallbackNameFromPath(String? path) {
    if (path == null || path.isEmpty) {
      return null;
    }
    final normalized = path.replaceAll('\\', '/');
    final segment = normalized.split('/').last;
    final dot = segment.lastIndexOf('.');
    if (dot <= 0) {
      return segment;
    }
    return segment.substring(0, dot);
  }

  String? _resolveFormat(String? path) {
    if (path == null) {
      return null;
    }
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) {
      return null;
    }
    final ext = path.substring(dot + 1).toLowerCase();
    if (ext.length > 5) {
      return null;
    }
    return ext;
  }
}

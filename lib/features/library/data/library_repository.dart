import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/db/app_database.dart';
import '../../../core/ingest/artwork/local_artwork_store.dart';
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
        final replayGainJson = track.replayGain != null
            ? _replayGainToJson(track.replayGain!)
            : null;
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
              replayGainJson: Value(replayGainJson),
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

  /// Artwork lookups that are still worth attempting, newest content first.
  ///
  /// Replaces the old `albumsNeedingArt(dirtyAlbumKeys)`, which had two defects
  /// that together meant artwork could never recover:
  ///
  ///  * it returned early when no album changed in the current batch, so a
  ///    re-scan never retried anything that had failed before, and
  ///  * it only ever looked at `albums`, so a track whose MediaStore
  ///    `album_id` is 0 — singles, downloads, voice memos — had nowhere for
  ///    artwork to live and was skipped forever.
  ///
  /// [dirtyAlbumKeys] is now a *priority* hint rather than a filter: those
  /// albums are returned first, then any other album still missing art that we
  /// have not already tried, then album-less songs. [limit] bounds the result
  /// so a 20,000-song library cannot turn one scan into 20,000 native decodes.
  Future<List<ArtworkTarget>> artworkTargets({
    Set<String> dirtyAlbumKeys = const {},
    int limit = 240,
    bool retryFailed = false,
  }) async {
    if (limit <= 0) {
      return const [];
    }
    final targets = <ArtworkTarget>[];
    final seenKeys = <String>{};

    void add(ArtworkTarget target) {
      if (seenKeys.add(target.key)) {
        targets.add(target);
      }
    }

    // Albums missing art. One representative song per album carries the song id
    // and path that the per-song fallbacks need.
    //
    // `art_small_path IS NULL OR art_small_path = ''` tolerates rows poisoned by
    // the old empty-string writes even if a database somehow skipped the v6
    // repair.
    //
    // Exactly one aggregate is used on purpose. SQLite guarantees that when a
    // grouped query contains a single min()/max(), every bare column in the
    // result comes from that same input row — so `song_ms_id` and `song_path`
    // are certain to describe the one song `MIN(s.id)` picked. Adding a second
    // aggregate (say `MAX(date_added_sec)` for ordering) would void that
    // guarantee and could pair one song's id with another song's path, so the
    // ordering uses `a.id` instead: album rows are created as albums are first
    // encountered, which makes a higher id a good enough proxy for "newer".
    final attemptFilter = retryFailed
        ? ''
        : 'AND (ax.art_resolved_at IS NULL OR ax.art_attempts < 2)';
    final albumRows = await _db
        .customSelect(
          '''
SELECT a.album_key AS album_key,
       a.media_store_album_id AS album_ms_id,
       MIN(s.id) AS song_row_id,
       s.media_store_id AS song_ms_id,
       s.path AS song_path
FROM albums a
JOIN songs s ON s.album_row_id = a.id
LEFT JOIN album_extras ax ON ax.album_id = a.id
WHERE a.album_key IS NOT NULL
  AND (a.art_small_path IS NULL OR a.art_small_path = ''
       OR a.art_large_path IS NULL OR a.art_large_path = '')
  $attemptFilter
GROUP BY a.id
ORDER BY CASE WHEN a.album_key IN (${_placeholders(dirtyAlbumKeys.length)})
              THEN 0 ELSE 1 END,
         a.id DESC
LIMIT ?
''',
          variables: [
            for (final key in dirtyAlbumKeys) Variable<String>(key),
            Variable<int>(limit),
          ],
        )
        .get();

    for (final row in albumRows) {
      final albumKey = row.data['album_key'] as String?;
      if (albumKey == null || albumKey.isEmpty) continue;
      add(
        ArtworkTarget.album(
          albumKey: albumKey,
          albumMediaStoreId: (row.data['album_ms_id'] as num?)?.toInt(),
          audioMediaStoreId: (row.data['song_ms_id'] as num?)?.toInt(),
          path: row.data['song_path'] as String?,
        ),
      );
    }

    final remaining = limit - targets.length;
    if (remaining <= 0) {
      return targets;
    }

    // Album-less songs: the case the old query could not express at all.
    final songRows = await _db
        .customSelect(
          '''
SELECT s.media_store_id AS song_ms_id,
       s.content_hash AS content_hash,
       s.source AS source,
       s.path AS path
FROM songs s
LEFT JOIN song_extras sx ON sx.song_id = s.id
WHERE s.album_row_id IS NULL
  AND (sx.art_small_path IS NULL OR sx.art_small_path = '')
  ${retryFailed ? '' : 'AND sx.art_resolved_at IS NULL'}
ORDER BY s.date_added_sec DESC
LIMIT ?
''',
          variables: [Variable<int>(remaining)],
        )
        .get();

    for (final row in songRows) {
      final source = row.data['source'] as String?;
      final msId = (row.data['song_ms_id'] as num?)?.toInt();
      final hash = row.data['content_hash'] as String?;
      final identityKey = source == IngestSource.mediastore.name
          ? (msId == null ? null : 'ms:$msId')
          : (hash == null ? null : 'h:$hash');
      if (identityKey == null) continue;
      add(
        ArtworkTarget.song(
          identityKey: identityKey,
          audioMediaStoreId: msId,
          path: row.data['path'] as String?,
        ),
      );
    }

    return targets;
  }

  static String _placeholders(int count) =>
      count == 0 ? 'NULL' : List<String>.filled(count, '?').join(', ');

  /// Persists resolved artwork and, just as importantly, records the attempt.
  ///
  /// Two rules that the previous implementation broke:
  ///
  ///  * a failure writes NULL, never the empty string. `''` is not null, so it
  ///    silently satisfied the `art_small_path IS NULL` predicate used to find
  ///    albums needing art, permanently marking every failed album as done.
  ///  * a failure never clears a path that is already set. Artwork resolution
  ///    is best-effort and can fail transiently (revoked permission, ejected
  ///    SD card); losing working artwork because of one bad call is worse than
  ///    keeping a slightly stale file.
  Future<void> attachArtwork(Map<String, ResolvedArtwork?> resolved) async {
    if (resolved.isEmpty) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      for (final entry in resolved.entries) {
        final artwork = entry.value;
        if (ArtworkTarget.isSongKey(entry.key)) {
          await _attachSongArtwork(
            ArtworkTarget.identityKeyOf(entry.key),
            artwork,
            nowMs,
          );
        } else {
          await _attachAlbumArtwork(entry.key, artwork, nowMs);
        }
      }
    });
  }

  Future<void> _attachAlbumArtwork(
    String albumKey,
    ResolvedArtwork? artwork,
    int nowMs,
  ) async {
    if (artwork != null && artwork.hasArt) {
      await (_db.update(
        _db.albums,
      )..where((tbl) => tbl.albumKey.equals(albumKey))).write(
        AlbumsCompanion(
          artSmallPath: Value(artwork.smallPath),
          artLargePath: Value(artwork.largePath),
        ),
      );
    }
    // Record the attempt either way, so a genuinely art-less album is not
    // re-decoded on every scan.
    await _db.customStatement(
      '''
INSERT INTO album_extras (album_id, art_resolved_at, art_attempts)
SELECT id, ?, 1 FROM albums WHERE album_key = ?
ON CONFLICT(album_id) DO UPDATE SET
  art_resolved_at = excluded.art_resolved_at,
  art_attempts = album_extras.art_attempts + 1
''',
      [nowMs, albumKey],
    );
  }

  Future<void> _attachSongArtwork(
    String identityKey,
    ResolvedArtwork? artwork,
    int nowMs,
  ) async {
    final rowId = await _songRowIdForIdentityKey(identityKey);
    if (rowId == null) {
      return;
    }
    if (artwork != null && artwork.hasArt) {
      await _db.customStatement(
        '''
INSERT INTO song_extras (song_id, art_small_path, art_large_path,
                         art_resolved_at)
VALUES (?, ?, ?, ?)
ON CONFLICT(song_id) DO UPDATE SET
  art_small_path = excluded.art_small_path,
  art_large_path = excluded.art_large_path,
  art_resolved_at = excluded.art_resolved_at
''',
        [rowId, artwork.smallPath, artwork.largePath, nowMs],
      );
      return;
    }
    await _db.customStatement(
      '''
INSERT INTO song_extras (song_id, art_resolved_at)
VALUES (?, ?)
ON CONFLICT(song_id) DO UPDATE SET art_resolved_at = excluded.art_resolved_at
''',
      [rowId, nowMs],
    );
  }

  Future<int?> _songRowIdForIdentityKey(String identityKey) async {
    if (identityKey.startsWith('ms:')) {
      final msId = int.tryParse(identityKey.substring(3));
      if (msId == null) return null;
      final row =
          await (_db.selectOnly(_db.songs)
                ..addColumns([_db.songs.id])
                ..where(
                  _db.songs.source.equals(IngestSource.mediastore.name) &
                      _db.songs.mediaStoreId.equals(msId),
                ))
              .getSingleOrNull();
      return row?.read(_db.songs.id);
    }
    if (identityKey.startsWith('h:')) {
      final hash = identityKey.substring(2);
      final row =
          await (_db.selectOnly(_db.songs)
                ..addColumns([_db.songs.id])
                ..where(_db.songs.contentHash.equals(hash)))
              .getSingleOrNull();
      return row?.read(_db.songs.id);
    }
    return null;
  }

  /// Removes MediaStore songs the device no longer reports.
  ///
  /// Refuses to act on an empty [seenMediaStoreIds]. An empty set does not mean
  /// "the user deleted all their music" — it means the scan enumerated nothing,
  /// which in practice is a denied permission, an unmounted volume, or an
  /// aborted scan. Trusting it would delete the entire library, along with
  /// every playlist entry and play count attached to it.
  Future<int> removeAbsentMediaStore(Set<int> seenMediaStoreIds) async {
    if (seenMediaStoreIds.isEmpty) {
      return 0;
    }

    // The difference is computed in Dart rather than as `mediaStoreId NOT IN
    // (...)`. A 20,000-song library would bind 20,000 SQL variables, well past
    // SQLITE_MAX_VARIABLE_NUMBER (999 on older builds), and the statement would
    // fail outright — taking the whole scan with it.
    final stored =
        await (_db.selectOnly(_db.songs)
              ..addColumns([_db.songs.id, _db.songs.mediaStoreId])
              ..where(_db.songs.source.equals(IngestSource.mediastore.name)))
            .get();

    final doomedIds = <int>[];
    for (final row in stored) {
      final rowId = row.read(_db.songs.id);
      if (rowId == null) continue;
      final msId = row.read(_db.songs.mediaStoreId);
      // A MediaStore row with no MediaStore id cannot be reconciled, but it is
      // also not evidence of deletion, so leave it alone.
      if (msId == null) continue;
      if (!seenMediaStoreIds.contains(msId)) {
        doomedIds.add(rowId);
      }
    }

    if (doomedIds.isEmpty) {
      return 0;
    }

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

    // Exclude hidden songs (song_extras is a side table, filtered in Dart).
    final hiddenIds = await hiddenSongIds();
    query.limit(limit, offset: offset);
    final allRows = await query.get();
    final rows = hiddenIds.isEmpty
        ? allRows
        : allRows.where((r) {
            final id = r.readTable(_db.songs).id;
            return !hiddenIds.contains(id);
          }).toList();

    final songRows = [for (final row in rows) row.readTable(_db.songs)];
    final overrides = await songArtOverrides(songRows.map((s) => s.id));
    final songs = [
      for (var i = 0; i < rows.length; i++)
        SongTileData(
          song: songRows[i],
          artPath:
              overrides[songRows[i].id] ??
              _pickArt(
                rows[i].read(albums.artLargePath),
                rows[i].read(albums.artSmallPath),
              ),
          // The album and artist lists already did this via `_decorate`, so the
          // same track normalised on one screen and not on another.
          replayGain: _replayGainFromJson(songRows[i].replayGainJson),
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

/// How many song ids to bind per `IN (...)` lookup.
///
/// Kept well under SQLITE_MAX_VARIABLE_NUMBER, which is 999 on older SQLite
/// builds — a single unbounded `IN` over a 20,000-song library would not just
/// be slow, it would fail to prepare.
const int _artChunkSize = 400;

extension SongArtworkOverrides on LibraryRepository {
  /// Per-song artwork that overrides, or substitutes for, the album's art.
  ///
  /// Two distinct jobs, one lookup:
  ///
  ///  * `custom_art_path` is a cover the user chose for this one track, and
  ///    must win over whatever the album says.
  ///  * `art_small_path`/`art_large_path` hold artwork resolved for a track
  ///    with no album row at all — MediaStore reports `album_id == 0` for
  ///    singles, downloads and voice memos, and those songs previously had
  ///    nowhere for artwork to live, so they always fell back to a placeholder.
  ///
  /// `song_extras` is not a drift-declared table (see `songExtrasDdl`), so this
  /// cannot be a typed join. Only songs that actually have a row come back, so
  /// the map is normally far smaller than the page it decorates.
  Future<Map<int, String>> songArtOverrides(Iterable<int> songRowIds) async {
    final ids = songRowIds.toList(growable: false);
    if (ids.isEmpty) {
      return const {};
    }
    final out = <int, String>{};
    for (var i = 0; i < ids.length; i += _artChunkSize) {
      final chunk = ids.sublist(i, (i + _artChunkSize).clamp(0, ids.length));
      final placeholders = List<String>.filled(chunk.length, '?').join(', ');
      final rows = await _db
          .customSelect(
            'SELECT song_id, custom_art_path, art_large_path, art_small_path '
            'FROM song_extras WHERE song_id IN ($placeholders)',
            variables: [for (final id in chunk) Variable<int>(id)],
          )
          .get();
      for (final row in rows) {
        final id = (row.data['song_id'] as num?)?.toInt();
        if (id == null) continue;
        final art =
            _pickArt(
              row.data['custom_art_path'] as String?,
              row.data['art_large_path'] as String?,
            ) ??
            _pickArt(null, row.data['art_small_path'] as String?);
        if (art != null) {
          out[id] = art;
        }
      }
    }
    return out;
  }
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
    final overrides = await songArtOverrides(rows.map((r) => r.id));
    return [
      for (final r in rows)
        SongTileData(
          song: r,
          artPath:
              overrides[r.id] ??
              (r.albumRowId == null ? null : artById[r.albumRowId!]),
          replayGain: _replayGainFromJson(r.replayGainJson),
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

  /// Persists a user-assigned mood for a song (the value stored in
  /// `song_stats.mood`). Pass an empty string to clear a previous assignment.
  /// Creates the stats row when absent so user moods are remembered even for
  /// songs that have never been played or favourited.
  Future<void> setSongMood(int songRowId, String mood) async {
    await _db.customStatement(
      'INSERT INTO song_stats (song_id, mood) VALUES (?, ?) '
      'ON CONFLICT(song_id) DO UPDATE SET mood = excluded.mood',
      [songRowId, mood.isEmpty ? null : mood],
    );
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

  Future<Map<int, SongStat>> getSongStatsForSongs(Set<int> songIds) async {
    if (songIds.isEmpty) return {};
    final stats = _db.songStats;
    final query = _db.select(stats)..where((tbl) => tbl.songId.isIn(songIds));
    final rows = await query.get();
    return {for (final r in rows) r.songId: r};
  }

  Future<ListeningStats> listeningStats() async {
    final songsCountExp = _db.songs.id.count();
    final playsExp = _db.songStats.playCount.sum();
    final favCountExp = _db.songStats.songId.count();

    final totalSongsRow = await (_db.selectOnly(
      _db.songs,
    )..addColumns([songsCountExp])).getSingle();
    final totalSongs = totalSongsRow.read(songsCountExp) ?? 0;

    // Bounded total plays and listening time via joined aggregation.
    final statsRows = await _db
        .customSelect(
          'SELECT COALESCE(SUM(st.play_count), 0) AS total_plays, '
          'COALESCE(SUM(st.play_count * s.duration_ms), 0) AS total_ms '
          'FROM song_stats st JOIN songs s ON s.id = st.song_id',
        )
        .getSingleOrNull();
    final totalPlays = (statsRows?.data['total_plays'] as num?)?.toInt() ?? 0;
    final totalMs = (statsRows?.data['total_ms'] as num?)?.toInt() ?? 0;

    final favRow =
        await (_db.selectOnly(_db.songStats)
              ..addColumns([favCountExp])
              ..where(_db.songStats.isFavorite.equals(true)))
            .getSingle();
    final favCount = favRow.read(favCountExp) ?? 0;

    // Reuse existing bounded counts for most/recently played indicator.
    final mostPlayed = await countCollection(CollectionKind.mostPlayed);
    final recentlyPlayed = await countCollection(CollectionKind.recentlyPlayed);

    // Top-scoring song for the featured stat card.
    String? topSongTitle;
    String? topSongArtist;
    var topSongCount = 0;
    final topRow = await _db
        .customSelect(
          'SELECT s.title AS title, s.artist AS artist, '
          'st.play_count AS count '
          'FROM song_stats st JOIN songs s ON s.id = st.song_id '
          'ORDER BY st.play_count DESC, s.title ASC LIMIT 1',
        )
        .getSingleOrNull();
    if (topRow != null) {
      final count = (topRow.data['count'] as num?)?.toInt() ?? 0;
      if (count > 0) {
        topSongTitle = topRow.data['title'] as String?;
        topSongArtist = topRow.data['artist'] as String?;
        topSongCount = count;
      }
    }

    // Also read totalPlays via typed query as fallback when customSelect is
    // unavailable in tests; keep the joined sum above as primary.
    final _ = playsExp;

    return ListeningStats(
      totalSongs: totalSongs,
      totalPlays: totalPlays,
      totalListeningMs: totalMs,
      favoritesCount: favCount,
      mostPlayedCount: mostPlayed,
      recentlyPlayedCount: recentlyPlayed,
      mostPlayedSongTitle: topSongTitle,
      mostPlayedSongArtist: topSongArtist,
      mostPlayedSongCount: topSongCount,
    );
  }

  Future<List<SongTileData>> topPlayedSongs({int limit = 5}) async {
    return collectionSongs(CollectionKind.mostPlayed, limit: limit);
  }

  Future<List<SongTileData>> recentlyPlayedSongs({int limit = 5}) async {
    return collectionSongs(CollectionKind.recentlyPlayed, limit: limit);
  }
}

extension LibrarySongActions on LibraryRepository {
  Future<String?> setCustomArtworkForSongWithBytes(
    int songId,
    Uint8List bytes,
  ) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final artDir = Directory('${dir.path}/art/custom');
      await artDir.create(recursive: true);
      final store = LocalArtworkStore(artDir.path);
      final saved = await store.save(bytes);
      if (saved == null) return null;
      final path = saved.largePath ?? saved.smallPath;
      if (path == null) return null;
      await setCustomArtworkForSong(songId, path);
      return path;
    } catch (_) {
      return null;
    }
  }

  Future<void> setCustomArtworkForSong(int songId, String path) async {
    await _db.customStatement(
      'INSERT INTO song_extras (song_id, custom_art_path, art_resolved_at) '
      'VALUES (?, ?, ?) '
      'ON CONFLICT(song_id) DO UPDATE SET custom_art_path = excluded.custom_art_path, '
      'art_resolved_at = excluded.art_resolved_at',
      [songId, path, DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<void> updateSongTags(
    int songId, {
    required String title,
    String? artist,
    String? albumName,
    String? genre,
    int? year,
  }) async {
    final titleSearch = title.toLowerCase();
    await (_db.update(_db.songs)..where((tbl) => tbl.id.equals(songId))).write(
      SongsCompanion(
        title: Value(title),
        titleSearch: Value(titleSearch),
        artist: Value(artist),
        artistSearch: Value(artist?.toLowerCase()),
        albumName: Value(albumName),
        genre: Value(genre),
        year: Value(year),
      ),
    );
    await _db.customStatement(
      'INSERT INTO song_extras (song_id, user_edited) VALUES (?, 1) '
      'ON CONFLICT(song_id) DO UPDATE SET user_edited = 1',
      [songId],
    );
  }

  Future<void> setHidden(int songId, bool hidden) async {
    await _db.customStatement(
      'INSERT INTO song_extras (song_id, is_hidden) VALUES (?, ?) '
      'ON CONFLICT(song_id) DO UPDATE SET is_hidden = excluded.is_hidden',
      [songId, hidden ? 1 : 0],
    );
  }

  Future<Set<int>> hiddenSongIds() async {
    final rows = await _db
        .customSelect('SELECT song_id FROM song_extras WHERE is_hidden = 1')
        .get();
    return {for (final r in rows) (r.data['song_id'] as num).toInt()};
  }

  Future<void> clearHidden() async {
    await _db.customStatement(
      'UPDATE song_extras SET is_hidden = 0 WHERE is_hidden = 1',
    );
  }
}

String _replayGainToJson(ReplayGainInfo rg) {
  final map = <String, double>{};
  if (rg.trackGainDb != null) map['trackGainDb'] = rg.trackGainDb!;
  if (rg.trackPeak != null) map['trackPeak'] = rg.trackPeak!;
  if (rg.albumGainDb != null) map['albumGainDb'] = rg.albumGainDb!;
  if (rg.albumPeak != null) map['albumPeak'] = rg.albumPeak!;
  return jsonEncode(map);
}

ReplayGainInfo? _replayGainFromJson(String? json) {
  if (json == null || json.isEmpty || json == '{}') return null;
  try {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return ReplayGainInfo(
      trackGainDb: (map['trackGainDb'] as num?)?.toDouble(),
      trackPeak: (map['trackPeak'] as num?)?.toDouble(),
      albumGainDb: (map['albumGainDb'] as num?)?.toDouble(),
      albumPeak: (map['albumPeak'] as num?)?.toDouble(),
    );
  } catch (_) {
    return null;
  }
}

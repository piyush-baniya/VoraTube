import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/db/app_database.dart';
import '../../../core/ingest/artwork/local_artwork_store.dart';
import '../../../core/ingest/ingest_service.dart';
import '../../../core/player/player_controller.dart';
import '../../../core/utils/string_utils.dart';
import '../../search/data/search_rank.dart';
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

      // Artist rows keyed by their stable key, so split-out "feat." credits
      // collide on the same row within this batch.
      final creditedArtistRowIdByKey = <String, int>{};

      for (final track in tracks) {
        final albumRowId = await _ensureAlbum(
          track: track,
          rowIdByKey: albumRowIdByKey,
        );
        // Split "Artist A feat. Artist B" into its individual credits. The
        // first entry stays the primary artist (back-compat via
        // `songs.artistRowId`), the rest are recorded in `song_artists`.
        final credits = splitArtists(track.artist);
        final rawCredit = track.artist?.trim();
        // BUG #5: a grouped credit ("Atif Aslam, Pritam") must NOT bind the
        // song's primary artist to the MediaStore *combined* artist key —
        // that row would be created/renamed after the first credit and
        // duplicate the real individual artist entry. Resolve the primary
        // through the name-keyed credited-artist path instead, which unifies
        // with the existing solo artist row by name.
        final isGroupCredit = rawCredit != null && hasGroupSeparator(rawCredit);
        final int? artistRowId;
        if (isGroupCredit && credits.isNotEmpty) {
          artistRowId = await _ensureCreditedArtist(
            credits.first,
            rowIdByKey: creditedArtistRowIdByKey,
          );
        } else {
          artistRowId = await _ensureArtist(
            track: track,
            rowIdByKey: artistRowIdByKey,
            artistName: credits.isNotEmpty ? credits.first : rawCredit,
          );
        }
        final creditedRowIds = <int>{?artistRowId};
        for (final name in credits.skip(1)) {
          final rowId = await _ensureCreditedArtist(
            name,
            rowIdByKey: creditedArtistRowIdByKey,
          );
          if (rowId != null) {
            creditedRowIds.add(rowId);
          }
        }
        // The combined credit as written in the tag ("Atif Aslam, Pritam")
        // also becomes its own artist entry, so grouped-credit pages exist
        // alongside the individual ones without duplicating any song: the
        // song_artists rows for this song are a set keyed by artist row id.
        if (rawCredit != null &&
            hasGroupSeparator(rawCredit) &&
            !credits.contains(rawCredit)) {
          final rawRowId = await _ensureCreditedArtist(
            rawCredit,
            rowIdByKey: creditedArtistRowIdByKey,
          );
          if (rawRowId != null) {
            creditedRowIds.add(rawRowId);
          }
        }

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
        // The song row id the credits below attach to. Insert returns the new
        // id; an existing row (added, updated, or untouched) keeps its own.
        final int songRowId;
        if (existing == null) {
          songRowId = await _db.into(_db.songs).insert(companion);
          added++;
          if (albumRowId != null && track.albumKey != null) {
            dirtyAlbums.add(track.albumKey!);
          }
        } else {
          songRowId = existing.id;
          // BUG #5: also converge the primary artist when a rescan resolves a
          // different (corrected) artist row — pre-fix rows may point at a
          // stale combined-credit artist row. Unchanged tracks previously
          // kept their old artist_row_id forever.
          if (existing.dateModifiedSec != track.dateModifiedSec ||
              existing.artistRowId != artistRowId) {
            await (_db.update(
              _db.songs,
            )..where((tbl) => tbl.id.equals(existing.id))).write(companion);
            updated++;
            if (albumRowId != null && track.albumKey != null) {
              dirtyAlbums.add(track.albumKey!);
            }
          }
        }

        // Record every credit (primary + featured) so artist pages count and
        // list songs correctly. Unchanged tracks are re-written here too, so
        // songs ingested before this split existed converge on the next scan.
        await _writeSongArtists(songRowId, creditedRowIds);

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
    String? artistName,
  }) async {
    final key = track.artistKey;
    if (key == null || key.isEmpty) {
      return null;
    }
    if (rowIdByKey.containsKey(key)) {
      return rowIdByKey[key];
    }
    final name = artistName?.trim() ?? track.artist?.trim();
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

  /// Stable key for a split-out credited artist that has no MediaStore ID.
  ///
  /// The 'c:' prefix distinguishes these rows from platform keys (`ms:`, `n:`)
  /// and the lowercase hashing makes "A feat. Bob" and "A feat. BOB" collide
  /// on the same artist row.
  String creditedArtistKey(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final digest = sha1.convert(utf8.encode(trimmed.toLowerCase()));
    return 'c:$digest';
  }

  Future<int?> _ensureCreditedArtist(
    String name, {
    required Map<String, int> rowIdByKey,
  }) async {
    final key = creditedArtistKey(name);
    if (key.isEmpty) {
      return null;
    }
    if (rowIdByKey.containsKey(key)) {
      return rowIdByKey[key];
    }
    // BUG #5: unify with an existing artist row that carries the same name
    // BEFORE inserting — "Atif Aslam" credited on a group track must be the
    // SAME artist entry as the solo MediaStore-keyed "Atif Aslam" row, so the
    // artist list never shows duplicate entries for one artist. The matched
    // row keeps its own (platform) key; nothing is rewritten on it.
    final nameMatch =
        await (_db.select(_db.artists)
              ..where(
                (tbl) => tbl.name.lower().equals(name.trim().toLowerCase()),
              )
              ..limit(1))
            .getSingleOrNull();
    if (nameMatch != null) {
      rowIdByKey[key] = nameMatch.id;
      return nameMatch.id;
    }
    await _db
        .into(_db.artists)
        .insert(
          ArtistsCompanion.insert(name: name, artistKey: Value(key)),
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

  /// Replaces the [song_artists] rows for one song with [creditedRowIds].
  ///
  /// Delete-then-insert keeps a song's credits authoritative — an updated tag
  /// that drops a feat. no longer leaves a stale row behind. Unchanged songs
  /// re-written here is what lets tracks ingested before this table existed
  /// converge on subsequent scans.
  Future<void> _writeSongArtists(int songId, Set<int> creditedRowIds) async {
    await _db.customStatement('DELETE FROM song_artists WHERE song_id = ?', [
      songId,
    ]);
    var position = 0;
    for (final artistId in creditedRowIds) {
      await _db.customStatement(
        'INSERT OR IGNORE INTO song_artists (song_id, artist_id, position) '
        'VALUES (?, ?, ?)',
        [songId, artistId, position],
      );
      position++;
    }
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
  /// have not already tried, then album-less songs, then songs inside albums
  /// that have no per-song artwork yet. Resolving the last group is what lets
  /// lists show each track's own embedded artwork (album detail, artist, genre,
  /// collections) instead of every row repeating the shared album art. [limit]
  /// bounds the result so a 20,000-song library cannot turn one scan into
  /// 20,000 native decodes.
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

    final remainingAfterAlbumLess = limit - targets.length;
    if (remainingAfterAlbumLess <= 0) {
      return targets;
    }

    // Songs inside an album that still lack per-song artwork. The album above
    // covers their display fallback, but resolving the track's own embedded
    // art (cached in song_extras) lets detail lists show distinct per-song
    // covers. Lower priority than album-less songs since they already have
    // artwork to show.
    final albumSongRows = await _db
        .customSelect(
          '''
SELECT s.media_store_id AS song_ms_id,
       s.content_hash AS content_hash,
       s.source AS source,
       s.path AS path
FROM songs s
LEFT JOIN song_extras sx ON sx.song_id = s.id
WHERE s.album_row_id IS NOT NULL
  AND (sx.art_small_path IS NULL OR sx.art_small_path = '')
  ${retryFailed ? '' : 'AND sx.art_resolved_at IS NULL'}
ORDER BY s.date_added_sec DESC
LIMIT ?
''',
          variables: [Variable<int>(remainingAfterAlbumLess)],
        )
        .get();

    for (final row in albumSongRows) {
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
      '(SELECT DISTINCT artist_row_id FROM songs WHERE artist_row_id IS NOT NULL) '
      'AND id NOT IN (SELECT DISTINCT artist_id FROM song_artists)',
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

  /// Songs whose genre tag is absent or empty — candidates for genre
  /// enrichment. Bounded by [limit] so the background pass stays cheap.
  Future<List<Song>> songsMissingGenre({required int limit}) {
    final where = _db.songs.genre.isNull() | _db.songs.genre.equals('');
    return (_db.select(_db.songs)
          ..where((t) => where)
          ..orderBy([(t) => OrderingTerm.asc(t.id)])
          ..limit(limit))
        .get();
  }

  /// Persists an enriched genre back onto a song row so it becomes part of the
  /// local library metadata and feeds the existing MoodEngine immediately.
  Future<void> setSongGenre(int rowId, String genre) async {
    await (_db.update(_db.songs)..where((tbl) => tbl.id.equals(rowId))).write(
      SongsCompanion(genre: Value(genre)),
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
    // Counts every song an artist is credited on — its own songs via the
    // back-compat `songs.artist_row_id` and featured appearances via
    // `song_artists` — so feat. credits surface in the artist list with
    // accurate numbers. COALESCE + DISTINCT dedups a song credited through
    // both paths (primary artists are also written to `song_artists`).
    final rows = await _db
        .customSelect(
          '''
              SELECT a.id AS id, a.artist_key AS artist_key, a.name AS name,
                COUNT(DISTINCT COALESCE(sa.song_id, s.artist_row_id))
                  AS song_count
              FROM artists a
              LEFT JOIN song_artists sa ON sa.artist_id = a.id
              LEFT JOIN songs s ON s.artist_row_id = a.id
              GROUP BY a.id
              HAVING COUNT(DISTINCT COALESCE(sa.song_id, s.artist_row_id)) > 0
              ORDER BY song_count DESC, a.name COLLATE NOCASE
              LIMIT ?
              ''',
          variables: [Variable<int>(limit)],
        )
        .get();
    return [
      for (final row in rows)
        ArtistSummary(
          artistRowId: row.data['id'] as int,
          key: row.data['artist_key'] as String? ?? '',
          name: row.data['name'] as String,
          songCount: row.data['song_count'] as int? ?? 0,
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

    // A broader candidate pool than the final per-section limit so that
    // relevance ranking (prefix/token/typo) has material to choose from.
    const candidateLimit = 300;

    final songRows =
        await (_db.select(_db.songs)
              ..where((tbl) {
                final phrase =
                    tbl.titleSearch.like(needle) |
                    tbl.artistSearch.like(needle) |
                    tbl.albumName.lower().like(needle);
                var clause = phrase;
                // OR per-token substrings so typo-tolerant fuzzy matching in
                // `tokenFuzzyMatch` has candidates to work with: `%linkn park%`
                // won't select "Linkin Park", but `%park%` does.
                for (final tok in searchTokens(q)) {
                  if (tok.length < 3) continue;
                  final tn = '%$tok%';
                  clause =
                      clause |
                      tbl.titleSearch.like(tn) |
                      tbl.artistSearch.like(tn) |
                      tbl.albumName.lower().like(tn);
                }
                return clause;
              })
              ..limit(candidateLimit))
            .get();

    // Rank songs by relevance, admitting typo-tolerant token matches.
    final rankedSongs = <Song>[];
    final scored = <(Song, int)>[];
    for (final row in songRows) {
      final title = row.title;
      final artist = row.artist ?? '';
      final album = row.albumName ?? '';
      if (!tokenFuzzyMatch(q, '$title $artist $album')) continue;
      scored.add((
        row,
        relevanceScore(query: q, title: title, artist: artist, album: album),
      ));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    rankedSongs.addAll(scored.take(perSectionLimit).map((e) => e.$1));

    final albums = _db.albums;
    final albumNameLower = albums.name.lower();
    Expression<bool> albumClause = albumNameLower.like(needle);
    for (final tok in searchTokens(q)) {
      if (tok.length < 3) continue;
      albumClause = albumClause | albumNameLower.like('%$tok%');
    }
    final albumCandidates =
        await (_db.selectOnly(albums)
              ..addColumns([
                albums.id,
                albums.albumKey,
                albums.name,
                albums.artistName,
                albums.artSmallPath,
                albums.artLargePath,
              ])
              ..where(albumClause)
              ..limit(candidateLimit))
            .get();

    final albumScored =
        <
          ({
            int id,
            String key,
            String name,
            String artist,
            String? small,
            String? large,
            int score,
          })
        >[];
    for (final row in albumCandidates) {
      final name = row.read(albums.name)!;
      final artist = row.read(albums.artistName) ?? '';
      if (!tokenFuzzyMatch(q, '$name $artist')) continue;
      albumScored.add((
        id: row.read(albums.id)!,
        key: row.read(albums.albumKey) ?? '',
        name: name,
        artist: artist,
        small: row.read(albums.artSmallPath),
        large: row.read(albums.artLargePath),
        score: relevanceScore(query: q, title: name, artist: artist, album: ''),
      ));
    }
    albumScored.sort((a, b) => b.score.compareTo(a.score));

    final artists = _db.artists;
    final artistsNameLower = artists.name.lower();
    Expression<bool> artistClause = artistsNameLower.like(needle);
    for (final tok in searchTokens(q)) {
      if (tok.length < 3) continue;
      artistClause = artistClause | artistsNameLower.like('%$tok%');
    }
    final artistCandidates =
        await (_db.selectOnly(artists)
              ..addColumns([artists.id, artists.artistKey, artists.name])
              ..where(artistClause)
              ..limit(candidateLimit))
            .get();

    final artistScored = <({int id, String key, String name, int score})>[];
    for (final row in artistCandidates) {
      final name = row.read(artists.name)!;
      if (!tokenFuzzyMatch(q, name)) continue;
      artistScored.add((
        id: row.read(artists.id)!,
        key: row.read(artists.artistKey) ?? '',
        name: name,
        score: relevanceScore(query: q, title: name, artist: '', album: ''),
      ));
    }
    artistScored.sort((a, b) => b.score.compareTo(a.score));

    final playlistCandidates =
        await (_db.select(_db.playlists)
              ..where((tbl) {
                final nameLower = tbl.name.lower();
                var clause = nameLower.like(needle);
                for (final tok in searchTokens(q)) {
                  if (tok.length < 3) continue;
                  clause = clause | nameLower.like('%$tok%');
                }
                return clause;
              })
              ..limit(candidateLimit))
            .get();

    final playlistScored = <(Playlist, int)>[];
    for (final p in playlistCandidates) {
      if (!tokenFuzzyMatch(q, p.name)) continue;
      playlistScored.add((
        p,
        relevanceScore(query: q, title: p.name, artist: '', album: ''),
      ));
    }
    playlistScored.sort((a, b) => b.$2.compareTo(a.$2));

    // Real per-playlist song counts (the Playlist row itself has no count
    // field). Used by the search UI to subtitle each playlist result.
    final topPlaylists = playlistScored.take(perSectionLimit).toList();
    final playlistCounts = <int, int>{};
    if (topPlaylists.isNotEmpty) {
      final idColumn = _db.playlistSongs.playlistId;
      final countRows =
          await (_db.selectOnly(_db.playlistSongs)
                ..addColumns([idColumn, _db.playlistSongs.songRowId.count()])
                ..where(idColumn.isIn([for (final e in topPlaylists) e.$1.id]))
                ..groupBy([idColumn]))
              .get();
      for (final row in countRows) {
        final id = row.read(idColumn);
        if (id != null) {
          playlistCounts[id] =
              row.read(_db.playlistSongs.songRowId.count()) ?? 0;
        }
      }
    }

    return SearchResults(
      query: q,
      songs: await _decorate(rankedSongs),
      albums: [
        for (final r in albumScored.take(perSectionLimit))
          AlbumSummary(
            albumRowId: r.id,
            key: r.key,
            name: r.name,
            artistName: r.artist,
            artPath: _pickArt(r.large, r.small),
            songCount: 0,
          ),
      ],
      artists: [
        for (final r in artistScored.take(perSectionLimit))
          ArtistSummary(
            artistRowId: r.id,
            key: r.key,
            name: r.name,
            songCount: 0,
          ),
      ],
      playlists: [for (final e in topPlaylists) e.$1],
      playlistCountsById: playlistCounts,
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

  /// Resolves the best artwork path for a single song, mirroring [_decorate]:
  /// a song_extras override (custom art, then per-song resolved art) wins,
  /// otherwise the album's cached art is used. Null when neither is available.
  Future<String?> _resolvedArtPath(int songId, int? albumRowId) async {
    final extras = await _db
        .customSelect(
          'SELECT custom_art_path, art_large_path, art_small_path '
          'FROM song_extras WHERE song_id = ?',
          variables: [Variable<int>(songId)],
        )
        .getSingleOrNull();
    if (extras != null) {
      final override =
          _pickArt(
            extras.data['custom_art_path'] as String?,
            extras.data['art_large_path'] as String?,
          ) ??
          _pickArt(null, extras.data['art_small_path'] as String?);
      if (override != null) return override;
    }
    if (albumRowId == null) return null;
    final album = await (_db.select(
      _db.albums,
    )..where((tbl) => tbl.id.equals(albumRowId))).getSingleOrNull();
    if (album == null) return null;
    return _pickArt(album.artLargePath, album.artSmallPath);
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
    final creditedIds = await _db
        .customSelect(
          'SELECT DISTINCT song_id FROM song_artists WHERE artist_id = ?',
          variables: [Variable<int>(artistRowId)],
        )
        .get();
    final creditedSongIds = <int>{
      for (final row in creditedIds) row.data['song_id'] as int,
    };
    final rows =
        await (_db.select(_db.songs)
              ..where(
                (tbl) =>
                    tbl.artistRowId.equals(artistRowId) |
                    tbl.id.isIn(creditedSongIds),
              )
              ..orderBy([
                (t) => OrderingTerm.desc(t.dateAddedSec),
                (t) => OrderingTerm.asc(t.titleSearch),
              ])
              ..limit(limit))
            .get();
    return _decorate(rows);
  }

  /// Albums the artist appears on — primary-artist albums plus albums of any
  /// song they are credited on via `song_artists` — for the horizontal album
  /// strip on the artist detail page.
  Future<List<AlbumSummary>> albumsForArtist(
    int artistRowId, {
    int limit = 200,
  }) async {
    final albums = _db.albums;
    final songs = _db.songs;
    final songCount = songs.id.count();

    final credited = await _db
        .customSelect(
          'SELECT DISTINCT song_id FROM song_artists WHERE artist_id = ?',
          variables: [Variable<int>(artistRowId)],
        )
        .get();
    final creditedSongIds = <int>{
      for (final row in credited) row.data['song_id'] as int,
    };

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
      ])
      ..where(
        songs.artistRowId.equals(artistRowId) |
            (creditedSongIds.isEmpty
                ? const Constant(false)
                : songs.id.isIn(creditedSongIds)),
      )
      ..groupBy([albums.id])
      ..orderBy([OrderingTerm.desc(songs.dateAddedSec.max())]);
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
        ),
    ];
  }

  Future<List<SongTileData>> songsForGenre(
    String genre, {
    int limit = 1000,
  }) async {
    final rows =
        await (_db.select(_db.songs)
              ..where((tbl) => tbl.genre.equals(genre))
              ..orderBy([
                (t) => OrderingTerm.desc(t.dateAddedSec),
                (t) => OrderingTerm.asc(t.titleSearch),
              ])
              ..limit(limit))
            .get();
    return _decorate(rows);
  }

  /// Songs the user explicitly hid via the song overflow menu ("Hide song").
  ///
  /// The normal browsing queries exclude these rows, so the Settings →
  /// "Show Hidden Songs" screen needs a dedicated read that surfaces them for
  /// restoration. Reuses the shared [_decorate] so artwork and ReplayGain are
  /// resolved exactly as they are everywhere else.
  Future<List<SongTileData>> hiddenSongs({int limit = 1000}) async {
    final hiddenIds = await hiddenSongIds();
    if (hiddenIds.isEmpty) {
      return const [];
    }
    final rows =
        await (_db.select(_db.songs)
              ..where((tbl) => tbl.id.isIn(hiddenIds))
              ..orderBy([(t) => OrderingTerm.asc(t.titleSearch)])
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

  /// Increments play_count, stamps last_played_at and appends a `play_history`
  /// row per song. The history row feeds the daily/weekly/yearly and peak-day
  /// statistics; its `listened_ms` is written later by
  /// [addPlaybackListenedMs] once the engine reports how long the track was
  /// actually heard for.
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
        b.customStatement(
          'INSERT INTO play_history (song_id, played_at, listened_ms) '
          'VALUES (?, ?, 0)',
          [id, millis],
        );
      }
    });
  }

  /// Credits `listenedMs` to the most recent unclosed `play_history` row for a
  /// song. The engine reports this when a track ends (advance/completion/stop),
  /// so only time actually heard — never paused or stopped time — is recorded.
  Future<void> addPlaybackListenedMs({
    required int songRowId,
    required int listenedMs,
    required DateTime at,
  }) async {
    if (listenedMs <= 0) {
      return;
    }
    await _db.customStatement(
      'UPDATE play_history SET listened_ms = listened_ms + ? '
      'WHERE id = ('
      'SELECT id FROM play_history WHERE song_id = ? AND played_at <= ? '
      'ORDER BY id DESC LIMIT 1'
      ')',
      [listenedMs, songRowId, at.millisecondsSinceEpoch],
    );
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
    //
    // total_ms is the SUM of *actual measured listening time* from
    // play_history — the same single source of truth as the week/year graphs,
    // so the header's "Listening Time" always agrees with the rest of the
    // Statistics screen and Home strip. (The older play-count x duration_ms
    // estimate inflated the number because it assumed every play heard the
    // whole song, producing inconsistent "7h header vs 2h graph" figures.)
    final statsRows = await _db
        .customSelect(
          'SELECT COALESCE(SUM(st.play_count), 0) AS total_plays, '
          'COALESCE((SELECT SUM(ph.listened_ms) FROM play_history ph), 0) '
          'AS total_ms '
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
    String? topSongArtPath;
    final topRow = await _db
        .customSelect(
          'SELECT s.id AS id, s.album_row_id AS album_row_id, '
          's.title AS title, s.artist AS artist, '
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
        final songId = (topRow.data['id'] as num?)?.toInt();
        final albumRowId = (topRow.data['album_row_id'] as num?)?.toInt();
        if (songId != null) {
          topSongArtPath = await _resolvedArtPath(songId, albumRowId);
        }
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
      mostPlayedSongArtPath: topSongArtPath,
    );
  }

  Future<List<SongTileData>> topPlayedSongs({int limit = 5}) async {
    return collectionSongs(CollectionKind.mostPlayed, limit: limit);
  }

  Future<List<SongTileData>> recentlyPlayedSongs({int limit = 5}) async {
    return collectionSongs(CollectionKind.recentlyPlayed, limit: limit);
  }

  /// Aggregates real, persisted listening history into the statistics screen's
  /// time-based breakdown. Every figure is derived from `play_history` rows —
  /// actual measured listening time and the timestamp each play started.
  ///
  /// [now] is injected so week/year boundaries can be tested deterministically.
  Future<ListeningBreakdown> listeningBreakdown({DateTime? now}) async {
    final reference = now ?? DateTime.now();
    final referenceDay = DateTime(
      reference.year,
      reference.month,
      reference.day,
    );
    final referenceDayKey = _dayKey(referenceDay);
    // Local-midnight Monday so the week boundary and its 7 daily bars use the
    // same local-date keys as [dayMs]/[dayKey] below. (A UTC-midnight week-start
    // drifted from the local day buckets, so early local-hours plays on the
    // week's first day were mis-bucketed or dropped entirely.)
    final weekStart = referenceDay.subtract(
      Duration(days: reference.weekday - 1),
    );
    // Exclusive end of the current week (next Monday at local midnight). The
    // week window is [weekStart, weekEnd): without the upper bound,
    // future-dated rows (clock skew, restored timestamps) would leak into
    // "This Week", and the window would never be a true calendar week.
    final weekEnd = weekStart.add(const Duration(days: 7));

    // One bounded pass over the joined history so all bucketing happens in
    // Dart with correct local-date handling, rather than many SQL passes.
    final rows = await _db
        .customSelect(
          'SELECT ph.played_at AS played_at, ph.listened_ms AS listened_ms, '
          's.title AS title, s.artist AS artist '
          'FROM play_history ph JOIN songs s ON s.id = ph.song_id '
          'ORDER BY ph.played_at ASC',
        )
        .get();

    int totalListenedMs = 0;
    int totalPlays = 0;
    final uniqueSongs = <String>{};
    // dayKey (yyyy-mm-dd) -> ms
    final dayMs = <String, int>{};
    // dayKey -> plays
    final dayPlays = <String, int>{};
    // year+monthKey -> ms
    final monthMs = <String, int>{};
    // period key -> artistKey normalized -> plays
    final weekArtistPlays = <String, int>{};
    final yearArtistPlays = <String, int>{};
    final allTimeArtistPlays = <String, int>{};
    // period key -> song play counts (keyed by normalized title+artist)
    final weekSongPlays = <String, int>{};
    final yearSongPlays = <String, int>{};
    // period key -> song metadata (normalized key -> {title, artist})
    final weekSongMeta = <String, ({String title, String? artist})>{};
    final yearSongMeta = <String, ({String title, String? artist})>{};

    for (final row in rows) {
      final playedAtMs = (row.data['played_at'] as num).toInt();
      final listenedMs = (row.data['listened_ms'] as num).toInt();
      final title = (row.data['title'] as String?) ?? '';
      final artist = (row.data['artist'] as String?) ?? '';
      final day = DateTime.fromMillisecondsSinceEpoch(playedAtMs);
      final dayKey = _dayKey(day);
      final monthKey = '${day.year}-${day.month.toString().padLeft(2, '0')}';

      totalListenedMs += listenedMs;
      totalPlays += 1;
      uniqueSongs.add(_songHistoryKey(title, artist));
      dayMs.update(dayKey, (v) => v + listenedMs, ifAbsent: () => listenedMs);
      dayPlays.update(dayKey, (v) => v + 1, ifAbsent: () => 1);
      monthMs.update(
        monthKey,
        (v) => v + listenedMs,
        ifAbsent: () => listenedMs,
      );

      final inWeek = !day.isBefore(weekStart) && day.isBefore(weekEnd);
      final songKey = _songHistoryKey(title, artist);
      final artistKey = artist.isEmpty ? '(Unknown)' : artist.toLowerCase();

      if (inWeek) {
        weekArtistPlays.update(artistKey, (v) => v + 1, ifAbsent: () => 1);
        weekSongPlays.update(songKey, (v) => v + 1, ifAbsent: () => 1);
        weekSongMeta[songKey] = (title: title, artist: artist);
      }
      final inYear = day.year == reference.year;
      if (inYear) {
        yearArtistPlays.update(artistKey, (v) => v + 1, ifAbsent: () => 1);
        yearSongPlays.update(songKey, (v) => v + 1, ifAbsent: () => 1);
        yearSongMeta[songKey] = (title: title, artist: artist);
      }
      allTimeArtistPlays.update(artistKey, (v) => v + 1, ifAbsent: () => 1);
    }

    // --- Week report ---
    var weekMs = 0;
    var weekPlays = 0;
    for (var i = 0; i < 7; i++) {
      final d = weekStart.add(Duration(days: i));
      final key = _dayKey(d);
      weekMs += dayMs[key] ?? 0;
      weekPlays += dayPlays[key] ?? 0;
    }
    // Distinct songs seen this week == distinct normalized entries in the week
    // song map, which is keyed per in-week row.
    final weekUniqueSongs = weekSongMeta.length;

    // --- Year report ---
    var yearMs = 0;
    var yearPlays = 0;
    final yearUniqueSongs = yearSongMeta.length;
    for (final v in monthMs.entries) {
      final y = int.tryParse(v.key.split('-').first) ?? 0;
      if (y == reference.year) {
        yearMs += v.value;
      }
    }
    for (final v in yearSongPlays.values) {
      yearPlays += v;
    }

    // --- Peak day ---
    PeakDayStats? peakDay;
    if (dayMs.isNotEmpty) {
      String? peakKey;
      var peak = -1;
      for (final e in dayMs.entries) {
        if (e.value > peak) {
          peak = e.value;
          peakKey = e.key;
        }
      }
      if (peakKey != null) {
        final parts = peakKey.split('-');
        peakDay = PeakDayStats(
          day: DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          ),
          listenedMs: peak,
          plays: dayPlays[peakKey] ?? 0,
        );
      }
    }

    // --- Top songs / artists ---
    List<HistoryTopEntry> topEntries(
      Map<String, int> plays,
      Map<String, ({String title, String? artist})> meta,
    ) {
      final sorted = plays.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return [
        for (final e in sorted.take(3))
          HistoryTopEntry(
            label: meta[e.key]?.title ?? 'Unknown song',
            artist: meta[e.key]?.artist,
            count: e.value,
          ),
      ];
    }

    HistoryTopEntry? topArtist(Map<String, int> plays) {
      if (plays.isEmpty) return null;
      final best = plays.entries.reduce((a, b) => b.value > a.value ? b : a);
      return HistoryTopEntry(label: best.key, count: best.value);
    }

    // weekDaily / yearMonthly bars (zero-filled so charts render cleanly).
    final weekDaily = <DayListen>[];
    for (var i = 0; i < 7; i++) {
      final d = weekStart.add(Duration(days: i));
      final key = _dayKey(d);
      weekDaily.add(
        DayListen(day: d, listenedMs: dayMs[key] ?? 0, plays: dayPlays[key] ?? 0),
      );
    }
    final yearMonthly = <DayListen>[];
    for (var m = 1; m <= 12; m++) {
      final key = '${reference.year}-${m.toString().padLeft(2, '0')}';
      yearMonthly.add(
        DayListen(
          day: DateTime(reference.year, m, 1),
          listenedMs: monthMs[key] ?? 0,
        ),
      );
    }

    return ListeningBreakdown(
      totalListenedMs: totalListenedMs,
      totalPlays: totalPlays,
      totalUniqueSongs: uniqueSongs.length,
      // Today is just a window onto the same persisted history: crossing
      // midnight moves the window without touching the stored rows, so Top
      // Day / This Week / This Year keep their historical values.
      today: DayListen(
        day: referenceDay,
        listenedMs: dayMs[referenceDayKey] ?? 0,
        plays: dayPlays[referenceDayKey] ?? 0,
      ),
      peakDay: peakDay,
      topArtist: topArtist(allTimeArtistPlays),
      week: PeriodStats(
        listenedMs: weekMs,
        plays: weekPlays,
        uniqueSongs: weekUniqueSongs,
        topSongs: topEntries(weekSongPlays, weekSongMeta),
        topArtist: topArtist(weekArtistPlays),
      ),
      year: PeriodStats(
        listenedMs: yearMs,
        plays: yearPlays,
        uniqueSongs: yearUniqueSongs,
        topSongs: topEntries(yearSongPlays, yearSongMeta),
        topArtist: topArtist(yearArtistPlays),
      ),
      weekDaily: weekDaily,
      yearMonthly: yearMonthly,
    );
  }
}

String _songHistoryKey(String title, String artist) =>
    '${title.toLowerCase()}|${artist.toLowerCase()}';

/// Single consistent calendar-day bucket key (local time): `yyyy-mm-dd`.
///
/// Every daily aggregation in [LibraryRepository.listeningBreakdown] — the
/// today window, the weekly bars and the peak-day map — goes through this one
/// helper so midnight rollover, week boundaries and DST transitions bucket
/// identically. Raw timestamps are never compared directly.
String _dayKey(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

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

import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../library/data/library_models.dart';
import 'playlist_models.dart';

/// The ONLY writer of playlist tables.
///
/// All multi-row mutations (append, renumber, delete) run inside a single
/// transaction so the UNIQUE(playlist_id, position) constraint can never be
/// observed in an inconsistent state.
class PlaylistRepository {
  PlaylistRepository(this._db);

  final AppDatabase _db;

  // -------------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------------

  Future<List<PlaylistSummary>> listPlaylists({int limit = 500}) async {
    final playlists = _db.playlists;
    final ps = _db.playlistSongs;
    final songs = _db.songs;
    final songCount = ps.id.count();
    final totalDur = songs.durationMs.sum();

    final query = _db.selectOnly(playlists).join([
      leftOuterJoin(ps, ps.playlistId.equalsExp(playlists.id)),
      leftOuterJoin(songs, songs.id.equalsExp(ps.songRowId)),
    ]);
    query
      ..addColumns([
        playlists.id,
        playlists.name,
        playlists.pinned,
        playlists.updatedAt,
        songCount,
        totalDur,
      ])
      ..groupBy([playlists.id])
      ..orderBy([
        OrderingTerm.desc(playlists.pinned),
        OrderingTerm.desc(playlists.updatedAt),
      ]);

    query.limit(limit);

    final rows = await query.get();

    final covers = await _coversByPlaylistId();
    return [
      for (final row in rows)
        PlaylistSummary(
          id: row.read(playlists.id)!,
          name: row.read(playlists.name)!,
          pinned: row.read(playlists.pinned)!,
          songCount: row.read(songCount) ?? 0,
          covers: covers[row.read(playlists.id)!] ?? const [],
          totalDurationMs: row.read(totalDur) ?? 0,
        ),
    ];
  }

  /// First three artwork paths per playlist via a window function, so the
  /// overview stays O(members) instead of one query per playlist.
  Future<Map<int, List<String?>>> _coversByPlaylistId() async {
    final rows = await _db
        .customSelect(
          '''
      SELECT playlist_id, art_path FROM (
        SELECT
          ps.playlist_id AS playlist_id,
          COALESCE(
            NULLIF(a.art_large_path, ''),
            NULLIF(a.art_small_path, '')
          ) AS art_path,
          ROW_NUMBER() OVER (
            PARTITION BY ps.playlist_id ORDER BY ps.position
          ) AS rn
        FROM playlist_songs ps
        JOIN songs s ON s.id = ps.song_row_id
        LEFT JOIN albums a ON a.id = s.album_row_id
      )
      WHERE rn <= 3 AND art_path IS NOT NULL
      ''',
          readsFrom: {_db.playlistSongs, _db.songs, _db.albums},
        )
        .get();

    final out = <int, List<String?>>{};
    for (final row in rows) {
      final pid = row.read<int>('playlist_id');
      final art = row.read<String?>('art_path');
      (out[pid] ??= []).add(art);
    }
    return out;
  }

  /// Decorated, position-ordered songs of one playlist. Paginated the same
  /// way as the library Songs view.
  Future<List<SongTileData>> songsOf(
    int playlistId, {
    int limit = 200,
    int offset = 0,
  }) async {
    final ps = _db.playlistSongs;
    final rows =
        await (_db.select(_db.songs).join([
                innerJoin(ps, ps.songRowId.equalsExp(_db.songs.id)),
              ])
              ..where(ps.playlistId.equals(playlistId))
              ..orderBy([OrderingTerm.asc(ps.position)])
              ..limit(limit, offset: offset))
            .get();

    final artById = await _albumArtForRows(
      rows.map((r) => r.readTable(_db.songs)),
    );
    return [
      for (final row in rows)
        SongTileData(
          song: row.readTable(_db.songs),
          artPath: artById[row.readTable(_db.songs).albumRowId],
        ),
    ];
  }

  Future<Map<int, String?>> _albumArtForRows(Iterable<Song> songs) async {
    final albumIds = songs.map((s) => s.albumRowId).whereType<int>().toSet();
    if (albumIds.isEmpty) {
      return const {};
    }
    final albums = await (_db.select(
      _db.albums,
    )..where((tbl) => tbl.id.isIn(albumIds))).get();
    return {
      for (final a in albums) a.id: _pickArt(a.artLargePath, a.artSmallPath),
    };
  }

  /// Song row ids currently members of [playlistId] — used by the add-sheet
  /// to show membership state without guessing.
  Future<Set<int>> memberSongRowIds(int playlistId) async {
    final rows = await (_db.select(
      _db.playlistSongs,
    )..where((tbl) => tbl.playlistId.equals(playlistId))).get();
    return rows.map((r) => r.songRowId).toSet();
  }

  // -------------------------------------------------------------------------
  // Mutations
  // -------------------------------------------------------------------------

  Future<int> createPlaylist(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    try {
      final id = await _db
          .into(_db.playlists)
          .insert(PlaylistsCompanion.insert(name: name));
      return id;
    } catch (_) {
      final existing = await (_db.select(
        _db.playlists,
      )..where((tbl) => tbl.name.equals(name))).getSingleOrNull();
      if (existing != null) {
        throw DuplicatePlaylistNameException(name);
      }
      rethrow;
    }
  }

  Future<void> renamePlaylist(int id, String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    final collision =
        await (_db.select(_db.playlists)
              ..where((tbl) => tbl.name.equals(name) & tbl.id.equals(id).not()))
            .getSingleOrNull();
    if (collision != null) {
      throw DuplicatePlaylistNameException(name);
    }
    final updated =
        await (_db.update(
          _db.playlists,
        )..where((tbl) => tbl.id.equals(id))).write(
          PlaylistsCompanion(
            name: Value(name),
            updatedAt: Value(DateTime.now()),
          ),
        );
    if (updated == 0) {
      throw PlaylistNotFoundException(id);
    }
  }

  Future<void> deletePlaylist(int id) {
    return _db.transaction(() async {
      await (_db.delete(
        _db.playlistSongs,
      )..where((tbl) => tbl.playlistId.equals(id))).go();
      await (_db.delete(_db.playlists)..where((tbl) => tbl.id.equals(id))).go();
    });
  }

  Future<void> setPinned(int id, bool pinned) async {
    await (_db.update(_db.playlists)..where((tbl) => tbl.id.equals(id))).write(
      PlaylistsCompanion(
        pinned: Value(pinned),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Appends songs at the tail, preserving the given order.
  Future<void> addSongs(int playlistId, List<int> songRowIds) async {
    if (songRowIds.isEmpty) {
      return;
    }
    await _db.transaction(() async {
      final maxExp = _db.playlistSongs.position.max();
      final row =
          await (_db.selectOnly(_db.playlistSongs)
                ..addColumns([maxExp])
                ..where(_db.playlistSongs.playlistId.equals(playlistId)))
              .getSingle();
      var next = (row.read(maxExp) ?? -1) + 1;
      await _db.batch((b) {
        for (final songRowId in songRowIds) {
          b.insert(
            _db.playlistSongs,
            PlaylistSongsCompanion.insert(
              playlistId: playlistId,
              songRowId: songRowId,
              position: next++,
            ),
            mode: InsertMode.insertOrAbort,
          );
        }
      });
      await _touch(playlistId);
    });
  }

  /// Removes the entry at [index] (position order) and renumbers the tail.
  Future<void> removeSongAt(int playlistId, int index) {
    return _renumberAfterRemoval(playlistId, index);
  }

  Future<void> _renumberAfterRemoval(int playlistId, int index) async {
    await _db.transaction(() async {
      final entries = await _orderedEntries(playlistId);
      if (index < 0 || index >= entries.length) {
        return;
      }
      final doomed = entries[index];
      await (_db.delete(
        _db.playlistSongs,
      )..where((tbl) => tbl.id.equals(doomed.entryId))).go();
      final remaining = [...entries]..removeAt(index);
      await _rewritePositions(playlistId, remaining.map((e) => e.songRowId));
    });
  }

  /// Moves the entry at [from] so it lands at [to], renumbering everything
  /// between. Negative staging avoids transient UNIQUE(position) clashes.
  Future<void> moveSong(int playlistId, int from, int to) {
    return _db.transaction(() async {
      final entries = await _orderedEntries(playlistId);
      if (from < 0 ||
          to < 0 ||
          from >= entries.length ||
          to >= entries.length) {
        return;
      }
      final reordered = [...entries];
      final moved = reordered.removeAt(from);
      reordered.insert(to, moved);

      for (var i = 0; i < reordered.length; i++) {
        await (_db.update(_db.playlistSongs)
              ..where((tbl) => tbl.id.equals(reordered[i].entryId)))
            .write(PlaylistSongsCompanion(position: Value(-1 - i)));
      }
      for (var i = 0; i < reordered.length; i++) {
        await (_db.update(_db.playlistSongs)
              ..where((tbl) => tbl.id.equals(reordered[i].entryId)))
            .write(PlaylistSongsCompanion(position: Value(i)));
      }
      await _touch(playlistId);
    });
  }

  Future<List<({int entryId, int songRowId})>> _orderedEntries(
    int playlistId,
  ) async {
    final rows =
        await (_db.select(_db.playlistSongs)
              ..where((tbl) => tbl.playlistId.equals(playlistId))
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();
    return [for (final r in rows) (entryId: r.id, songRowId: r.songRowId)];
  }

  Future<void> _rewritePositions(
    int playlistId,
    Iterable<int> songRowIdsInOrder,
  ) async {
    var pos = 0;
    for (final songRowId in songRowIdsInOrder) {
      await (_db.update(_db.playlistSongs)..where(
            (tbl) =>
                tbl.playlistId.equals(playlistId) &
                tbl.songRowId.equals(songRowId),
          ))
          .write(PlaylistSongsCompanion(position: Value(pos++)));
    }
    await _touch(playlistId);
  }

  Future<void> _touch(int playlistId) async {
    await (_db.update(_db.playlists)..where((tbl) => tbl.id.equals(playlistId)))
        .write(PlaylistsCompanion(updatedAt: Value(DateTime.now())));
  }
}

String? _pickArt(String? large, String? small) {
  if (large != null && large.isNotEmpty) return large;
  if (small != null && small.isNotEmpty) return small;
  return null;
}

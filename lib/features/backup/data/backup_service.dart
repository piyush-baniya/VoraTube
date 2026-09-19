import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/player/player_controller.dart';
import 'backup_format.dart';
import 'backup_models.dart';
import 'song_matcher.dart';

class BackupService {
  BackupService(this.db);
  final AppDatabase db;

  BackupPayload read(Uint8List bytes) {
    try {
      final payload = BackupPayload.tryFromJson(decodeBackupBytes(bytes));
      if (payload == null) {
        throw BackupFormatException('Invalid backup payload');
      }
      payload.validate();
      for (final entry in payload.kv) {
        if (entry.key != 'settings.librarySection' &&
            entry.value.isNotEmpty &&
            jsonDecode(entry.value) is! Map) {
          throw BackupFormatException('Invalid settings');
        }
      }
      return payload;
    } on BackupFormatException {
      rethrow;
    } catch (_) {
      throw BackupFormatException('Invalid backup payload');
    }
  }

  Future<List<Map<String, dynamic>>> rows(String sql) async => [
    for (final r in await db.customSelect(sql).get())
      Map<String, dynamic>.from(r.data),
  ];

  Future<BackupPayload> capture(String appVersion) => db.transaction(() async {
    final library = await db.select(db.songs).get();
    final indexes = {for (var i = 0; i < library.length; i++) library[i].id: i};
    final identities = {
      for (var i = 0; i < library.length; i++) songIdentity(library[i]): i,
    };
    final extras = await rows(
      'SELECT song_id, is_hidden, user_edited, skip_count, total_ms_played FROM song_extras',
    );
    final edited = {
      for (final e in extras)
        if (e['user_edited'] == 1) e['song_id'],
    };
    final kv = await db.select(db.kvEntries).get();
    Map<String, dynamic>? queue;
    for (final entry in kv) {
      if (entry.key == 'playback.snapshot.v1' && entry.valueText != null) {
        final snapshot = QueueSnapshot.fromJson(entry.valueText!);
        queue = {
          'songs': [
            for (final key in snapshot.identityKeys)
              if (identities.containsKey(key)) identities[key],
          ],
          'index': snapshot.index,
          'posMs': snapshot.positionMs,
          'shuffle': snapshot.shuffleEnabled,
          'repeat': snapshot.repeatMode.name,
        };
      }
    }
    final playlists = <BackupPlaylist>[];
    for (final p in await db.select(db.playlists).get()) {
      final content =
          await (db.select(db.playlistSongs)
                ..where((s) => s.playlistId.equals(p.id))
                ..orderBy([(s) => OrderingTerm.asc(s.position)]))
              .get();
      playlists.add(
        BackupPlaylist(
          name: p.name,
          pinned: p.pinned,
          songIndexes: [
            for (final s in content)
              if (indexes.containsKey(s.songRowId)) indexes[s.songRowId]!,
          ],
        ),
      );
    }
    final captured = BackupPayload(
      createdAt: DateTime.now(),
      appVersion: appVersion,
      librarySongCount: library.length,
      songs: [
        for (var i = 0; i < library.length; i++)
          BackupSongRef(
            index: i,
            identityKey: library[i].contentHash == null
                ? ''
                : 'h:${library[i].contentHash}',
            relativePath: relativePathOf(library[i].path),
            fileName: fileNameOf(library[i].path),
            title: library[i].title,
            artist: library[i].artist ?? '',
            album: library[i].albumName ?? '',
            durationMs: library[i].durationMs,
            sizeBytes: library[i].sizeBytes ?? 0,
          ),
      ],
      playlists: playlists,
      stats: [
        for (final s in await db.select(db.songStats).get())
          if (indexes.containsKey(s.songId))
            BackupSongStats(
              songIndex: indexes[s.songId]!,
              isFavorite: s.isFavorite,
              playCount: s.playCount,
              lastPlayedAtMs: s.lastPlayedAt,
              mood: s.mood ?? '',
            ),
      ],
      extras: [
        for (final e in extras)
          if (indexes.containsKey(e['song_id']))
            BackupSongExtras(
              songIndex: indexes[e['song_id']]!,
              isHidden: e['is_hidden'] == 1,
              userEdited: e['user_edited'] == 1,
              skipCount: e['skip_count'] as int,
              totalMsPlayed: e['total_ms_played'] as int,
            ),
      ],
      history: [
        for (final h in await rows(
          'SELECT song_id, played_at, listened_ms FROM play_history ORDER BY id',
        ))
          if (indexes.containsKey(h['song_id']))
            BackupHistoryEntry(
              songIndex: indexes[h['song_id']]!,
              playedAtMs: h['played_at'] as int,
              msPlayed: h['listened_ms'] as int,
            ),
      ],
      lrc: [
        for (final l in await rows(
          'SELECT identity_key, lrc, file_name FROM user_lrc',
        ))
          BackupLrc(
            identityKey: identities.containsKey(l['identity_key'])
                ? 'ref:${identities[l['identity_key']]}'
                : l['identity_key'] as String,
            songIndex: identities[l['identity_key']],
            lrc: l['lrc'] as String,
            fileName: l['file_name'] as String? ?? '',
          ),
      ],
      kv: [
        for (final e in kv)
          if (capturedPortableSettingKeys.contains(e.key) && e.valueText != null)
            BackupKvEntry(key: e.key, value: e.valueText!),
      ],
      songData: [
        for (var i = 0; i < library.length; i++)
          if (edited.contains(library[i].id) ||
              library[i].replayGainJson != null)
            {
              'i': i,
              if (library[i].replayGainJson != null)
                'gain': library[i].replayGainJson!,
              if (edited.contains(library[i].id)) ...{
                'title': library[i].title,
                'artist': library[i].artist ?? '',
                'album': library[i].albumName ?? '',
                'genre': library[i].genre ?? '',
                if (library[i].year != null) 'year': library[i].year!,
                if (library[i].trackNumber != null)
                  'track': library[i].trackNumber!,
                if (library[i].discNumber != null)
                  'disc': library[i].discNumber!,
              },
            },
      ],
      queue: queue,
    );
    final pending = kv
        .where((e) => e.key == 'backup.unresolved.v1')
        .firstOrNull
        ?.valueText;
    return pending == null || pending.isEmpty
        ? captured
        : _retainUnresolved(captured, pending);
  });

  Future<SongMatchResult> plan(BackupPayload payload) async {
    read(composeBackupBytes(payload.toJson()));
    return const SongMatcher().match(
      payload.songs,
      await db.select(db.songs).get(),
    );
  }

  Future<SongMatchResult> restore(
    Uint8List bytes,
    Directory safetyDirectory, {
    Future<void> Function()? beforeCommit,
  }) async {
    final payload = read(bytes);
    await plan(payload);
    final safety = File(
      '${safetyDirectory.path}/voratube-restore-${DateTime.now().microsecondsSinceEpoch}.vtb',
    );
    final previous = composeBackupBytes((await capture('safety')).toJson());
    await safety.writeAsBytes(previous, flush: true);
    read(await safety.readAsBytes());
    late SongMatchResult mapping;
    try {
      await db.transaction(() async {
        final library = await db.select(db.songs).get();
        mapping = const SongMatcher().match(payload.songs, library);
        int? id(int index) => mapping.matches[index]?.rowId;
        final byId = {for (final s in library) s.id: s};
        await db.delete(db.playlistSongs).go();
        await db.delete(db.playlists).go();
        await db.delete(db.songStats).go();
        await db.customStatement('DELETE FROM play_history');
        await db.customStatement('DELETE FROM user_lrc');
        await db.customStatement(
          'UPDATE song_extras SET is_hidden=0, user_edited=0, skip_count=0, total_ms_played=0',
        );
        for (final key in acceptedPortableSettingKeys) {
          await (db.delete(db.kvEntries)..where((e) => e.key.equals(key))).go();
        }
        for (final e in payload.kv) {
          // Obsolete settings keys older backups may carry (the removed
          // `settings.uiLayout.v1` customization) parse fine on read but are
          // never written back: their feature no longer exists.
          if (!capturedPortableSettingKeys.contains(e.key)) continue;
          await db
              .into(db.kvEntries)
              .insertOnConflictUpdate(
                KvEntriesCompanion.insert(
                  key: e.key,
                  valueText: Value(e.value),
                ),
              );
        }
        for (final p in payload.playlists) {
          final playlistId = await db
              .into(db.playlists)
              .insert(
                PlaylistsCompanion.insert(
                  name: p.name,
                  pinned: Value(p.pinned),
                ),
              );
          for (var position = 0; position < p.songIndexes.length; position++) {
            final songId = id(p.songIndexes[position]);
            if (songId != null) {
              await db
                  .into(db.playlistSongs)
                  .insert(
                    PlaylistSongsCompanion.insert(
                      playlistId: playlistId,
                      songRowId: songId,
                      position: position,
                    ),
                  );
            }
          }
        }
        for (final s in payload.stats) {
          final songId = id(s.songIndex);
          if (songId == null) continue;
          await db
              .into(db.songStats)
              .insertOnConflictUpdate(
                SongStatsCompanion.insert(
                  songId: Value(songId),
                  isFavorite: Value(s.isFavorite),
                  playCount: Value(s.playCount),
                  lastPlayedAt: Value(s.lastPlayedAtMs),
                  mood: Value(s.mood),
                ),
              );
        }
        for (final e in payload.extras) {
          final songId = id(e.songIndex);
          if (songId == null) continue;
          await db.customStatement(
            'INSERT INTO song_extras (song_id,is_hidden,user_edited,skip_count,total_ms_played) VALUES (?,?,?,?,?) '
            'ON CONFLICT(song_id) DO UPDATE SET is_hidden=excluded.is_hidden,user_edited=excluded.user_edited,skip_count=excluded.skip_count,total_ms_played=excluded.total_ms_played',
            [
              songId,
              e.isHidden ? 1 : 0,
              e.userEdited ? 1 : 0,
              e.skipCount,
              e.totalMsPlayed,
            ],
          );
        }
        for (final h in payload.history) {
          final songId = id(h.songIndex);
          if (songId != null) {
            await db.customStatement(
              'INSERT INTO play_history (song_id,played_at,listened_ms) VALUES (?,?,?)',
              [songId, h.playedAtMs, h.msPlayed],
            );
          }
        }
        for (final l in payload.lrc) {
          final songId = l.songIndex == null ? null : id(l.songIndex!);
          final key = songId == null
              ? 'unresolved:${l.identityKey}'
              : songIdentity(byId[songId]!);
          await db.customStatement(
            'INSERT OR REPLACE INTO user_lrc (identity_key,lrc,file_name,saved_at) VALUES (?,?,?,?)',
            [key, l.lrc, l.fileName, payload.createdAt.millisecondsSinceEpoch],
          );
        }
        for (final data in payload.songData) {
          final songId = id(data['i'] as int);
          if (songId == null) continue;
          await (db.update(db.songs)..where((s) => s.id.equals(songId))).write(
            SongsCompanion(
              replayGainJson: data.containsKey('gain')
                  ? Value(data['gain'] as String)
                  : const Value.absent(),
              title: data.containsKey('title')
                  ? Value(data['title'] as String)
                  : const Value.absent(),
              titleSearch: data.containsKey('title')
                  ? Value((data['title'] as String).toLowerCase())
                  : const Value.absent(),
              artist: data.containsKey('artist')
                  ? Value(data['artist'] as String)
                  : const Value.absent(),
              artistSearch: data.containsKey('artist')
                  ? Value((data['artist'] as String).toLowerCase())
                  : const Value.absent(),
              albumName: data.containsKey('album')
                  ? Value(data['album'] as String)
                  : const Value.absent(),
              genre: data.containsKey('genre')
                  ? Value(data['genre'] as String)
                  : const Value.absent(),
              year: data.containsKey('year')
                  ? Value(data['year'] as int)
                  : const Value.absent(),
              trackNumber: data.containsKey('track')
                  ? Value(data['track'] as int)
                  : const Value.absent(),
              discNumber: data.containsKey('disc')
                  ? Value(data['disc'] as int)
                  : const Value.absent(),
            ),
          );
        }
        final q = payload.queue;
        final queueSongIds = [
          for (final i in q?['songs'] ?? const [])
            if (id(i) != null) id(i)!,
        ];
        final queue = q == null || queueSongIds.isEmpty
            ? const QueueSnapshot.empty()
            : QueueSnapshot(
                identityKeys: [
                  for (final songId in queueSongIds) songIdentity(byId[songId]!),
                ],
                index: (q['index'] as int).clamp(0, queueSongIds.length - 1),
                positionMs: q['posMs'] as int,
                shuffleEnabled: q['shuffle'] as bool,
                repeatMode: RepeatMode.values.byName(q['repeat'] as String),
              );
        await db
            .into(db.kvEntries)
            .insertOnConflictUpdate(
              KvEntriesCompanion.insert(
                key: 'playback.snapshot.v1',
                valueText: Value(queue.toJson()),
              ),
            );
        // Retain the original portable references, including all unresolved state.
        await db
            .into(db.kvEntries)
            .insertOnConflictUpdate(
              KvEntriesCompanion.insert(
                key: 'backup.unresolved.v1',
                valueText: Value(
                  mapping.unresolved.isEmpty
                      ? ''
                      : jsonEncode({
                          'payload': payload.toJson(),
                          'indexes': mapping.unresolved,
                        }),
                ),
              ),
            );
        if (beforeCommit != null) await beforeCommit();
        if ((await db.customSelect('PRAGMA foreign_key_check').get())
            .isNotEmpty) {
          throw StateError('Restore failed database integrity verification');
        }
      });
    } catch (_) {
      // Drift rolls every persisted domain back together. Keep the safety file.
      rethrow;
    }
    try {
      await safety.delete();
    } on FileSystemException {
      /* committed */
    }
    db.notifyUpdates({
      for (final table in db.allTables) TableUpdate.onTable(table),
    });
    return mapping;
  }
}

BackupPayload _retainUnresolved(BackupPayload current, String stored) {
  final pending = jsonDecode(stored) as Map<String, dynamic>;
  final original = BackupPayload.tryFromJson(
    pending['payload'] as Map<String, dynamic>,
  )!;
  final missing = (pending['indexes'] as List).cast<int>().toSet();
  final json = current.toJson();
  final indexes = <int, int>{};
  final songs = json['songs'] as List;
  for (final i in missing) {
    indexes[i] = songs.length;
    songs.add(original.songs[i].toJson());
  }
  for (final section in ['stats', 'extras', 'history', 'songData', 'lrc']) {
    for (final row in original.toJson()[section] as List) {
      if (indexes.containsKey(row['i'])) {
        (json[section] as List).add({
          ...row as Map<String, dynamic>,
          'i': indexes[row['i']],
        });
      }
    }
  }
  final playlists = json['playlists'] as List;
  for (final p in original.playlists) {
    final retained = p.songIndexes.where(missing.contains).toList();
    if (retained.isEmpty) continue;
    var target = playlists
        .cast<Map<String, dynamic>>()
        .where((e) => e['n'] == p.name)
        .firstOrNull;
    if (target == null) {
      target = {'n': p.name, 'pin': p.pinned, 's': <int>[]};
      playlists.add(target);
    }
    final content = (target['s'] as List?) ?? <int>[];
    target['s'] = content;
    for (var pos = 0; pos < p.songIndexes.length; pos++) {
      final index = indexes[p.songIndexes[pos]];
      if (index != null) content.insert(pos.clamp(0, content.length), index);
    }
  }
  json['counts'] = {
    'songs': songs.length,
    'playlists': playlists.length,
    'favorites': (json['stats'] as List).where((s) => s['fav'] == true).length,
    'history': (json['history'] as List).length,
  };
  return BackupPayload.tryFromJson(json)!;
}
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/features/backup/data/backup_format.dart';
import 'package:vora_tube/features/backup/data/backup_models.dart';
import 'package:vora_tube/features/backup/data/backup_service.dart';
import 'package:vora_tube/features/backup/data/song_matcher.dart';

Future<int> track(
  AppDatabase db,
  int mediaId, {
  String path = '/storage/emulated/0/Music/a.mp3',
  String? hash,
  String title = 'A',
}) => db
    .into(db.songs)
    .insert(
      SongsCompanion.insert(
        contentUri: 'content://$mediaId',
        title: title,
        titleSearch: title.toLowerCase(),
        durationMs: 180000,
        dateModifiedSec: 1,
        mediaStoreId: Value(mediaId),
        path: Value(path),
        artist: const Value('Artist'),
        albumName: const Value('Album'),
        sizeBytes: const Value(4000),
        contentHash: Value(hash),
      ),
    );

void main() {
  late AppDatabase db;
  late BackupService service;
  late Directory temp;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    service = BackupService(db);
    temp = await Directory.systemTemp.createTemp('vtb-test-');
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  test(
    'round trip, checksum, malformed, truncated, future and invalid structures',
    () async {
      await track(db, 1);
      final p = await service.capture('test');
      final bytes = composeBackupBytes(p.toJson());
      expect(service.read(bytes).toJson(), p.toJson());
      final corrupt = Uint8List.fromList(bytes)..[bytes.length - 1] ^= 1;
      final future = Uint8List.fromList(bytes)..[backupMagic.length] = 2;
      for (final bad in [
        corrupt,
        future,
        Uint8List.fromList([1, 2, 3]),
        bytes.sublist(0, bytes.length - 2),
        composeBackupBytes({
          ...p.toJson(),
          'stats': [
            {'i': 300},
          ],
        }),
        composeBackupBytes({
          ...p.toJson(),
          'playlists': [
            {
              'n': 'Bad',
              's': ['0'],
            },
          ],
        }),
        composeBackupBytes({
          ...p.toJson(),
          'extras': [
            {'i': 0, 'hid': 'yes'},
          ],
        }),
        composeBackupBytes({
          ...p.toJson(),
          'kv': [
            {'k': 'analytics.identity', 'v': 'x'},
          ],
        }),
      ]) {
        expect(() => service.read(bad), throwsA(isA<BackupFormatException>()));
      }
    },
  );

  test('full replacement restores user state across changed install IDs, excludes caches', () async {
    final id = await track(db, 1);
    final p = await db
        .into(db.playlists)
        .insert(
          PlaylistsCompanion.insert(
            name: 'Survival',
            pinned: const Value(true),
          ),
        );
    await db
        .into(db.playlistSongs)
        .insert(
          PlaylistSongsCompanion.insert(
            playlistId: p,
            songRowId: id,
            position: 0,
          ),
        );
    await db
        .into(db.songStats)
        .insert(
          SongStatsCompanion.insert(
            songId: Value(id),
            isFavorite: const Value(true),
            playCount: const Value(8),
          ),
        );
    await db.customStatement(
      'INSERT INTO song_extras (song_id,is_hidden,skip_count,total_ms_played,art_small_path) VALUES (?,1,3,5000,?)',
      [id, '/private/cache.jpg'],
    );
    await db.customStatement(
      'INSERT INTO play_history (song_id,played_at,listened_ms) VALUES (?,1234,5000)',
      [id],
    );
    await db.customStatement(
      "INSERT INTO user_lrc VALUES ('ms:1','[00:01]Survival','survival.lrc',1234)",
    );
    for (final entry in {
      'settings.audio': '{"eqCustomLevels":[1,2,3],"playbackSpeed":1.25}',
      'settings.equalizer':
          '{"v":1,"presets":[{"id":"mine","name":"Mine","levels":[1,2,3]}]}',
      'settings.appearance': '{"themeMode":"dark"}',
      // Obsolete customization key from a pre-removal app version: tolerated on
      // read, never captured, never written back.
      'settings.uiLayout.v1': '{"v":2,"layouts":[]}',
      'analytics.identity': 'private',
      'artwork.cache': '/private/cache.jpg',
    }.entries) {
      await db
          .into(db.kvEntries)
          .insert(
            KvEntriesCompanion.insert(
              key: entry.key,
              valueText: Value(entry.value),
            ),
          );
    }
    final payload = await service.capture('test');
    final bytes = composeBackupBytes(payload.toJson());
    expect(payload.kv.length, 3);
    expect(payload.kv.map((e) => e.key), isNot(contains('settings.uiLayout.v1')));
    expect(payload.toJson().toString(), isNot(contains('/private')));
    await db.customStatement(
      "UPDATE songs SET media_store_id=900, content_uri='content://900'",
    );
    await db.customStatement("UPDATE playlists SET name='Changed'");
    final result = await service.restore(bytes, temp);
    expect(result.matchedCount, 1);
    expect((await db.select(db.playlists).get()).single.name, 'Survival');
    expect((await db.select(db.playlistSongs).get()).single.songRowId, id);
    expect((await db.select(db.songStats).get()).single.playCount, 8);
    expect((await db.select(db.songStats).get()).single.isFavorite, isTrue);
    expect(
      (await service.rows('SELECT * FROM play_history')).single['listened_ms'],
      5000,
    );
    expect(
      (await service.rows('SELECT * FROM song_extras')).single['skip_count'],
      3,
    );
    expect(
      (await service.rows('SELECT * FROM user_lrc')).single['identity_key'],
      'ms:900',
    );
    expect(
      await service.rows(
        "SELECT key FROM kv_entries WHERE key='settings.uiLayout.v1'",
      ),
      isEmpty,
    );
    expect(
      await service.rows(
        "SELECT key FROM kv_entries WHERE key='artwork.cache'",
      ),
      isNotEmpty,
      reason: 'caches are never captured nor deleted',
    );
    expect(
      (await service.capture('test')).kv.map((e) => e.value),
      payload.kv.map((e) => e.value),
    );
    await service.restore(bytes, temp);
    expect((await db.select(db.playlists).get()).length, 1);
    expect((await service.rows('SELECT * FROM play_history')).length, 1);
    expect(await temp.list().length, 0);
  });

  test('old backups carrying removed customization are accepted but not restored', () async {
    await track(db, 1);
    final base = await service.capture('old-app');
    final json = base.toJson();
    json['kv'] = [
      {'k': 'settings.uiLayout.v1', 'v': '{"v":2,"layouts":[]}'},
      {'k': 'settings.appearance', 'v': '{"themeMode":"dark"}'},
    ];
    final bytes = composeBackupBytes(json);
    expect(() => service.read(bytes), returnsNormally);
    await service.restore(bytes, temp);
    expect(
      (await service.rows(
        "SELECT value_text FROM kv_entries WHERE key='settings.appearance'",
      )).single['value_text'],
      '{"themeMode":"dark"}',
    );
    expect(
      await service.rows(
        "SELECT key FROM kv_entries WHERE key='settings.uiLayout.v1'",
      ),
      isEmpty,
    );
  });

  test('rollback after destructive writes and validation failure preserve all state', () async {
    await track(db, 1);
    final bytes = composeBackupBytes((await service.capture('test')).toJson());
    await db
        .into(db.playlists)
        .insert(PlaylistsCompanion.insert(name: 'Keep me'));
    await db
        .into(db.kvEntries)
        .insert(
          KvEntriesCompanion.insert(
            key: 'settings.appearance',
            valueText: const Value('{"themeMode":"light"}'),
          ),
        );
    final before = (await service.capture('test')).toJson()..remove('at');
    await expectLater(
      service.restore(
        bytes,
        temp,
        beforeCommit: () async => throw StateError('injected'),
      ),
      throwsStateError,
    );
    expect((await service.capture('test')).toJson()..remove('at'), before);
    await expectLater(
      service.restore(Uint8List(1), temp),
      throwsA(isA<BackupFormatException>()),
    );
    expect((await service.capture('test')).toJson()..remove('at'), before);
    expect(await temp.list().length, 1);
  });

  test(
    'matching tiers, ambiguity, missing tracks and MediaStore IDs',
    () async {
      await track(db, 10, hash: 'stable');
      final library = await db.select(db.songs).get();
      SongMatchResult match(BackupSongRef ref) =>
          const SongMatcher().match([ref], library);
      expect(
        match(const BackupSongRef(index: 0, identityKey: 'h:stable'))
            .matches[0]!
            .tier,
        SongMatchTier.identity,
      );
      expect(
        match(
          const BackupSongRef(
            index: 0,
            relativePath: 'Music/a.mp3',
            fileName: 'a.mp3',
          ),
        ).matches[0]!.tier,
        SongMatchTier.relativePath,
      );
      expect(
        match(
          const BackupSongRef(
            index: 0,
            fileName: 'a.mp3',
            sizeBytes: 4000,
            durationMs: 180000,
          ),
        ).matches[0]!.tier,
        SongMatchTier.fileExact,
      );
      expect(
        match(
          const BackupSongRef(
            index: 0,
            title: 'A',
            artist: 'Artist',
            album: 'Album',
            durationMs: 180000,
          ),
        ).matches[0]!.tier,
        SongMatchTier.metadata,
      );
      expect(
        match(const BackupSongRef(index: 0, identityKey: 'ms:10')).unresolved,
        [0],
      );
      await track(db, 11, path: '/storage/ABCD/Music/a.mp3');
      expect(
        const SongMatcher().match([
          const BackupSongRef(
            index: 0,
            relativePath: 'Music/a.mp3',
            fileName: 'a.mp3',
            title: 'A',
            artist: 'Artist',
            album: 'Album',
            durationMs: 180000,
          ),
        ], await db.select(db.songs).get()).unresolved,
        [0],
      );
      final missing = BackupPayload(
        createdAt: DateTime.now(),
        songs: [const BackupSongRef(index: 0, fileName: 'gone.mp3')],
        playlists: [
          const BackupPlaylist(name: 'Missing', songIndexes: [0]),
        ],
      );
      final result = await service.restore(
        composeBackupBytes(missing.toJson()),
        temp,
      );
      expect(result.unresolvedCount, 1);
      expect((await db.select(db.playlists).get()).single.name, 'Missing');
      expect(
        (await service.rows(
          "SELECT value_text FROM kv_entries WHERE key='backup.unresolved.v1'",
        )).single['value_text'],
        contains('gone.mp3'),
      );
    },
  );
}
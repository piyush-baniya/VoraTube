import 'dart:io';

import 'package:drift/native.dart';

import 'package:vora_tube/core/db/app_database.dart';

Future<void> main() async {
  final copy = File(
    'C:/Users/LENOVO/AppData/Local/Temp/opencode/vt_bin.sqlite',
  );
  final db = AppDatabase(NativeDatabase(copy));

  final songs = await db.select(db.songs).get();
  final albums = await db.select(db.albums).get();
  final artists = await db.select(db.artists).get();
  final scans = await db.select(db.scanStates).get();

  stdout.writeln('songs:   ${songs.length}');
  stdout.writeln('albums:  ${albums.length}');
  stdout.writeln('artists: ${artists.length}');
  stdout.writeln('scan_state entries: ${scans.length}');
  for (final s in scans) {
    stdout.writeln(
      '  source=${s.source} totalSongs=${s.totalSongs} '
      'completedAt=${s.lastCompletedAt}',
    );
  }

  final withAlbum = songs.where((s) => s.albumRowId != null).length;
  final withArtist = songs.where((s) => s.artistRowId != null).length;
  final withGenre = songs.where((s) => s.genre != null).length;
  final withYear = songs.where((s) => s.year != null).length;
  final withTrack = songs.where((s) => s.trackNumber != null).length;
  final albumsWithArt = albums
      .where((a) => (a.artSmallPath ?? '').isNotEmpty)
      .length;

  stdout.writeln(
    'links: album=$withAlbum artist=$withArtist '
    'genre=$withGenre year=$withYear track=$withTrack',
  );
  stdout.writeln('albums with artwork: $albumsWithArt/${albums.length}');

  stdout.writeln('--- sample rows ---');
  for (final s in songs.take(5)) {
    stdout.writeln(
      '${s.mediaStoreId} | "${s.title}" | ${s.artist} | ${s.albumName} | '
      '${s.durationMs}ms | fmt=${s.format} | y=${s.year} | t=${s.trackNumber}',
    );
  }
  stdout.writeln('--- sample albums ---');
  for (final a in albums.take(4)) {
    stdout.writeln(
      '${a.mediaStoreAlbumId} | "${a.name}" | ${a.artistName} | '
      'art=${(a.artSmallPath ?? '').isEmpty ? "MISSING" : "ok"}',
    );
  }

  await db.close();
}

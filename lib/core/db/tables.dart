import 'package:drift/drift.dart';

@TableIndex(
  name: 'songs_media_store_id',
  columns: {#mediaStoreId},
  unique: true,
)
@TableIndex(name: 'songs_album', columns: {#albumRowId})
@TableIndex(name: 'songs_artist', columns: {#artistRowId})
@TableIndex(name: 'songs_title_search', columns: {#titleSearch})
@TableIndex(name: 'songs_date_added', columns: {#dateAddedSec})
class Songs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get mediaStoreId => integer()();
  TextColumn get contentUri => text()();
  TextColumn get path => text().nullable()();
  TextColumn get title => text()();
  TextColumn get titleSearch => text()();
  TextColumn get artist => text().nullable()();
  TextColumn get artistSearch => text().nullable()();
  TextColumn get albumName => text().nullable()();
  IntColumn get albumRowId => integer().nullable().references(Albums, #id)();
  IntColumn get artistRowId => integer().nullable().references(Artists, #id)();
  TextColumn get genre => text().nullable()();
  IntColumn get year => integer().nullable()();
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get discNumber => integer().nullable()();
  IntColumn get durationMs => integer()();
  IntColumn get dateModifiedSec => integer()();
  IntColumn get dateAddedSec => integer().nullable()();
  IntColumn get sizeBytes => integer().nullable()();
  TextColumn get format => text().nullable()();
}

@TableIndex(
  name: 'albums_media_store_id',
  columns: {#mediaStoreAlbumId},
  unique: true,
)
class Albums extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get mediaStoreAlbumId => integer()();
  TextColumn get name => text()();
  TextColumn get artistName => text().nullable()();
  TextColumn get artSmallPath => text().nullable()();
  TextColumn get artLargePath => text().nullable()();
}

@TableIndex(
  name: 'artists_media_store_id',
  columns: {#mediaStoreArtistId},
  unique: true,
)
class Artists extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get mediaStoreArtistId => integer()();
  TextColumn get name => text()();
}

@DataClassName('SongStat')
class SongStats extends Table {
  IntColumn get songId => integer()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {songId};
}

class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@TableIndex(
  name: 'playlist_songs_position',
  columns: {#playlistId, #position},
  unique: true,
)
class PlaylistSongs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get playlistId => integer().references(Playlists, #id)();
  IntColumn get songRowId => integer().references(Songs, #id)();
  IntColumn get position => integer()();
}

@DataClassName('KvEntry')
class KvEntries extends Table {
  TextColumn get key => text()();
  TextColumn get valueText => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('ScanStateEntry')
class ScanStates extends Table {
  TextColumn get source => text()();
  DateTimeColumn get lastCompletedAt => dateTime().nullable()();
  IntColumn get totalSongs => integer().nullable()();
  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {source};
}

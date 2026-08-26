// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $AlbumsTable extends Albums with TableInfo<$AlbumsTable, Album> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlbumsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _mediaStoreAlbumIdMeta = const VerificationMeta(
    'mediaStoreAlbumId',
  );
  @override
  late final GeneratedColumn<int> mediaStoreAlbumId = GeneratedColumn<int>(
    'media_store_album_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumKeyMeta = const VerificationMeta(
    'albumKey',
  );
  @override
  late final GeneratedColumn<String> albumKey = GeneratedColumn<String>(
    'album_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistNameMeta = const VerificationMeta(
    'artistName',
  );
  @override
  late final GeneratedColumn<String> artistName = GeneratedColumn<String>(
    'artist_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artSmallPathMeta = const VerificationMeta(
    'artSmallPath',
  );
  @override
  late final GeneratedColumn<String> artSmallPath = GeneratedColumn<String>(
    'art_small_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artLargePathMeta = const VerificationMeta(
    'artLargePath',
  );
  @override
  late final GeneratedColumn<String> artLargePath = GeneratedColumn<String>(
    'art_large_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    mediaStoreAlbumId,
    albumKey,
    name,
    artistName,
    artSmallPath,
    artLargePath,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'albums';
  @override
  VerificationContext validateIntegrity(
    Insertable<Album> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('media_store_album_id')) {
      context.handle(
        _mediaStoreAlbumIdMeta,
        mediaStoreAlbumId.isAcceptableOrUnknown(
          data['media_store_album_id']!,
          _mediaStoreAlbumIdMeta,
        ),
      );
    }
    if (data.containsKey('album_key')) {
      context.handle(
        _albumKeyMeta,
        albumKey.isAcceptableOrUnknown(data['album_key']!, _albumKeyMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('artist_name')) {
      context.handle(
        _artistNameMeta,
        artistName.isAcceptableOrUnknown(data['artist_name']!, _artistNameMeta),
      );
    }
    if (data.containsKey('art_small_path')) {
      context.handle(
        _artSmallPathMeta,
        artSmallPath.isAcceptableOrUnknown(
          data['art_small_path']!,
          _artSmallPathMeta,
        ),
      );
    }
    if (data.containsKey('art_large_path')) {
      context.handle(
        _artLargePathMeta,
        artLargePath.isAcceptableOrUnknown(
          data['art_large_path']!,
          _artLargePathMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Album map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Album(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      mediaStoreAlbumId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}media_store_album_id'],
      ),
      albumKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_key'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      artistName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist_name'],
      ),
      artSmallPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}art_small_path'],
      ),
      artLargePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}art_large_path'],
      ),
    );
  }

  @override
  $AlbumsTable createAlias(String alias) {
    return $AlbumsTable(attachedDatabase, alias);
  }
}

class Album extends DataClass implements Insertable<Album> {
  final int id;
  final int? mediaStoreAlbumId;
  final String? albumKey;
  final String name;
  final String? artistName;
  final String? artSmallPath;
  final String? artLargePath;
  const Album({
    required this.id,
    this.mediaStoreAlbumId,
    this.albumKey,
    required this.name,
    this.artistName,
    this.artSmallPath,
    this.artLargePath,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || mediaStoreAlbumId != null) {
      map['media_store_album_id'] = Variable<int>(mediaStoreAlbumId);
    }
    if (!nullToAbsent || albumKey != null) {
      map['album_key'] = Variable<String>(albumKey);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || artistName != null) {
      map['artist_name'] = Variable<String>(artistName);
    }
    if (!nullToAbsent || artSmallPath != null) {
      map['art_small_path'] = Variable<String>(artSmallPath);
    }
    if (!nullToAbsent || artLargePath != null) {
      map['art_large_path'] = Variable<String>(artLargePath);
    }
    return map;
  }

  AlbumsCompanion toCompanion(bool nullToAbsent) {
    return AlbumsCompanion(
      id: Value(id),
      mediaStoreAlbumId: mediaStoreAlbumId == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaStoreAlbumId),
      albumKey: albumKey == null && nullToAbsent
          ? const Value.absent()
          : Value(albumKey),
      name: Value(name),
      artistName: artistName == null && nullToAbsent
          ? const Value.absent()
          : Value(artistName),
      artSmallPath: artSmallPath == null && nullToAbsent
          ? const Value.absent()
          : Value(artSmallPath),
      artLargePath: artLargePath == null && nullToAbsent
          ? const Value.absent()
          : Value(artLargePath),
    );
  }

  factory Album.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Album(
      id: serializer.fromJson<int>(json['id']),
      mediaStoreAlbumId: serializer.fromJson<int?>(json['mediaStoreAlbumId']),
      albumKey: serializer.fromJson<String?>(json['albumKey']),
      name: serializer.fromJson<String>(json['name']),
      artistName: serializer.fromJson<String?>(json['artistName']),
      artSmallPath: serializer.fromJson<String?>(json['artSmallPath']),
      artLargePath: serializer.fromJson<String?>(json['artLargePath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'mediaStoreAlbumId': serializer.toJson<int?>(mediaStoreAlbumId),
      'albumKey': serializer.toJson<String?>(albumKey),
      'name': serializer.toJson<String>(name),
      'artistName': serializer.toJson<String?>(artistName),
      'artSmallPath': serializer.toJson<String?>(artSmallPath),
      'artLargePath': serializer.toJson<String?>(artLargePath),
    };
  }

  Album copyWith({
    int? id,
    Value<int?> mediaStoreAlbumId = const Value.absent(),
    Value<String?> albumKey = const Value.absent(),
    String? name,
    Value<String?> artistName = const Value.absent(),
    Value<String?> artSmallPath = const Value.absent(),
    Value<String?> artLargePath = const Value.absent(),
  }) => Album(
    id: id ?? this.id,
    mediaStoreAlbumId: mediaStoreAlbumId.present
        ? mediaStoreAlbumId.value
        : this.mediaStoreAlbumId,
    albumKey: albumKey.present ? albumKey.value : this.albumKey,
    name: name ?? this.name,
    artistName: artistName.present ? artistName.value : this.artistName,
    artSmallPath: artSmallPath.present ? artSmallPath.value : this.artSmallPath,
    artLargePath: artLargePath.present ? artLargePath.value : this.artLargePath,
  );
  Album copyWithCompanion(AlbumsCompanion data) {
    return Album(
      id: data.id.present ? data.id.value : this.id,
      mediaStoreAlbumId: data.mediaStoreAlbumId.present
          ? data.mediaStoreAlbumId.value
          : this.mediaStoreAlbumId,
      albumKey: data.albumKey.present ? data.albumKey.value : this.albumKey,
      name: data.name.present ? data.name.value : this.name,
      artistName: data.artistName.present
          ? data.artistName.value
          : this.artistName,
      artSmallPath: data.artSmallPath.present
          ? data.artSmallPath.value
          : this.artSmallPath,
      artLargePath: data.artLargePath.present
          ? data.artLargePath.value
          : this.artLargePath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Album(')
          ..write('id: $id, ')
          ..write('mediaStoreAlbumId: $mediaStoreAlbumId, ')
          ..write('albumKey: $albumKey, ')
          ..write('name: $name, ')
          ..write('artistName: $artistName, ')
          ..write('artSmallPath: $artSmallPath, ')
          ..write('artLargePath: $artLargePath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    mediaStoreAlbumId,
    albumKey,
    name,
    artistName,
    artSmallPath,
    artLargePath,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Album &&
          other.id == this.id &&
          other.mediaStoreAlbumId == this.mediaStoreAlbumId &&
          other.albumKey == this.albumKey &&
          other.name == this.name &&
          other.artistName == this.artistName &&
          other.artSmallPath == this.artSmallPath &&
          other.artLargePath == this.artLargePath);
}

class AlbumsCompanion extends UpdateCompanion<Album> {
  final Value<int> id;
  final Value<int?> mediaStoreAlbumId;
  final Value<String?> albumKey;
  final Value<String> name;
  final Value<String?> artistName;
  final Value<String?> artSmallPath;
  final Value<String?> artLargePath;
  const AlbumsCompanion({
    this.id = const Value.absent(),
    this.mediaStoreAlbumId = const Value.absent(),
    this.albumKey = const Value.absent(),
    this.name = const Value.absent(),
    this.artistName = const Value.absent(),
    this.artSmallPath = const Value.absent(),
    this.artLargePath = const Value.absent(),
  });
  AlbumsCompanion.insert({
    this.id = const Value.absent(),
    this.mediaStoreAlbumId = const Value.absent(),
    this.albumKey = const Value.absent(),
    required String name,
    this.artistName = const Value.absent(),
    this.artSmallPath = const Value.absent(),
    this.artLargePath = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Album> custom({
    Expression<int>? id,
    Expression<int>? mediaStoreAlbumId,
    Expression<String>? albumKey,
    Expression<String>? name,
    Expression<String>? artistName,
    Expression<String>? artSmallPath,
    Expression<String>? artLargePath,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mediaStoreAlbumId != null) 'media_store_album_id': mediaStoreAlbumId,
      if (albumKey != null) 'album_key': albumKey,
      if (name != null) 'name': name,
      if (artistName != null) 'artist_name': artistName,
      if (artSmallPath != null) 'art_small_path': artSmallPath,
      if (artLargePath != null) 'art_large_path': artLargePath,
    });
  }

  AlbumsCompanion copyWith({
    Value<int>? id,
    Value<int?>? mediaStoreAlbumId,
    Value<String?>? albumKey,
    Value<String>? name,
    Value<String?>? artistName,
    Value<String?>? artSmallPath,
    Value<String?>? artLargePath,
  }) {
    return AlbumsCompanion(
      id: id ?? this.id,
      mediaStoreAlbumId: mediaStoreAlbumId ?? this.mediaStoreAlbumId,
      albumKey: albumKey ?? this.albumKey,
      name: name ?? this.name,
      artistName: artistName ?? this.artistName,
      artSmallPath: artSmallPath ?? this.artSmallPath,
      artLargePath: artLargePath ?? this.artLargePath,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (mediaStoreAlbumId.present) {
      map['media_store_album_id'] = Variable<int>(mediaStoreAlbumId.value);
    }
    if (albumKey.present) {
      map['album_key'] = Variable<String>(albumKey.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (artistName.present) {
      map['artist_name'] = Variable<String>(artistName.value);
    }
    if (artSmallPath.present) {
      map['art_small_path'] = Variable<String>(artSmallPath.value);
    }
    if (artLargePath.present) {
      map['art_large_path'] = Variable<String>(artLargePath.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlbumsCompanion(')
          ..write('id: $id, ')
          ..write('mediaStoreAlbumId: $mediaStoreAlbumId, ')
          ..write('albumKey: $albumKey, ')
          ..write('name: $name, ')
          ..write('artistName: $artistName, ')
          ..write('artSmallPath: $artSmallPath, ')
          ..write('artLargePath: $artLargePath')
          ..write(')'))
        .toString();
  }
}

class $ArtistsTable extends Artists with TableInfo<$ArtistsTable, Artist> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ArtistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _mediaStoreArtistIdMeta =
      const VerificationMeta('mediaStoreArtistId');
  @override
  late final GeneratedColumn<int> mediaStoreArtistId = GeneratedColumn<int>(
    'media_store_artist_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artistKeyMeta = const VerificationMeta(
    'artistKey',
  );
  @override
  late final GeneratedColumn<String> artistKey = GeneratedColumn<String>(
    'artist_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    mediaStoreArtistId,
    artistKey,
    name,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'artists';
  @override
  VerificationContext validateIntegrity(
    Insertable<Artist> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('media_store_artist_id')) {
      context.handle(
        _mediaStoreArtistIdMeta,
        mediaStoreArtistId.isAcceptableOrUnknown(
          data['media_store_artist_id']!,
          _mediaStoreArtistIdMeta,
        ),
      );
    }
    if (data.containsKey('artist_key')) {
      context.handle(
        _artistKeyMeta,
        artistKey.isAcceptableOrUnknown(data['artist_key']!, _artistKeyMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Artist map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Artist(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      mediaStoreArtistId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}media_store_artist_id'],
      ),
      artistKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist_key'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
    );
  }

  @override
  $ArtistsTable createAlias(String alias) {
    return $ArtistsTable(attachedDatabase, alias);
  }
}

class Artist extends DataClass implements Insertable<Artist> {
  final int id;
  final int? mediaStoreArtistId;
  final String? artistKey;
  final String name;
  const Artist({
    required this.id,
    this.mediaStoreArtistId,
    this.artistKey,
    required this.name,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || mediaStoreArtistId != null) {
      map['media_store_artist_id'] = Variable<int>(mediaStoreArtistId);
    }
    if (!nullToAbsent || artistKey != null) {
      map['artist_key'] = Variable<String>(artistKey);
    }
    map['name'] = Variable<String>(name);
    return map;
  }

  ArtistsCompanion toCompanion(bool nullToAbsent) {
    return ArtistsCompanion(
      id: Value(id),
      mediaStoreArtistId: mediaStoreArtistId == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaStoreArtistId),
      artistKey: artistKey == null && nullToAbsent
          ? const Value.absent()
          : Value(artistKey),
      name: Value(name),
    );
  }

  factory Artist.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Artist(
      id: serializer.fromJson<int>(json['id']),
      mediaStoreArtistId: serializer.fromJson<int?>(json['mediaStoreArtistId']),
      artistKey: serializer.fromJson<String?>(json['artistKey']),
      name: serializer.fromJson<String>(json['name']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'mediaStoreArtistId': serializer.toJson<int?>(mediaStoreArtistId),
      'artistKey': serializer.toJson<String?>(artistKey),
      'name': serializer.toJson<String>(name),
    };
  }

  Artist copyWith({
    int? id,
    Value<int?> mediaStoreArtistId = const Value.absent(),
    Value<String?> artistKey = const Value.absent(),
    String? name,
  }) => Artist(
    id: id ?? this.id,
    mediaStoreArtistId: mediaStoreArtistId.present
        ? mediaStoreArtistId.value
        : this.mediaStoreArtistId,
    artistKey: artistKey.present ? artistKey.value : this.artistKey,
    name: name ?? this.name,
  );
  Artist copyWithCompanion(ArtistsCompanion data) {
    return Artist(
      id: data.id.present ? data.id.value : this.id,
      mediaStoreArtistId: data.mediaStoreArtistId.present
          ? data.mediaStoreArtistId.value
          : this.mediaStoreArtistId,
      artistKey: data.artistKey.present ? data.artistKey.value : this.artistKey,
      name: data.name.present ? data.name.value : this.name,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Artist(')
          ..write('id: $id, ')
          ..write('mediaStoreArtistId: $mediaStoreArtistId, ')
          ..write('artistKey: $artistKey, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, mediaStoreArtistId, artistKey, name);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Artist &&
          other.id == this.id &&
          other.mediaStoreArtistId == this.mediaStoreArtistId &&
          other.artistKey == this.artistKey &&
          other.name == this.name);
}

class ArtistsCompanion extends UpdateCompanion<Artist> {
  final Value<int> id;
  final Value<int?> mediaStoreArtistId;
  final Value<String?> artistKey;
  final Value<String> name;
  const ArtistsCompanion({
    this.id = const Value.absent(),
    this.mediaStoreArtistId = const Value.absent(),
    this.artistKey = const Value.absent(),
    this.name = const Value.absent(),
  });
  ArtistsCompanion.insert({
    this.id = const Value.absent(),
    this.mediaStoreArtistId = const Value.absent(),
    this.artistKey = const Value.absent(),
    required String name,
  }) : name = Value(name);
  static Insertable<Artist> custom({
    Expression<int>? id,
    Expression<int>? mediaStoreArtistId,
    Expression<String>? artistKey,
    Expression<String>? name,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mediaStoreArtistId != null)
        'media_store_artist_id': mediaStoreArtistId,
      if (artistKey != null) 'artist_key': artistKey,
      if (name != null) 'name': name,
    });
  }

  ArtistsCompanion copyWith({
    Value<int>? id,
    Value<int?>? mediaStoreArtistId,
    Value<String?>? artistKey,
    Value<String>? name,
  }) {
    return ArtistsCompanion(
      id: id ?? this.id,
      mediaStoreArtistId: mediaStoreArtistId ?? this.mediaStoreArtistId,
      artistKey: artistKey ?? this.artistKey,
      name: name ?? this.name,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (mediaStoreArtistId.present) {
      map['media_store_artist_id'] = Variable<int>(mediaStoreArtistId.value);
    }
    if (artistKey.present) {
      map['artist_key'] = Variable<String>(artistKey.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ArtistsCompanion(')
          ..write('id: $id, ')
          ..write('mediaStoreArtistId: $mediaStoreArtistId, ')
          ..write('artistKey: $artistKey, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }
}

class $SongsTable extends Songs with TableInfo<$SongsTable, Song> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SongsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _mediaStoreIdMeta = const VerificationMeta(
    'mediaStoreId',
  );
  @override
  late final GeneratedColumn<int> mediaStoreId = GeneratedColumn<int>(
    'media_store_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('mediastore'),
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentUriMeta = const VerificationMeta(
    'contentUri',
  );
  @override
  late final GeneratedColumn<String> contentUri = GeneratedColumn<String>(
    'content_uri',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleSearchMeta = const VerificationMeta(
    'titleSearch',
  );
  @override
  late final GeneratedColumn<String> titleSearch = GeneratedColumn<String>(
    'title_search',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artistSearchMeta = const VerificationMeta(
    'artistSearch',
  );
  @override
  late final GeneratedColumn<String> artistSearch = GeneratedColumn<String>(
    'artist_search',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumNameMeta = const VerificationMeta(
    'albumName',
  );
  @override
  late final GeneratedColumn<String> albumName = GeneratedColumn<String>(
    'album_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumRowIdMeta = const VerificationMeta(
    'albumRowId',
  );
  @override
  late final GeneratedColumn<int> albumRowId = GeneratedColumn<int>(
    'album_row_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES albums (id)',
    ),
  );
  static const VerificationMeta _artistRowIdMeta = const VerificationMeta(
    'artistRowId',
  );
  @override
  late final GeneratedColumn<int> artistRowId = GeneratedColumn<int>(
    'artist_row_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES artists (id)',
    ),
  );
  static const VerificationMeta _genreMeta = const VerificationMeta('genre');
  @override
  late final GeneratedColumn<String> genre = GeneratedColumn<String>(
    'genre',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _trackNumberMeta = const VerificationMeta(
    'trackNumber',
  );
  @override
  late final GeneratedColumn<int> trackNumber = GeneratedColumn<int>(
    'track_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _discNumberMeta = const VerificationMeta(
    'discNumber',
  );
  @override
  late final GeneratedColumn<int> discNumber = GeneratedColumn<int>(
    'disc_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateModifiedSecMeta = const VerificationMeta(
    'dateModifiedSec',
  );
  @override
  late final GeneratedColumn<int> dateModifiedSec = GeneratedColumn<int>(
    'date_modified_sec',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateAddedSecMeta = const VerificationMeta(
    'dateAddedSec',
  );
  @override
  late final GeneratedColumn<int> dateAddedSec = GeneratedColumn<int>(
    'date_added_sec',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    mediaStoreId,
    source,
    contentHash,
    contentUri,
    path,
    title,
    titleSearch,
    artist,
    artistSearch,
    albumName,
    albumRowId,
    artistRowId,
    genre,
    year,
    trackNumber,
    discNumber,
    durationMs,
    dateModifiedSec,
    dateAddedSec,
    sizeBytes,
    format,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'songs';
  @override
  VerificationContext validateIntegrity(
    Insertable<Song> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('media_store_id')) {
      context.handle(
        _mediaStoreIdMeta,
        mediaStoreId.isAcceptableOrUnknown(
          data['media_store_id']!,
          _mediaStoreIdMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
    }
    if (data.containsKey('content_uri')) {
      context.handle(
        _contentUriMeta,
        contentUri.isAcceptableOrUnknown(data['content_uri']!, _contentUriMeta),
      );
    } else if (isInserting) {
      context.missing(_contentUriMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('title_search')) {
      context.handle(
        _titleSearchMeta,
        titleSearch.isAcceptableOrUnknown(
          data['title_search']!,
          _titleSearchMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_titleSearchMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    }
    if (data.containsKey('artist_search')) {
      context.handle(
        _artistSearchMeta,
        artistSearch.isAcceptableOrUnknown(
          data['artist_search']!,
          _artistSearchMeta,
        ),
      );
    }
    if (data.containsKey('album_name')) {
      context.handle(
        _albumNameMeta,
        albumName.isAcceptableOrUnknown(data['album_name']!, _albumNameMeta),
      );
    }
    if (data.containsKey('album_row_id')) {
      context.handle(
        _albumRowIdMeta,
        albumRowId.isAcceptableOrUnknown(
          data['album_row_id']!,
          _albumRowIdMeta,
        ),
      );
    }
    if (data.containsKey('artist_row_id')) {
      context.handle(
        _artistRowIdMeta,
        artistRowId.isAcceptableOrUnknown(
          data['artist_row_id']!,
          _artistRowIdMeta,
        ),
      );
    }
    if (data.containsKey('genre')) {
      context.handle(
        _genreMeta,
        genre.isAcceptableOrUnknown(data['genre']!, _genreMeta),
      );
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('track_number')) {
      context.handle(
        _trackNumberMeta,
        trackNumber.isAcceptableOrUnknown(
          data['track_number']!,
          _trackNumberMeta,
        ),
      );
    }
    if (data.containsKey('disc_number')) {
      context.handle(
        _discNumberMeta,
        discNumber.isAcceptableOrUnknown(data['disc_number']!, _discNumberMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('date_modified_sec')) {
      context.handle(
        _dateModifiedSecMeta,
        dateModifiedSec.isAcceptableOrUnknown(
          data['date_modified_sec']!,
          _dateModifiedSecMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dateModifiedSecMeta);
    }
    if (data.containsKey('date_added_sec')) {
      context.handle(
        _dateAddedSecMeta,
        dateAddedSec.isAcceptableOrUnknown(
          data['date_added_sec']!,
          _dateAddedSecMeta,
        ),
      );
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Song map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Song(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      mediaStoreId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}media_store_id'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      ),
      contentUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_uri'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      titleSearch: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_search'],
      )!,
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      ),
      artistSearch: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist_search'],
      ),
      albumName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_name'],
      ),
      albumRowId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}album_row_id'],
      ),
      artistRowId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}artist_row_id'],
      ),
      genre: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre'],
      ),
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      ),
      trackNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}track_number'],
      ),
      discNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}disc_number'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      dateModifiedSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date_modified_sec'],
      )!,
      dateAddedSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}date_added_sec'],
      ),
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      ),
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      ),
    );
  }

  @override
  $SongsTable createAlias(String alias) {
    return $SongsTable(attachedDatabase, alias);
  }
}

class Song extends DataClass implements Insertable<Song> {
  final int id;
  final int? mediaStoreId;
  final String source;
  final String? contentHash;
  final String contentUri;
  final String? path;
  final String title;
  final String titleSearch;
  final String? artist;
  final String? artistSearch;
  final String? albumName;
  final int? albumRowId;
  final int? artistRowId;
  final String? genre;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final int durationMs;
  final int dateModifiedSec;
  final int? dateAddedSec;
  final int? sizeBytes;
  final String? format;
  const Song({
    required this.id,
    this.mediaStoreId,
    required this.source,
    this.contentHash,
    required this.contentUri,
    this.path,
    required this.title,
    required this.titleSearch,
    this.artist,
    this.artistSearch,
    this.albumName,
    this.albumRowId,
    this.artistRowId,
    this.genre,
    this.year,
    this.trackNumber,
    this.discNumber,
    required this.durationMs,
    required this.dateModifiedSec,
    this.dateAddedSec,
    this.sizeBytes,
    this.format,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || mediaStoreId != null) {
      map['media_store_id'] = Variable<int>(mediaStoreId);
    }
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || contentHash != null) {
      map['content_hash'] = Variable<String>(contentHash);
    }
    map['content_uri'] = Variable<String>(contentUri);
    if (!nullToAbsent || path != null) {
      map['path'] = Variable<String>(path);
    }
    map['title'] = Variable<String>(title);
    map['title_search'] = Variable<String>(titleSearch);
    if (!nullToAbsent || artist != null) {
      map['artist'] = Variable<String>(artist);
    }
    if (!nullToAbsent || artistSearch != null) {
      map['artist_search'] = Variable<String>(artistSearch);
    }
    if (!nullToAbsent || albumName != null) {
      map['album_name'] = Variable<String>(albumName);
    }
    if (!nullToAbsent || albumRowId != null) {
      map['album_row_id'] = Variable<int>(albumRowId);
    }
    if (!nullToAbsent || artistRowId != null) {
      map['artist_row_id'] = Variable<int>(artistRowId);
    }
    if (!nullToAbsent || genre != null) {
      map['genre'] = Variable<String>(genre);
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    if (!nullToAbsent || trackNumber != null) {
      map['track_number'] = Variable<int>(trackNumber);
    }
    if (!nullToAbsent || discNumber != null) {
      map['disc_number'] = Variable<int>(discNumber);
    }
    map['duration_ms'] = Variable<int>(durationMs);
    map['date_modified_sec'] = Variable<int>(dateModifiedSec);
    if (!nullToAbsent || dateAddedSec != null) {
      map['date_added_sec'] = Variable<int>(dateAddedSec);
    }
    if (!nullToAbsent || sizeBytes != null) {
      map['size_bytes'] = Variable<int>(sizeBytes);
    }
    if (!nullToAbsent || format != null) {
      map['format'] = Variable<String>(format);
    }
    return map;
  }

  SongsCompanion toCompanion(bool nullToAbsent) {
    return SongsCompanion(
      id: Value(id),
      mediaStoreId: mediaStoreId == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaStoreId),
      source: Value(source),
      contentHash: contentHash == null && nullToAbsent
          ? const Value.absent()
          : Value(contentHash),
      contentUri: Value(contentUri),
      path: path == null && nullToAbsent ? const Value.absent() : Value(path),
      title: Value(title),
      titleSearch: Value(titleSearch),
      artist: artist == null && nullToAbsent
          ? const Value.absent()
          : Value(artist),
      artistSearch: artistSearch == null && nullToAbsent
          ? const Value.absent()
          : Value(artistSearch),
      albumName: albumName == null && nullToAbsent
          ? const Value.absent()
          : Value(albumName),
      albumRowId: albumRowId == null && nullToAbsent
          ? const Value.absent()
          : Value(albumRowId),
      artistRowId: artistRowId == null && nullToAbsent
          ? const Value.absent()
          : Value(artistRowId),
      genre: genre == null && nullToAbsent
          ? const Value.absent()
          : Value(genre),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      trackNumber: trackNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(trackNumber),
      discNumber: discNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(discNumber),
      durationMs: Value(durationMs),
      dateModifiedSec: Value(dateModifiedSec),
      dateAddedSec: dateAddedSec == null && nullToAbsent
          ? const Value.absent()
          : Value(dateAddedSec),
      sizeBytes: sizeBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(sizeBytes),
      format: format == null && nullToAbsent
          ? const Value.absent()
          : Value(format),
    );
  }

  factory Song.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Song(
      id: serializer.fromJson<int>(json['id']),
      mediaStoreId: serializer.fromJson<int?>(json['mediaStoreId']),
      source: serializer.fromJson<String>(json['source']),
      contentHash: serializer.fromJson<String?>(json['contentHash']),
      contentUri: serializer.fromJson<String>(json['contentUri']),
      path: serializer.fromJson<String?>(json['path']),
      title: serializer.fromJson<String>(json['title']),
      titleSearch: serializer.fromJson<String>(json['titleSearch']),
      artist: serializer.fromJson<String?>(json['artist']),
      artistSearch: serializer.fromJson<String?>(json['artistSearch']),
      albumName: serializer.fromJson<String?>(json['albumName']),
      albumRowId: serializer.fromJson<int?>(json['albumRowId']),
      artistRowId: serializer.fromJson<int?>(json['artistRowId']),
      genre: serializer.fromJson<String?>(json['genre']),
      year: serializer.fromJson<int?>(json['year']),
      trackNumber: serializer.fromJson<int?>(json['trackNumber']),
      discNumber: serializer.fromJson<int?>(json['discNumber']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      dateModifiedSec: serializer.fromJson<int>(json['dateModifiedSec']),
      dateAddedSec: serializer.fromJson<int?>(json['dateAddedSec']),
      sizeBytes: serializer.fromJson<int?>(json['sizeBytes']),
      format: serializer.fromJson<String?>(json['format']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'mediaStoreId': serializer.toJson<int?>(mediaStoreId),
      'source': serializer.toJson<String>(source),
      'contentHash': serializer.toJson<String?>(contentHash),
      'contentUri': serializer.toJson<String>(contentUri),
      'path': serializer.toJson<String?>(path),
      'title': serializer.toJson<String>(title),
      'titleSearch': serializer.toJson<String>(titleSearch),
      'artist': serializer.toJson<String?>(artist),
      'artistSearch': serializer.toJson<String?>(artistSearch),
      'albumName': serializer.toJson<String?>(albumName),
      'albumRowId': serializer.toJson<int?>(albumRowId),
      'artistRowId': serializer.toJson<int?>(artistRowId),
      'genre': serializer.toJson<String?>(genre),
      'year': serializer.toJson<int?>(year),
      'trackNumber': serializer.toJson<int?>(trackNumber),
      'discNumber': serializer.toJson<int?>(discNumber),
      'durationMs': serializer.toJson<int>(durationMs),
      'dateModifiedSec': serializer.toJson<int>(dateModifiedSec),
      'dateAddedSec': serializer.toJson<int?>(dateAddedSec),
      'sizeBytes': serializer.toJson<int?>(sizeBytes),
      'format': serializer.toJson<String?>(format),
    };
  }

  Song copyWith({
    int? id,
    Value<int?> mediaStoreId = const Value.absent(),
    String? source,
    Value<String?> contentHash = const Value.absent(),
    String? contentUri,
    Value<String?> path = const Value.absent(),
    String? title,
    String? titleSearch,
    Value<String?> artist = const Value.absent(),
    Value<String?> artistSearch = const Value.absent(),
    Value<String?> albumName = const Value.absent(),
    Value<int?> albumRowId = const Value.absent(),
    Value<int?> artistRowId = const Value.absent(),
    Value<String?> genre = const Value.absent(),
    Value<int?> year = const Value.absent(),
    Value<int?> trackNumber = const Value.absent(),
    Value<int?> discNumber = const Value.absent(),
    int? durationMs,
    int? dateModifiedSec,
    Value<int?> dateAddedSec = const Value.absent(),
    Value<int?> sizeBytes = const Value.absent(),
    Value<String?> format = const Value.absent(),
  }) => Song(
    id: id ?? this.id,
    mediaStoreId: mediaStoreId.present ? mediaStoreId.value : this.mediaStoreId,
    source: source ?? this.source,
    contentHash: contentHash.present ? contentHash.value : this.contentHash,
    contentUri: contentUri ?? this.contentUri,
    path: path.present ? path.value : this.path,
    title: title ?? this.title,
    titleSearch: titleSearch ?? this.titleSearch,
    artist: artist.present ? artist.value : this.artist,
    artistSearch: artistSearch.present ? artistSearch.value : this.artistSearch,
    albumName: albumName.present ? albumName.value : this.albumName,
    albumRowId: albumRowId.present ? albumRowId.value : this.albumRowId,
    artistRowId: artistRowId.present ? artistRowId.value : this.artistRowId,
    genre: genre.present ? genre.value : this.genre,
    year: year.present ? year.value : this.year,
    trackNumber: trackNumber.present ? trackNumber.value : this.trackNumber,
    discNumber: discNumber.present ? discNumber.value : this.discNumber,
    durationMs: durationMs ?? this.durationMs,
    dateModifiedSec: dateModifiedSec ?? this.dateModifiedSec,
    dateAddedSec: dateAddedSec.present ? dateAddedSec.value : this.dateAddedSec,
    sizeBytes: sizeBytes.present ? sizeBytes.value : this.sizeBytes,
    format: format.present ? format.value : this.format,
  );
  Song copyWithCompanion(SongsCompanion data) {
    return Song(
      id: data.id.present ? data.id.value : this.id,
      mediaStoreId: data.mediaStoreId.present
          ? data.mediaStoreId.value
          : this.mediaStoreId,
      source: data.source.present ? data.source.value : this.source,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      contentUri: data.contentUri.present
          ? data.contentUri.value
          : this.contentUri,
      path: data.path.present ? data.path.value : this.path,
      title: data.title.present ? data.title.value : this.title,
      titleSearch: data.titleSearch.present
          ? data.titleSearch.value
          : this.titleSearch,
      artist: data.artist.present ? data.artist.value : this.artist,
      artistSearch: data.artistSearch.present
          ? data.artistSearch.value
          : this.artistSearch,
      albumName: data.albumName.present ? data.albumName.value : this.albumName,
      albumRowId: data.albumRowId.present
          ? data.albumRowId.value
          : this.albumRowId,
      artistRowId: data.artistRowId.present
          ? data.artistRowId.value
          : this.artistRowId,
      genre: data.genre.present ? data.genre.value : this.genre,
      year: data.year.present ? data.year.value : this.year,
      trackNumber: data.trackNumber.present
          ? data.trackNumber.value
          : this.trackNumber,
      discNumber: data.discNumber.present
          ? data.discNumber.value
          : this.discNumber,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      dateModifiedSec: data.dateModifiedSec.present
          ? data.dateModifiedSec.value
          : this.dateModifiedSec,
      dateAddedSec: data.dateAddedSec.present
          ? data.dateAddedSec.value
          : this.dateAddedSec,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      format: data.format.present ? data.format.value : this.format,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Song(')
          ..write('id: $id, ')
          ..write('mediaStoreId: $mediaStoreId, ')
          ..write('source: $source, ')
          ..write('contentHash: $contentHash, ')
          ..write('contentUri: $contentUri, ')
          ..write('path: $path, ')
          ..write('title: $title, ')
          ..write('titleSearch: $titleSearch, ')
          ..write('artist: $artist, ')
          ..write('artistSearch: $artistSearch, ')
          ..write('albumName: $albumName, ')
          ..write('albumRowId: $albumRowId, ')
          ..write('artistRowId: $artistRowId, ')
          ..write('genre: $genre, ')
          ..write('year: $year, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('discNumber: $discNumber, ')
          ..write('durationMs: $durationMs, ')
          ..write('dateModifiedSec: $dateModifiedSec, ')
          ..write('dateAddedSec: $dateAddedSec, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('format: $format')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    mediaStoreId,
    source,
    contentHash,
    contentUri,
    path,
    title,
    titleSearch,
    artist,
    artistSearch,
    albumName,
    albumRowId,
    artistRowId,
    genre,
    year,
    trackNumber,
    discNumber,
    durationMs,
    dateModifiedSec,
    dateAddedSec,
    sizeBytes,
    format,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Song &&
          other.id == this.id &&
          other.mediaStoreId == this.mediaStoreId &&
          other.source == this.source &&
          other.contentHash == this.contentHash &&
          other.contentUri == this.contentUri &&
          other.path == this.path &&
          other.title == this.title &&
          other.titleSearch == this.titleSearch &&
          other.artist == this.artist &&
          other.artistSearch == this.artistSearch &&
          other.albumName == this.albumName &&
          other.albumRowId == this.albumRowId &&
          other.artistRowId == this.artistRowId &&
          other.genre == this.genre &&
          other.year == this.year &&
          other.trackNumber == this.trackNumber &&
          other.discNumber == this.discNumber &&
          other.durationMs == this.durationMs &&
          other.dateModifiedSec == this.dateModifiedSec &&
          other.dateAddedSec == this.dateAddedSec &&
          other.sizeBytes == this.sizeBytes &&
          other.format == this.format);
}

class SongsCompanion extends UpdateCompanion<Song> {
  final Value<int> id;
  final Value<int?> mediaStoreId;
  final Value<String> source;
  final Value<String?> contentHash;
  final Value<String> contentUri;
  final Value<String?> path;
  final Value<String> title;
  final Value<String> titleSearch;
  final Value<String?> artist;
  final Value<String?> artistSearch;
  final Value<String?> albumName;
  final Value<int?> albumRowId;
  final Value<int?> artistRowId;
  final Value<String?> genre;
  final Value<int?> year;
  final Value<int?> trackNumber;
  final Value<int?> discNumber;
  final Value<int> durationMs;
  final Value<int> dateModifiedSec;
  final Value<int?> dateAddedSec;
  final Value<int?> sizeBytes;
  final Value<String?> format;
  const SongsCompanion({
    this.id = const Value.absent(),
    this.mediaStoreId = const Value.absent(),
    this.source = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.contentUri = const Value.absent(),
    this.path = const Value.absent(),
    this.title = const Value.absent(),
    this.titleSearch = const Value.absent(),
    this.artist = const Value.absent(),
    this.artistSearch = const Value.absent(),
    this.albumName = const Value.absent(),
    this.albumRowId = const Value.absent(),
    this.artistRowId = const Value.absent(),
    this.genre = const Value.absent(),
    this.year = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.discNumber = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.dateModifiedSec = const Value.absent(),
    this.dateAddedSec = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.format = const Value.absent(),
  });
  SongsCompanion.insert({
    this.id = const Value.absent(),
    this.mediaStoreId = const Value.absent(),
    this.source = const Value.absent(),
    this.contentHash = const Value.absent(),
    required String contentUri,
    this.path = const Value.absent(),
    required String title,
    required String titleSearch,
    this.artist = const Value.absent(),
    this.artistSearch = const Value.absent(),
    this.albumName = const Value.absent(),
    this.albumRowId = const Value.absent(),
    this.artistRowId = const Value.absent(),
    this.genre = const Value.absent(),
    this.year = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.discNumber = const Value.absent(),
    required int durationMs,
    required int dateModifiedSec,
    this.dateAddedSec = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.format = const Value.absent(),
  }) : contentUri = Value(contentUri),
       title = Value(title),
       titleSearch = Value(titleSearch),
       durationMs = Value(durationMs),
       dateModifiedSec = Value(dateModifiedSec);
  static Insertable<Song> custom({
    Expression<int>? id,
    Expression<int>? mediaStoreId,
    Expression<String>? source,
    Expression<String>? contentHash,
    Expression<String>? contentUri,
    Expression<String>? path,
    Expression<String>? title,
    Expression<String>? titleSearch,
    Expression<String>? artist,
    Expression<String>? artistSearch,
    Expression<String>? albumName,
    Expression<int>? albumRowId,
    Expression<int>? artistRowId,
    Expression<String>? genre,
    Expression<int>? year,
    Expression<int>? trackNumber,
    Expression<int>? discNumber,
    Expression<int>? durationMs,
    Expression<int>? dateModifiedSec,
    Expression<int>? dateAddedSec,
    Expression<int>? sizeBytes,
    Expression<String>? format,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mediaStoreId != null) 'media_store_id': mediaStoreId,
      if (source != null) 'source': source,
      if (contentHash != null) 'content_hash': contentHash,
      if (contentUri != null) 'content_uri': contentUri,
      if (path != null) 'path': path,
      if (title != null) 'title': title,
      if (titleSearch != null) 'title_search': titleSearch,
      if (artist != null) 'artist': artist,
      if (artistSearch != null) 'artist_search': artistSearch,
      if (albumName != null) 'album_name': albumName,
      if (albumRowId != null) 'album_row_id': albumRowId,
      if (artistRowId != null) 'artist_row_id': artistRowId,
      if (genre != null) 'genre': genre,
      if (year != null) 'year': year,
      if (trackNumber != null) 'track_number': trackNumber,
      if (discNumber != null) 'disc_number': discNumber,
      if (durationMs != null) 'duration_ms': durationMs,
      if (dateModifiedSec != null) 'date_modified_sec': dateModifiedSec,
      if (dateAddedSec != null) 'date_added_sec': dateAddedSec,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (format != null) 'format': format,
    });
  }

  SongsCompanion copyWith({
    Value<int>? id,
    Value<int?>? mediaStoreId,
    Value<String>? source,
    Value<String?>? contentHash,
    Value<String>? contentUri,
    Value<String?>? path,
    Value<String>? title,
    Value<String>? titleSearch,
    Value<String?>? artist,
    Value<String?>? artistSearch,
    Value<String?>? albumName,
    Value<int?>? albumRowId,
    Value<int?>? artistRowId,
    Value<String?>? genre,
    Value<int?>? year,
    Value<int?>? trackNumber,
    Value<int?>? discNumber,
    Value<int>? durationMs,
    Value<int>? dateModifiedSec,
    Value<int?>? dateAddedSec,
    Value<int?>? sizeBytes,
    Value<String?>? format,
  }) {
    return SongsCompanion(
      id: id ?? this.id,
      mediaStoreId: mediaStoreId ?? this.mediaStoreId,
      source: source ?? this.source,
      contentHash: contentHash ?? this.contentHash,
      contentUri: contentUri ?? this.contentUri,
      path: path ?? this.path,
      title: title ?? this.title,
      titleSearch: titleSearch ?? this.titleSearch,
      artist: artist ?? this.artist,
      artistSearch: artistSearch ?? this.artistSearch,
      albumName: albumName ?? this.albumName,
      albumRowId: albumRowId ?? this.albumRowId,
      artistRowId: artistRowId ?? this.artistRowId,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      durationMs: durationMs ?? this.durationMs,
      dateModifiedSec: dateModifiedSec ?? this.dateModifiedSec,
      dateAddedSec: dateAddedSec ?? this.dateAddedSec,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      format: format ?? this.format,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (mediaStoreId.present) {
      map['media_store_id'] = Variable<int>(mediaStoreId.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (contentUri.present) {
      map['content_uri'] = Variable<String>(contentUri.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (titleSearch.present) {
      map['title_search'] = Variable<String>(titleSearch.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (artistSearch.present) {
      map['artist_search'] = Variable<String>(artistSearch.value);
    }
    if (albumName.present) {
      map['album_name'] = Variable<String>(albumName.value);
    }
    if (albumRowId.present) {
      map['album_row_id'] = Variable<int>(albumRowId.value);
    }
    if (artistRowId.present) {
      map['artist_row_id'] = Variable<int>(artistRowId.value);
    }
    if (genre.present) {
      map['genre'] = Variable<String>(genre.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (trackNumber.present) {
      map['track_number'] = Variable<int>(trackNumber.value);
    }
    if (discNumber.present) {
      map['disc_number'] = Variable<int>(discNumber.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (dateModifiedSec.present) {
      map['date_modified_sec'] = Variable<int>(dateModifiedSec.value);
    }
    if (dateAddedSec.present) {
      map['date_added_sec'] = Variable<int>(dateAddedSec.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SongsCompanion(')
          ..write('id: $id, ')
          ..write('mediaStoreId: $mediaStoreId, ')
          ..write('source: $source, ')
          ..write('contentHash: $contentHash, ')
          ..write('contentUri: $contentUri, ')
          ..write('path: $path, ')
          ..write('title: $title, ')
          ..write('titleSearch: $titleSearch, ')
          ..write('artist: $artist, ')
          ..write('artistSearch: $artistSearch, ')
          ..write('albumName: $albumName, ')
          ..write('albumRowId: $albumRowId, ')
          ..write('artistRowId: $artistRowId, ')
          ..write('genre: $genre, ')
          ..write('year: $year, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('discNumber: $discNumber, ')
          ..write('durationMs: $durationMs, ')
          ..write('dateModifiedSec: $dateModifiedSec, ')
          ..write('dateAddedSec: $dateAddedSec, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('format: $format')
          ..write(')'))
        .toString();
  }
}

class $SongStatsTable extends SongStats
    with TableInfo<$SongStatsTable, SongStat> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SongStatsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<int> songId = GeneratedColumn<int>(
    'song_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _playCountMeta = const VerificationMeta(
    'playCount',
  );
  @override
  late final GeneratedColumn<int> playCount = GeneratedColumn<int>(
    'play_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastPlayedAtMeta = const VerificationMeta(
    'lastPlayedAt',
  );
  @override
  late final GeneratedColumn<int> lastPlayedAt = GeneratedColumn<int>(
    'last_played_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _moodMeta = const VerificationMeta('mood');
  @override
  late final GeneratedColumn<String> mood = GeneratedColumn<String>(
    'mood',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    songId,
    isFavorite,
    playCount,
    lastPlayedAt,
    mood,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'song_stats';
  @override
  VerificationContext validateIntegrity(
    Insertable<SongStat> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    if (data.containsKey('play_count')) {
      context.handle(
        _playCountMeta,
        playCount.isAcceptableOrUnknown(data['play_count']!, _playCountMeta),
      );
    }
    if (data.containsKey('last_played_at')) {
      context.handle(
        _lastPlayedAtMeta,
        lastPlayedAt.isAcceptableOrUnknown(
          data['last_played_at']!,
          _lastPlayedAtMeta,
        ),
      );
    }
    if (data.containsKey('mood')) {
      context.handle(
        _moodMeta,
        mood.isAcceptableOrUnknown(data['mood']!, _moodMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {songId};
  @override
  SongStat map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SongStat(
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}song_id'],
      )!,
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      playCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}play_count'],
      )!,
      lastPlayedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_played_at'],
      ),
      mood: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mood'],
      ),
    );
  }

  @override
  $SongStatsTable createAlias(String alias) {
    return $SongStatsTable(attachedDatabase, alias);
  }
}

class SongStat extends DataClass implements Insertable<SongStat> {
  final int songId;
  final bool isFavorite;
  final int playCount;
  final int? lastPlayedAt;
  final String? mood;
  const SongStat({
    required this.songId,
    required this.isFavorite,
    required this.playCount,
    this.lastPlayedAt,
    this.mood,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['song_id'] = Variable<int>(songId);
    map['is_favorite'] = Variable<bool>(isFavorite);
    map['play_count'] = Variable<int>(playCount);
    if (!nullToAbsent || lastPlayedAt != null) {
      map['last_played_at'] = Variable<int>(lastPlayedAt);
    }
    if (!nullToAbsent || mood != null) {
      map['mood'] = Variable<String>(mood);
    }
    return map;
  }

  SongStatsCompanion toCompanion(bool nullToAbsent) {
    return SongStatsCompanion(
      songId: Value(songId),
      isFavorite: Value(isFavorite),
      playCount: Value(playCount),
      lastPlayedAt: lastPlayedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPlayedAt),
      mood: mood == null && nullToAbsent ? const Value.absent() : Value(mood),
    );
  }

  factory SongStat.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SongStat(
      songId: serializer.fromJson<int>(json['songId']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      playCount: serializer.fromJson<int>(json['playCount']),
      lastPlayedAt: serializer.fromJson<int?>(json['lastPlayedAt']),
      mood: serializer.fromJson<String?>(json['mood']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'songId': serializer.toJson<int>(songId),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'playCount': serializer.toJson<int>(playCount),
      'lastPlayedAt': serializer.toJson<int?>(lastPlayedAt),
      'mood': serializer.toJson<String?>(mood),
    };
  }

  SongStat copyWith({
    int? songId,
    bool? isFavorite,
    int? playCount,
    Value<int?> lastPlayedAt = const Value.absent(),
    Value<String?> mood = const Value.absent(),
  }) => SongStat(
    songId: songId ?? this.songId,
    isFavorite: isFavorite ?? this.isFavorite,
    playCount: playCount ?? this.playCount,
    lastPlayedAt: lastPlayedAt.present ? lastPlayedAt.value : this.lastPlayedAt,
    mood: mood.present ? mood.value : this.mood,
  );
  SongStat copyWithCompanion(SongStatsCompanion data) {
    return SongStat(
      songId: data.songId.present ? data.songId.value : this.songId,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      playCount: data.playCount.present ? data.playCount.value : this.playCount,
      lastPlayedAt: data.lastPlayedAt.present
          ? data.lastPlayedAt.value
          : this.lastPlayedAt,
      mood: data.mood.present ? data.mood.value : this.mood,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SongStat(')
          ..write('songId: $songId, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('playCount: $playCount, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('mood: $mood')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(songId, isFavorite, playCount, lastPlayedAt, mood);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SongStat &&
          other.songId == this.songId &&
          other.isFavorite == this.isFavorite &&
          other.playCount == this.playCount &&
          other.lastPlayedAt == this.lastPlayedAt &&
          other.mood == this.mood);
}

class SongStatsCompanion extends UpdateCompanion<SongStat> {
  final Value<int> songId;
  final Value<bool> isFavorite;
  final Value<int> playCount;
  final Value<int?> lastPlayedAt;
  final Value<String?> mood;
  const SongStatsCompanion({
    this.songId = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.playCount = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.mood = const Value.absent(),
  });
  SongStatsCompanion.insert({
    this.songId = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.playCount = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.mood = const Value.absent(),
  });
  static Insertable<SongStat> custom({
    Expression<int>? songId,
    Expression<bool>? isFavorite,
    Expression<int>? playCount,
    Expression<int>? lastPlayedAt,
    Expression<String>? mood,
  }) {
    return RawValuesInsertable({
      if (songId != null) 'song_id': songId,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (playCount != null) 'play_count': playCount,
      if (lastPlayedAt != null) 'last_played_at': lastPlayedAt,
      if (mood != null) 'mood': mood,
    });
  }

  SongStatsCompanion copyWith({
    Value<int>? songId,
    Value<bool>? isFavorite,
    Value<int>? playCount,
    Value<int?>? lastPlayedAt,
    Value<String?>? mood,
  }) {
    return SongStatsCompanion(
      songId: songId ?? this.songId,
      isFavorite: isFavorite ?? this.isFavorite,
      playCount: playCount ?? this.playCount,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      mood: mood ?? this.mood,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (songId.present) {
      map['song_id'] = Variable<int>(songId.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (playCount.present) {
      map['play_count'] = Variable<int>(playCount.value);
    }
    if (lastPlayedAt.present) {
      map['last_played_at'] = Variable<int>(lastPlayedAt.value);
    }
    if (mood.present) {
      map['mood'] = Variable<String>(mood.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SongStatsCompanion(')
          ..write('songId: $songId, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('playCount: $playCount, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('mood: $mood')
          ..write(')'))
        .toString();
  }
}

class $PlaylistsTable extends Playlists
    with TableInfo<$PlaylistsTable, Playlist> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    pinned,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlists';
  @override
  VerificationContext validateIntegrity(
    Insertable<Playlist> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Playlist map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Playlist(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PlaylistsTable createAlias(String alias) {
    return $PlaylistsTable(attachedDatabase, alias);
  }
}

class Playlist extends DataClass implements Insertable<Playlist> {
  final int id;
  final String name;
  final bool pinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Playlist({
    required this.id,
    required this.name,
    required this.pinned,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['pinned'] = Variable<bool>(pinned);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PlaylistsCompanion toCompanion(bool nullToAbsent) {
    return PlaylistsCompanion(
      id: Value(id),
      name: Value(name),
      pinned: Value(pinned),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Playlist.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Playlist(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'pinned': serializer.toJson<bool>(pinned),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Playlist copyWith({
    int? id,
    String? name,
    bool? pinned,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Playlist(
    id: id ?? this.id,
    name: name ?? this.name,
    pinned: pinned ?? this.pinned,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Playlist copyWithCompanion(PlaylistsCompanion data) {
    return Playlist(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Playlist(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('pinned: $pinned, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, pinned, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Playlist &&
          other.id == this.id &&
          other.name == this.name &&
          other.pinned == this.pinned &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PlaylistsCompanion extends UpdateCompanion<Playlist> {
  final Value<int> id;
  final Value<String> name;
  final Value<bool> pinned;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const PlaylistsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.pinned = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  PlaylistsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.pinned = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Playlist> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<bool>? pinned,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (pinned != null) 'pinned': pinned,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  PlaylistsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<bool>? pinned,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return PlaylistsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      pinned: pinned ?? this.pinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('pinned: $pinned, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $PlaylistSongsTable extends PlaylistSongs
    with TableInfo<$PlaylistSongsTable, PlaylistSong> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistSongsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<int> playlistId = GeneratedColumn<int>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES playlists (id)',
    ),
  );
  static const VerificationMeta _songRowIdMeta = const VerificationMeta(
    'songRowId',
  );
  @override
  late final GeneratedColumn<int> songRowId = GeneratedColumn<int>(
    'song_row_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES songs (id)',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, playlistId, songRowId, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlist_songs';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaylistSong> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('song_row_id')) {
      context.handle(
        _songRowIdMeta,
        songRowId.isAcceptableOrUnknown(data['song_row_id']!, _songRowIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songRowIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlaylistSong map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistSong(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}playlist_id'],
      )!,
      songRowId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}song_row_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $PlaylistSongsTable createAlias(String alias) {
    return $PlaylistSongsTable(attachedDatabase, alias);
  }
}

class PlaylistSong extends DataClass implements Insertable<PlaylistSong> {
  final int id;
  final int playlistId;
  final int songRowId;
  final int position;
  const PlaylistSong({
    required this.id,
    required this.playlistId,
    required this.songRowId,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['playlist_id'] = Variable<int>(playlistId);
    map['song_row_id'] = Variable<int>(songRowId);
    map['position'] = Variable<int>(position);
    return map;
  }

  PlaylistSongsCompanion toCompanion(bool nullToAbsent) {
    return PlaylistSongsCompanion(
      id: Value(id),
      playlistId: Value(playlistId),
      songRowId: Value(songRowId),
      position: Value(position),
    );
  }

  factory PlaylistSong.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistSong(
      id: serializer.fromJson<int>(json['id']),
      playlistId: serializer.fromJson<int>(json['playlistId']),
      songRowId: serializer.fromJson<int>(json['songRowId']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'playlistId': serializer.toJson<int>(playlistId),
      'songRowId': serializer.toJson<int>(songRowId),
      'position': serializer.toJson<int>(position),
    };
  }

  PlaylistSong copyWith({
    int? id,
    int? playlistId,
    int? songRowId,
    int? position,
  }) => PlaylistSong(
    id: id ?? this.id,
    playlistId: playlistId ?? this.playlistId,
    songRowId: songRowId ?? this.songRowId,
    position: position ?? this.position,
  );
  PlaylistSong copyWithCompanion(PlaylistSongsCompanion data) {
    return PlaylistSong(
      id: data.id.present ? data.id.value : this.id,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      songRowId: data.songRowId.present ? data.songRowId.value : this.songRowId,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistSong(')
          ..write('id: $id, ')
          ..write('playlistId: $playlistId, ')
          ..write('songRowId: $songRowId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, playlistId, songRowId, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistSong &&
          other.id == this.id &&
          other.playlistId == this.playlistId &&
          other.songRowId == this.songRowId &&
          other.position == this.position);
}

class PlaylistSongsCompanion extends UpdateCompanion<PlaylistSong> {
  final Value<int> id;
  final Value<int> playlistId;
  final Value<int> songRowId;
  final Value<int> position;
  const PlaylistSongsCompanion({
    this.id = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.songRowId = const Value.absent(),
    this.position = const Value.absent(),
  });
  PlaylistSongsCompanion.insert({
    this.id = const Value.absent(),
    required int playlistId,
    required int songRowId,
    required int position,
  }) : playlistId = Value(playlistId),
       songRowId = Value(songRowId),
       position = Value(position);
  static Insertable<PlaylistSong> custom({
    Expression<int>? id,
    Expression<int>? playlistId,
    Expression<int>? songRowId,
    Expression<int>? position,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (playlistId != null) 'playlist_id': playlistId,
      if (songRowId != null) 'song_row_id': songRowId,
      if (position != null) 'position': position,
    });
  }

  PlaylistSongsCompanion copyWith({
    Value<int>? id,
    Value<int>? playlistId,
    Value<int>? songRowId,
    Value<int>? position,
  }) {
    return PlaylistSongsCompanion(
      id: id ?? this.id,
      playlistId: playlistId ?? this.playlistId,
      songRowId: songRowId ?? this.songRowId,
      position: position ?? this.position,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<int>(playlistId.value);
    }
    if (songRowId.present) {
      map['song_row_id'] = Variable<int>(songRowId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistSongsCompanion(')
          ..write('id: $id, ')
          ..write('playlistId: $playlistId, ')
          ..write('songRowId: $songRowId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }
}

class $KvEntriesTable extends KvEntries
    with TableInfo<$KvEntriesTable, KvEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KvEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueTextMeta = const VerificationMeta(
    'valueText',
  );
  @override
  late final GeneratedColumn<String> valueText = GeneratedColumn<String>(
    'value_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [key, valueText];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'kv_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<KvEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value_text')) {
      context.handle(
        _valueTextMeta,
        valueText.isAcceptableOrUnknown(data['value_text']!, _valueTextMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  KvEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KvEntry(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      valueText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_text'],
      ),
    );
  }

  @override
  $KvEntriesTable createAlias(String alias) {
    return $KvEntriesTable(attachedDatabase, alias);
  }
}

class KvEntry extends DataClass implements Insertable<KvEntry> {
  final String key;
  final String? valueText;
  const KvEntry({required this.key, this.valueText});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    if (!nullToAbsent || valueText != null) {
      map['value_text'] = Variable<String>(valueText);
    }
    return map;
  }

  KvEntriesCompanion toCompanion(bool nullToAbsent) {
    return KvEntriesCompanion(
      key: Value(key),
      valueText: valueText == null && nullToAbsent
          ? const Value.absent()
          : Value(valueText),
    );
  }

  factory KvEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KvEntry(
      key: serializer.fromJson<String>(json['key']),
      valueText: serializer.fromJson<String?>(json['valueText']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'valueText': serializer.toJson<String?>(valueText),
    };
  }

  KvEntry copyWith({
    String? key,
    Value<String?> valueText = const Value.absent(),
  }) => KvEntry(
    key: key ?? this.key,
    valueText: valueText.present ? valueText.value : this.valueText,
  );
  KvEntry copyWithCompanion(KvEntriesCompanion data) {
    return KvEntry(
      key: data.key.present ? data.key.value : this.key,
      valueText: data.valueText.present ? data.valueText.value : this.valueText,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KvEntry(')
          ..write('key: $key, ')
          ..write('valueText: $valueText')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, valueText);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KvEntry &&
          other.key == this.key &&
          other.valueText == this.valueText);
}

class KvEntriesCompanion extends UpdateCompanion<KvEntry> {
  final Value<String> key;
  final Value<String?> valueText;
  final Value<int> rowid;
  const KvEntriesCompanion({
    this.key = const Value.absent(),
    this.valueText = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KvEntriesCompanion.insert({
    required String key,
    this.valueText = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key);
  static Insertable<KvEntry> custom({
    Expression<String>? key,
    Expression<String>? valueText,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (valueText != null) 'value_text': valueText,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KvEntriesCompanion copyWith({
    Value<String>? key,
    Value<String?>? valueText,
    Value<int>? rowid,
  }) {
    return KvEntriesCompanion(
      key: key ?? this.key,
      valueText: valueText ?? this.valueText,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (valueText.present) {
      map['value_text'] = Variable<String>(valueText.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KvEntriesCompanion(')
          ..write('key: $key, ')
          ..write('valueText: $valueText, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ScanStatesTable extends ScanStates
    with TableInfo<$ScanStatesTable, ScanStateEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScanStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastCompletedAtMeta = const VerificationMeta(
    'lastCompletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastCompletedAt =
      GeneratedColumn<DateTime>(
        'last_completed_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _totalSongsMeta = const VerificationMeta(
    'totalSongs',
  );
  @override
  late final GeneratedColumn<int> totalSongs = GeneratedColumn<int>(
    'total_songs',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _schemaVersionMeta = const VerificationMeta(
    'schemaVersion',
  );
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
    'schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    source,
    lastCompletedAt,
    totalSongs,
    schemaVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scan_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScanStateEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('last_completed_at')) {
      context.handle(
        _lastCompletedAtMeta,
        lastCompletedAt.isAcceptableOrUnknown(
          data['last_completed_at']!,
          _lastCompletedAtMeta,
        ),
      );
    }
    if (data.containsKey('total_songs')) {
      context.handle(
        _totalSongsMeta,
        totalSongs.isAcceptableOrUnknown(data['total_songs']!, _totalSongsMeta),
      );
    }
    if (data.containsKey('schema_version')) {
      context.handle(
        _schemaVersionMeta,
        schemaVersion.isAcceptableOrUnknown(
          data['schema_version']!,
          _schemaVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {source};
  @override
  ScanStateEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScanStateEntry(
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      lastCompletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_completed_at'],
      ),
      totalSongs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_songs'],
      ),
      schemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_version'],
      )!,
    );
  }

  @override
  $ScanStatesTable createAlias(String alias) {
    return $ScanStatesTable(attachedDatabase, alias);
  }
}

class ScanStateEntry extends DataClass implements Insertable<ScanStateEntry> {
  final String source;
  final DateTime? lastCompletedAt;
  final int? totalSongs;
  final int schemaVersion;
  const ScanStateEntry({
    required this.source,
    this.lastCompletedAt,
    this.totalSongs,
    required this.schemaVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || lastCompletedAt != null) {
      map['last_completed_at'] = Variable<DateTime>(lastCompletedAt);
    }
    if (!nullToAbsent || totalSongs != null) {
      map['total_songs'] = Variable<int>(totalSongs);
    }
    map['schema_version'] = Variable<int>(schemaVersion);
    return map;
  }

  ScanStatesCompanion toCompanion(bool nullToAbsent) {
    return ScanStatesCompanion(
      source: Value(source),
      lastCompletedAt: lastCompletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCompletedAt),
      totalSongs: totalSongs == null && nullToAbsent
          ? const Value.absent()
          : Value(totalSongs),
      schemaVersion: Value(schemaVersion),
    );
  }

  factory ScanStateEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScanStateEntry(
      source: serializer.fromJson<String>(json['source']),
      lastCompletedAt: serializer.fromJson<DateTime?>(json['lastCompletedAt']),
      totalSongs: serializer.fromJson<int?>(json['totalSongs']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'source': serializer.toJson<String>(source),
      'lastCompletedAt': serializer.toJson<DateTime?>(lastCompletedAt),
      'totalSongs': serializer.toJson<int?>(totalSongs),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
    };
  }

  ScanStateEntry copyWith({
    String? source,
    Value<DateTime?> lastCompletedAt = const Value.absent(),
    Value<int?> totalSongs = const Value.absent(),
    int? schemaVersion,
  }) => ScanStateEntry(
    source: source ?? this.source,
    lastCompletedAt: lastCompletedAt.present
        ? lastCompletedAt.value
        : this.lastCompletedAt,
    totalSongs: totalSongs.present ? totalSongs.value : this.totalSongs,
    schemaVersion: schemaVersion ?? this.schemaVersion,
  );
  ScanStateEntry copyWithCompanion(ScanStatesCompanion data) {
    return ScanStateEntry(
      source: data.source.present ? data.source.value : this.source,
      lastCompletedAt: data.lastCompletedAt.present
          ? data.lastCompletedAt.value
          : this.lastCompletedAt,
      totalSongs: data.totalSongs.present
          ? data.totalSongs.value
          : this.totalSongs,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScanStateEntry(')
          ..write('source: $source, ')
          ..write('lastCompletedAt: $lastCompletedAt, ')
          ..write('totalSongs: $totalSongs, ')
          ..write('schemaVersion: $schemaVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(source, lastCompletedAt, totalSongs, schemaVersion);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScanStateEntry &&
          other.source == this.source &&
          other.lastCompletedAt == this.lastCompletedAt &&
          other.totalSongs == this.totalSongs &&
          other.schemaVersion == this.schemaVersion);
}

class ScanStatesCompanion extends UpdateCompanion<ScanStateEntry> {
  final Value<String> source;
  final Value<DateTime?> lastCompletedAt;
  final Value<int?> totalSongs;
  final Value<int> schemaVersion;
  final Value<int> rowid;
  const ScanStatesCompanion({
    this.source = const Value.absent(),
    this.lastCompletedAt = const Value.absent(),
    this.totalSongs = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ScanStatesCompanion.insert({
    required String source,
    this.lastCompletedAt = const Value.absent(),
    this.totalSongs = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : source = Value(source);
  static Insertable<ScanStateEntry> custom({
    Expression<String>? source,
    Expression<DateTime>? lastCompletedAt,
    Expression<int>? totalSongs,
    Expression<int>? schemaVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (source != null) 'source': source,
      if (lastCompletedAt != null) 'last_completed_at': lastCompletedAt,
      if (totalSongs != null) 'total_songs': totalSongs,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ScanStatesCompanion copyWith({
    Value<String>? source,
    Value<DateTime?>? lastCompletedAt,
    Value<int?>? totalSongs,
    Value<int>? schemaVersion,
    Value<int>? rowid,
  }) {
    return ScanStatesCompanion(
      source: source ?? this.source,
      lastCompletedAt: lastCompletedAt ?? this.lastCompletedAt,
      totalSongs: totalSongs ?? this.totalSongs,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (lastCompletedAt.present) {
      map['last_completed_at'] = Variable<DateTime>(lastCompletedAt.value);
    }
    if (totalSongs.present) {
      map['total_songs'] = Variable<int>(totalSongs.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScanStatesCompanion(')
          ..write('source: $source, ')
          ..write('lastCompletedAt: $lastCompletedAt, ')
          ..write('totalSongs: $totalSongs, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LyricsCacheTable extends LyricsCache
    with TableInfo<$LyricsCacheTable, LyricsCacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LyricsCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _identityKeyMeta = const VerificationMeta(
    'identityKey',
  );
  @override
  late final GeneratedColumn<String> identityKey = GeneratedColumn<String>(
    'identity_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lyricsJsonMeta = const VerificationMeta(
    'lyricsJson',
  );
  @override
  late final GeneratedColumn<String> lyricsJson = GeneratedColumn<String>(
    'lyrics_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    contentHash,
    identityKey,
    lyricsJson,
    source,
    fetchedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'lyrics_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<LyricsCacheEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentHashMeta);
    }
    if (data.containsKey('identity_key')) {
      context.handle(
        _identityKeyMeta,
        identityKey.isAcceptableOrUnknown(
          data['identity_key']!,
          _identityKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_identityKeyMeta);
    }
    if (data.containsKey('lyrics_json')) {
      context.handle(
        _lyricsJsonMeta,
        lyricsJson.isAcceptableOrUnknown(data['lyrics_json']!, _lyricsJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_lyricsJsonMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {contentHash};
  @override
  LyricsCacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LyricsCacheEntry(
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      )!,
      identityKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_key'],
      )!,
      lyricsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lyrics_json'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $LyricsCacheTable createAlias(String alias) {
    return $LyricsCacheTable(attachedDatabase, alias);
  }
}

class LyricsCacheEntry extends DataClass
    implements Insertable<LyricsCacheEntry> {
  final String contentHash;
  final String identityKey;
  final String lyricsJson;
  final String source;
  final DateTime fetchedAt;
  const LyricsCacheEntry({
    required this.contentHash,
    required this.identityKey,
    required this.lyricsJson,
    required this.source,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['content_hash'] = Variable<String>(contentHash);
    map['identity_key'] = Variable<String>(identityKey);
    map['lyrics_json'] = Variable<String>(lyricsJson);
    map['source'] = Variable<String>(source);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  LyricsCacheCompanion toCompanion(bool nullToAbsent) {
    return LyricsCacheCompanion(
      contentHash: Value(contentHash),
      identityKey: Value(identityKey),
      lyricsJson: Value(lyricsJson),
      source: Value(source),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory LyricsCacheEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LyricsCacheEntry(
      contentHash: serializer.fromJson<String>(json['contentHash']),
      identityKey: serializer.fromJson<String>(json['identityKey']),
      lyricsJson: serializer.fromJson<String>(json['lyricsJson']),
      source: serializer.fromJson<String>(json['source']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'contentHash': serializer.toJson<String>(contentHash),
      'identityKey': serializer.toJson<String>(identityKey),
      'lyricsJson': serializer.toJson<String>(lyricsJson),
      'source': serializer.toJson<String>(source),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  LyricsCacheEntry copyWith({
    String? contentHash,
    String? identityKey,
    String? lyricsJson,
    String? source,
    DateTime? fetchedAt,
  }) => LyricsCacheEntry(
    contentHash: contentHash ?? this.contentHash,
    identityKey: identityKey ?? this.identityKey,
    lyricsJson: lyricsJson ?? this.lyricsJson,
    source: source ?? this.source,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  LyricsCacheEntry copyWithCompanion(LyricsCacheCompanion data) {
    return LyricsCacheEntry(
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      identityKey: data.identityKey.present
          ? data.identityKey.value
          : this.identityKey,
      lyricsJson: data.lyricsJson.present
          ? data.lyricsJson.value
          : this.lyricsJson,
      source: data.source.present ? data.source.value : this.source,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LyricsCacheEntry(')
          ..write('contentHash: $contentHash, ')
          ..write('identityKey: $identityKey, ')
          ..write('lyricsJson: $lyricsJson, ')
          ..write('source: $source, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(contentHash, identityKey, lyricsJson, source, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LyricsCacheEntry &&
          other.contentHash == this.contentHash &&
          other.identityKey == this.identityKey &&
          other.lyricsJson == this.lyricsJson &&
          other.source == this.source &&
          other.fetchedAt == this.fetchedAt);
}

class LyricsCacheCompanion extends UpdateCompanion<LyricsCacheEntry> {
  final Value<String> contentHash;
  final Value<String> identityKey;
  final Value<String> lyricsJson;
  final Value<String> source;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const LyricsCacheCompanion({
    this.contentHash = const Value.absent(),
    this.identityKey = const Value.absent(),
    this.lyricsJson = const Value.absent(),
    this.source = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LyricsCacheCompanion.insert({
    required String contentHash,
    required String identityKey,
    required String lyricsJson,
    required String source,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : contentHash = Value(contentHash),
       identityKey = Value(identityKey),
       lyricsJson = Value(lyricsJson),
       source = Value(source),
       fetchedAt = Value(fetchedAt);
  static Insertable<LyricsCacheEntry> custom({
    Expression<String>? contentHash,
    Expression<String>? identityKey,
    Expression<String>? lyricsJson,
    Expression<String>? source,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (contentHash != null) 'content_hash': contentHash,
      if (identityKey != null) 'identity_key': identityKey,
      if (lyricsJson != null) 'lyrics_json': lyricsJson,
      if (source != null) 'source': source,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LyricsCacheCompanion copyWith({
    Value<String>? contentHash,
    Value<String>? identityKey,
    Value<String>? lyricsJson,
    Value<String>? source,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return LyricsCacheCompanion(
      contentHash: contentHash ?? this.contentHash,
      identityKey: identityKey ?? this.identityKey,
      lyricsJson: lyricsJson ?? this.lyricsJson,
      source: source ?? this.source,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (identityKey.present) {
      map['identity_key'] = Variable<String>(identityKey.value);
    }
    if (lyricsJson.present) {
      map['lyrics_json'] = Variable<String>(lyricsJson.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LyricsCacheCompanion(')
          ..write('contentHash: $contentHash, ')
          ..write('identityKey: $identityKey, ')
          ..write('lyricsJson: $lyricsJson, ')
          ..write('source: $source, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AlbumsTable albums = $AlbumsTable(this);
  late final $ArtistsTable artists = $ArtistsTable(this);
  late final $SongsTable songs = $SongsTable(this);
  late final $SongStatsTable songStats = $SongStatsTable(this);
  late final $PlaylistsTable playlists = $PlaylistsTable(this);
  late final $PlaylistSongsTable playlistSongs = $PlaylistSongsTable(this);
  late final $KvEntriesTable kvEntries = $KvEntriesTable(this);
  late final $ScanStatesTable scanStates = $ScanStatesTable(this);
  late final $LyricsCacheTable lyricsCache = $LyricsCacheTable(this);
  late final Index songsSourceMediaStoreId = Index(
    'songs_source_media_store_id',
    'CREATE UNIQUE INDEX songs_source_media_store_id ON songs (source, media_store_id)',
  );
  late final Index songsSourceContentHash = Index(
    'songs_source_content_hash',
    'CREATE UNIQUE INDEX songs_source_content_hash ON songs (source, content_hash)',
  );
  late final Index songsAlbum = Index(
    'songs_album',
    'CREATE INDEX songs_album ON songs (album_row_id)',
  );
  late final Index songsArtist = Index(
    'songs_artist',
    'CREATE INDEX songs_artist ON songs (artist_row_id)',
  );
  late final Index songsTitleSearch = Index(
    'songs_title_search',
    'CREATE INDEX songs_title_search ON songs (title_search)',
  );
  late final Index songsDateAdded = Index(
    'songs_date_added',
    'CREATE INDEX songs_date_added ON songs (date_added_sec)',
  );
  late final Index albumsMediaStoreId = Index(
    'albums_media_store_id',
    'CREATE UNIQUE INDEX albums_media_store_id ON albums (media_store_album_id)',
  );
  late final Index albumsAlbumKey = Index(
    'albums_album_key',
    'CREATE UNIQUE INDEX albums_album_key ON albums (album_key)',
  );
  late final Index artistsMediaStoreId = Index(
    'artists_media_store_id',
    'CREATE UNIQUE INDEX artists_media_store_id ON artists (media_store_artist_id)',
  );
  late final Index artistsArtistKey = Index(
    'artists_artist_key',
    'CREATE UNIQUE INDEX artists_artist_key ON artists (artist_key)',
  );
  late final Index playlistSongsPosition = Index(
    'playlist_songs_position',
    'CREATE UNIQUE INDEX playlist_songs_position ON playlist_songs (playlist_id, position)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    albums,
    artists,
    songs,
    songStats,
    playlists,
    playlistSongs,
    kvEntries,
    scanStates,
    lyricsCache,
    songsSourceMediaStoreId,
    songsSourceContentHash,
    songsAlbum,
    songsArtist,
    songsTitleSearch,
    songsDateAdded,
    albumsMediaStoreId,
    albumsAlbumKey,
    artistsMediaStoreId,
    artistsArtistKey,
    playlistSongsPosition,
  ];
}

typedef $$AlbumsTableCreateCompanionBuilder = AlbumsCompanion Function({
  Value<int> id,
  Value<int?> mediaStoreAlbumId,
  Value<String?> albumKey,
  required String name,
  Value<String?> artistName,
  Value<String?> artSmallPath,
  Value<String?> artLargePath,
});
typedef $$AlbumsTableUpdateCompanionBuilder = AlbumsCompanion Function({
  Value<int> id,
  Value<int?> mediaStoreAlbumId,
  Value<String?> albumKey,
  Value<String> name,
  Value<String?> artistName,
  Value<String?> artSmallPath,
  Value<String?> artLargePath,
});

final class $$AlbumsTableReferences
    extends BaseReferences<_$AppDatabase, $AlbumsTable, Album> {
  $$AlbumsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SongsTable, List<Song>> _songsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.songs,
    aliasName: 'albums__id__songs__album_row_id',
  );

  $$SongsTableProcessedTableManager get songsRefs {
    final manager = $$SongsTableTableManager(
      $_db,
      $_db.songs,
    ).filter((f) => f.albumRowId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_songsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$AlbumsTableFilterComposer
    extends Composer<_$AppDatabase, $AlbumsTable> {
  $$AlbumsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mediaStoreAlbumId => $composableBuilder(
    column: $table.mediaStoreAlbumId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumKey => $composableBuilder(
    column: $table.albumKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artistName => $composableBuilder(
    column: $table.artistName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artSmallPath => $composableBuilder(
    column: $table.artSmallPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artLargePath => $composableBuilder(
    column: $table.artLargePath,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> songsRefs(
    Expression<bool> Function($$SongsTableFilterComposer f) f,
  ) {
    final $$SongsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.songs,
      getReferencedColumn: (t) => t.albumRowId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongsTableFilterComposer(
            $db: $db,
            $table: $db.songs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AlbumsTableOrderingComposer
    extends Composer<_$AppDatabase, $AlbumsTable> {
  $$AlbumsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mediaStoreAlbumId => $composableBuilder(
    column: $table.mediaStoreAlbumId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumKey => $composableBuilder(
    column: $table.albumKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artistName => $composableBuilder(
    column: $table.artistName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artSmallPath => $composableBuilder(
    column: $table.artSmallPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artLargePath => $composableBuilder(
    column: $table.artLargePath,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AlbumsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AlbumsTable> {
  $$AlbumsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get mediaStoreAlbumId => $composableBuilder(
    column: $table.mediaStoreAlbumId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get albumKey =>
      $composableBuilder(column: $table.albumKey, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get artistName => $composableBuilder(
    column: $table.artistName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get artSmallPath => $composableBuilder(
    column: $table.artSmallPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get artLargePath => $composableBuilder(
    column: $table.artLargePath,
    builder: (column) => column,
  );

  Expression<T> songsRefs<T extends Object>(
    Expression<T> Function($$SongsTableAnnotationComposer a) f,
  ) {
    final $$SongsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.songs,
      getReferencedColumn: (t) => t.albumRowId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongsTableAnnotationComposer(
            $db: $db,
            $table: $db.songs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AlbumsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AlbumsTable,
          Album,
          $$AlbumsTableFilterComposer,
          $$AlbumsTableOrderingComposer,
          $$AlbumsTableAnnotationComposer,
          $$AlbumsTableCreateCompanionBuilder,
          $$AlbumsTableUpdateCompanionBuilder,
          (Album, $$AlbumsTableReferences),
          Album,
          PrefetchHooks Function({bool songsRefs})
        > {
  $$AlbumsTableTableManager(_$AppDatabase db, $AlbumsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlbumsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlbumsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlbumsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> mediaStoreAlbumId = const Value.absent(),
                Value<String?> albumKey = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> artistName = const Value.absent(),
                Value<String?> artSmallPath = const Value.absent(),
                Value<String?> artLargePath = const Value.absent(),
              }) => AlbumsCompanion(
                id: id,
                mediaStoreAlbumId: mediaStoreAlbumId,
                albumKey: albumKey,
                name: name,
                artistName: artistName,
                artSmallPath: artSmallPath,
                artLargePath: artLargePath,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> mediaStoreAlbumId = const Value.absent(),
                Value<String?> albumKey = const Value.absent(),
                required String name,
                Value<String?> artistName = const Value.absent(),
                Value<String?> artSmallPath = const Value.absent(),
                Value<String?> artLargePath = const Value.absent(),
              }) => AlbumsCompanion.insert(
                id: id,
                mediaStoreAlbumId: mediaStoreAlbumId,
                albumKey: albumKey,
                name: name,
                artistName: artistName,
                artSmallPath: artSmallPath,
                artLargePath: artLargePath,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$AlbumsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({songsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (songsRefs) db.songs],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (songsRefs)
                    await $_getPrefetchedData<Album, $AlbumsTable, Song>(
                      currentTable: table,
                      referencedTable: $$AlbumsTableReferences._songsRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $$AlbumsTableReferences(db, table, p0).songsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.albumRowId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$AlbumsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AlbumsTable,
      Album,
      $$AlbumsTableFilterComposer,
      $$AlbumsTableOrderingComposer,
      $$AlbumsTableAnnotationComposer,
      $$AlbumsTableCreateCompanionBuilder,
      $$AlbumsTableUpdateCompanionBuilder,
      (Album, $$AlbumsTableReferences),
      Album,
      PrefetchHooks Function({bool songsRefs})
    >;
typedef $$ArtistsTableCreateCompanionBuilder = ArtistsCompanion Function({
  Value<int> id,
  Value<int?> mediaStoreArtistId,
  Value<String?> artistKey,
  required String name,
});
typedef $$ArtistsTableUpdateCompanionBuilder = ArtistsCompanion Function({
  Value<int> id,
  Value<int?> mediaStoreArtistId,
  Value<String?> artistKey,
  Value<String> name,
});

final class $$ArtistsTableReferences
    extends BaseReferences<_$AppDatabase, $ArtistsTable, Artist> {
  $$ArtistsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SongsTable, List<Song>> _songsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.songs,
    aliasName: 'artists__id__songs__artist_row_id',
  );

  $$SongsTableProcessedTableManager get songsRefs {
    final manager = $$SongsTableTableManager(
      $_db,
      $_db.songs,
    ).filter((f) => f.artistRowId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_songsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ArtistsTableFilterComposer
    extends Composer<_$AppDatabase, $ArtistsTable> {
  $$ArtistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mediaStoreArtistId => $composableBuilder(
    column: $table.mediaStoreArtistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artistKey => $composableBuilder(
    column: $table.artistKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> songsRefs(
    Expression<bool> Function($$SongsTableFilterComposer f) f,
  ) {
    final $$SongsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.songs,
      getReferencedColumn: (t) => t.artistRowId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongsTableFilterComposer(
            $db: $db,
            $table: $db.songs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ArtistsTableOrderingComposer
    extends Composer<_$AppDatabase, $ArtistsTable> {
  $$ArtistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mediaStoreArtistId => $composableBuilder(
    column: $table.mediaStoreArtistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artistKey => $composableBuilder(
    column: $table.artistKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ArtistsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ArtistsTable> {
  $$ArtistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get mediaStoreArtistId => $composableBuilder(
    column: $table.mediaStoreArtistId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get artistKey =>
      $composableBuilder(column: $table.artistKey, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  Expression<T> songsRefs<T extends Object>(
    Expression<T> Function($$SongsTableAnnotationComposer a) f,
  ) {
    final $$SongsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.songs,
      getReferencedColumn: (t) => t.artistRowId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongsTableAnnotationComposer(
            $db: $db,
            $table: $db.songs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ArtistsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ArtistsTable,
          Artist,
          $$ArtistsTableFilterComposer,
          $$ArtistsTableOrderingComposer,
          $$ArtistsTableAnnotationComposer,
          $$ArtistsTableCreateCompanionBuilder,
          $$ArtistsTableUpdateCompanionBuilder,
          (Artist, $$ArtistsTableReferences),
          Artist,
          PrefetchHooks Function({bool songsRefs})
        > {
  $$ArtistsTableTableManager(_$AppDatabase db, $ArtistsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ArtistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ArtistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ArtistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> mediaStoreArtistId = const Value.absent(),
                Value<String?> artistKey = const Value.absent(),
                Value<String> name = const Value.absent(),
              }) => ArtistsCompanion(
                id: id,
                mediaStoreArtistId: mediaStoreArtistId,
                artistKey: artistKey,
                name: name,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> mediaStoreArtistId = const Value.absent(),
                Value<String?> artistKey = const Value.absent(),
                required String name,
              }) => ArtistsCompanion.insert(
                id: id,
                mediaStoreArtistId: mediaStoreArtistId,
                artistKey: artistKey,
                name: name,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ArtistsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({songsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (songsRefs) db.songs],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (songsRefs)
                    await $_getPrefetchedData<Artist, $ArtistsTable, Song>(
                      currentTable: table,
                      referencedTable: $$ArtistsTableReferences._songsRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $$ArtistsTableReferences(db, table, p0).songsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.artistRowId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ArtistsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ArtistsTable,
      Artist,
      $$ArtistsTableFilterComposer,
      $$ArtistsTableOrderingComposer,
      $$ArtistsTableAnnotationComposer,
      $$ArtistsTableCreateCompanionBuilder,
      $$ArtistsTableUpdateCompanionBuilder,
      (Artist, $$ArtistsTableReferences),
      Artist,
      PrefetchHooks Function({bool songsRefs})
    >;
typedef $$SongsTableCreateCompanionBuilder = SongsCompanion Function({
  Value<int> id,
  Value<int?> mediaStoreId,
  Value<String> source,
  Value<String?> contentHash,
  required String contentUri,
  Value<String?> path,
  required String title,
  required String titleSearch,
  Value<String?> artist,
  Value<String?> artistSearch,
  Value<String?> albumName,
  Value<int?> albumRowId,
  Value<int?> artistRowId,
  Value<String?> genre,
  Value<int?> year,
  Value<int?> trackNumber,
  Value<int?> discNumber,
  required int durationMs,
  required int dateModifiedSec,
  Value<int?> dateAddedSec,
  Value<int?> sizeBytes,
  Value<String?> format,
});
typedef $$SongsTableUpdateCompanionBuilder = SongsCompanion Function({
  Value<int> id,
  Value<int?> mediaStoreId,
  Value<String> source,
  Value<String?> contentHash,
  Value<String> contentUri,
  Value<String?> path,
  Value<String> title,
  Value<String> titleSearch,
  Value<String?> artist,
  Value<String?> artistSearch,
  Value<String?> albumName,
  Value<int?> albumRowId,
  Value<int?> artistRowId,
  Value<String?> genre,
  Value<int?> year,
  Value<int?> trackNumber,
  Value<int?> discNumber,
  Value<int> durationMs,
  Value<int> dateModifiedSec,
  Value<int?> dateAddedSec,
  Value<int?> sizeBytes,
  Value<String?> format,
});

final class $$SongsTableReferences
    extends BaseReferences<_$AppDatabase, $SongsTable, Song> {
  $$SongsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AlbumsTable _albumRowIdTable(_$AppDatabase db) =>
      db.albums.createAlias('songs__album_row_id__albums__id');

  $$AlbumsTableProcessedTableManager? get albumRowId {
    final $_column = $_itemColumn<int>('album_row_id');
    if ($_column == null) return null;
    final manager = $$AlbumsTableTableManager(
      $_db,
      $_db.albums,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_albumRowIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ArtistsTable _artistRowIdTable(_$AppDatabase db) =>
      db.artists.createAlias('songs__artist_row_id__artists__id');

  $$ArtistsTableProcessedTableManager? get artistRowId {
    final $_column = $_itemColumn<int>('artist_row_id');
    if ($_column == null) return null;
    final manager = $$ArtistsTableTableManager(
      $_db,
      $_db.artists,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_artistRowIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$PlaylistSongsTable, List<PlaylistSong>>
  _playlistSongsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.playlistSongs,
    aliasName: 'songs__id__playlist_songs__song_row_id',
  );

  $$PlaylistSongsTableProcessedTableManager get playlistSongsRefs {
    final manager = $$PlaylistSongsTableTableManager(
      $_db,
      $_db.playlistSongs,
    ).filter((f) => f.songRowId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_playlistSongsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SongsTableFilterComposer extends Composer<_$AppDatabase, $SongsTable> {
  $$SongsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mediaStoreId => $composableBuilder(
    column: $table.mediaStoreId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentUri => $composableBuilder(
    column: $table.contentUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleSearch => $composableBuilder(
    column: $table.titleSearch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artistSearch => $composableBuilder(
    column: $table.artistSearch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumName => $composableBuilder(
    column: $table.albumName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get discNumber => $composableBuilder(
    column: $table.discNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateModifiedSec => $composableBuilder(
    column: $table.dateModifiedSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dateAddedSec => $composableBuilder(
    column: $table.dateAddedSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  $$AlbumsTableFilterComposer get albumRowId {
    final $$AlbumsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.albumRowId,
      referencedTable: $db.albums,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AlbumsTableFilterComposer(
            $db: $db,
            $table: $db.albums,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ArtistsTableFilterComposer get artistRowId {
    final $$ArtistsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.artistRowId,
      referencedTable: $db.artists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArtistsTableFilterComposer(
            $db: $db,
            $table: $db.artists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> playlistSongsRefs(
    Expression<bool> Function($$PlaylistSongsTableFilterComposer f) f,
  ) {
    final $$PlaylistSongsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.playlistSongs,
      getReferencedColumn: (t) => t.songRowId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistSongsTableFilterComposer(
            $db: $db,
            $table: $db.playlistSongs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SongsTableOrderingComposer
    extends Composer<_$AppDatabase, $SongsTable> {
  $$SongsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mediaStoreId => $composableBuilder(
    column: $table.mediaStoreId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentUri => $composableBuilder(
    column: $table.contentUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleSearch => $composableBuilder(
    column: $table.titleSearch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artistSearch => $composableBuilder(
    column: $table.artistSearch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumName => $composableBuilder(
    column: $table.albumName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genre => $composableBuilder(
    column: $table.genre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get discNumber => $composableBuilder(
    column: $table.discNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateModifiedSec => $composableBuilder(
    column: $table.dateModifiedSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dateAddedSec => $composableBuilder(
    column: $table.dateAddedSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  $$AlbumsTableOrderingComposer get albumRowId {
    final $$AlbumsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.albumRowId,
      referencedTable: $db.albums,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AlbumsTableOrderingComposer(
            $db: $db,
            $table: $db.albums,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ArtistsTableOrderingComposer get artistRowId {
    final $$ArtistsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.artistRowId,
      referencedTable: $db.artists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArtistsTableOrderingComposer(
            $db: $db,
            $table: $db.artists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SongsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SongsTable> {
  $$SongsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get mediaStoreId => $composableBuilder(
    column: $table.mediaStoreId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentUri => $composableBuilder(
    column: $table.contentUri,
    builder: (column) => column,
  );

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get titleSearch => $composableBuilder(
    column: $table.titleSearch,
    builder: (column) => column,
  );

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get artistSearch => $composableBuilder(
    column: $table.artistSearch,
    builder: (column) => column,
  );

  GeneratedColumn<String> get albumName =>
      $composableBuilder(column: $table.albumName, builder: (column) => column);

  GeneratedColumn<String> get genre =>
      $composableBuilder(column: $table.genre, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get discNumber => $composableBuilder(
    column: $table.discNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dateModifiedSec => $composableBuilder(
    column: $table.dateModifiedSec,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dateAddedSec => $composableBuilder(
    column: $table.dateAddedSec,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  $$AlbumsTableAnnotationComposer get albumRowId {
    final $$AlbumsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.albumRowId,
      referencedTable: $db.albums,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AlbumsTableAnnotationComposer(
            $db: $db,
            $table: $db.albums,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ArtistsTableAnnotationComposer get artistRowId {
    final $$ArtistsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.artistRowId,
      referencedTable: $db.artists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArtistsTableAnnotationComposer(
            $db: $db,
            $table: $db.artists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> playlistSongsRefs<T extends Object>(
    Expression<T> Function($$PlaylistSongsTableAnnotationComposer a) f,
  ) {
    final $$PlaylistSongsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.playlistSongs,
      getReferencedColumn: (t) => t.songRowId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistSongsTableAnnotationComposer(
            $db: $db,
            $table: $db.playlistSongs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SongsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SongsTable,
          Song,
          $$SongsTableFilterComposer,
          $$SongsTableOrderingComposer,
          $$SongsTableAnnotationComposer,
          $$SongsTableCreateCompanionBuilder,
          $$SongsTableUpdateCompanionBuilder,
          (Song, $$SongsTableReferences),
          Song,
          PrefetchHooks Function({
            bool albumRowId,
            bool artistRowId,
            bool playlistSongsRefs,
          })
        > {
  $$SongsTableTableManager(_$AppDatabase db, $SongsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SongsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SongsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SongsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> mediaStoreId = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> contentHash = const Value.absent(),
                Value<String> contentUri = const Value.absent(),
                Value<String?> path = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> titleSearch = const Value.absent(),
                Value<String?> artist = const Value.absent(),
                Value<String?> artistSearch = const Value.absent(),
                Value<String?> albumName = const Value.absent(),
                Value<int?> albumRowId = const Value.absent(),
                Value<int?> artistRowId = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<int?> trackNumber = const Value.absent(),
                Value<int?> discNumber = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<int> dateModifiedSec = const Value.absent(),
                Value<int?> dateAddedSec = const Value.absent(),
                Value<int?> sizeBytes = const Value.absent(),
                Value<String?> format = const Value.absent(),
              }) => SongsCompanion(
                id: id,
                mediaStoreId: mediaStoreId,
                source: source,
                contentHash: contentHash,
                contentUri: contentUri,
                path: path,
                title: title,
                titleSearch: titleSearch,
                artist: artist,
                artistSearch: artistSearch,
                albumName: albumName,
                albumRowId: albumRowId,
                artistRowId: artistRowId,
                genre: genre,
                year: year,
                trackNumber: trackNumber,
                discNumber: discNumber,
                durationMs: durationMs,
                dateModifiedSec: dateModifiedSec,
                dateAddedSec: dateAddedSec,
                sizeBytes: sizeBytes,
                format: format,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> mediaStoreId = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> contentHash = const Value.absent(),
                required String contentUri,
                Value<String?> path = const Value.absent(),
                required String title,
                required String titleSearch,
                Value<String?> artist = const Value.absent(),
                Value<String?> artistSearch = const Value.absent(),
                Value<String?> albumName = const Value.absent(),
                Value<int?> albumRowId = const Value.absent(),
                Value<int?> artistRowId = const Value.absent(),
                Value<String?> genre = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<int?> trackNumber = const Value.absent(),
                Value<int?> discNumber = const Value.absent(),
                required int durationMs,
                required int dateModifiedSec,
                Value<int?> dateAddedSec = const Value.absent(),
                Value<int?> sizeBytes = const Value.absent(),
                Value<String?> format = const Value.absent(),
              }) => SongsCompanion.insert(
                id: id,
                mediaStoreId: mediaStoreId,
                source: source,
                contentHash: contentHash,
                contentUri: contentUri,
                path: path,
                title: title,
                titleSearch: titleSearch,
                artist: artist,
                artistSearch: artistSearch,
                albumName: albumName,
                albumRowId: albumRowId,
                artistRowId: artistRowId,
                genre: genre,
                year: year,
                trackNumber: trackNumber,
                discNumber: discNumber,
                durationMs: durationMs,
                dateModifiedSec: dateModifiedSec,
                dateAddedSec: dateAddedSec,
                sizeBytes: sizeBytes,
                format: format,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$SongsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                albumRowId = false,
                artistRowId = false,
                playlistSongsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (playlistSongsRefs) db.playlistSongs,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (albumRowId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.albumRowId,
                            referencedTable: $$SongsTableReferences
                                ._albumRowIdTable(db),
                            referencedColumn: $$SongsTableReferences
                                ._albumRowIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (artistRowId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.artistRowId,
                            referencedTable: $$SongsTableReferences
                                ._artistRowIdTable(db),
                            referencedColumn: $$SongsTableReferences
                                ._artistRowIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (playlistSongsRefs)
                        await $_getPrefetchedData<
                          Song,
                          $SongsTable,
                          PlaylistSong
                        >(
                          currentTable: table,
                          referencedTable: $$SongsTableReferences
                              ._playlistSongsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SongsTableReferences(
                                db,
                                table,
                                p0,
                              ).playlistSongsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.songRowId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SongsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SongsTable,
      Song,
      $$SongsTableFilterComposer,
      $$SongsTableOrderingComposer,
      $$SongsTableAnnotationComposer,
      $$SongsTableCreateCompanionBuilder,
      $$SongsTableUpdateCompanionBuilder,
      (Song, $$SongsTableReferences),
      Song,
      PrefetchHooks Function({
        bool albumRowId,
        bool artistRowId,
        bool playlistSongsRefs,
      })
    >;
typedef $$SongStatsTableCreateCompanionBuilder = SongStatsCompanion Function({
  Value<int> songId,
  Value<bool> isFavorite,
  Value<int> playCount,
  Value<int?> lastPlayedAt,
  Value<String?> mood,
});
typedef $$SongStatsTableUpdateCompanionBuilder = SongStatsCompanion Function({
  Value<int> songId,
  Value<bool> isFavorite,
  Value<int> playCount,
  Value<int?> lastPlayedAt,
  Value<String?> mood,
});

class $$SongStatsTableFilterComposer
    extends Composer<_$AppDatabase, $SongStatsTable> {
  $$SongStatsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SongStatsTableOrderingComposer
    extends Composer<_$AppDatabase, $SongStatsTable> {
  $$SongStatsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SongStatsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SongStatsTable> {
  $$SongStatsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<int> get playCount =>
      $composableBuilder(column: $table.playCount, builder: (column) => column);

  GeneratedColumn<int> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mood =>
      $composableBuilder(column: $table.mood, builder: (column) => column);
}

class $$SongStatsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SongStatsTable,
          SongStat,
          $$SongStatsTableFilterComposer,
          $$SongStatsTableOrderingComposer,
          $$SongStatsTableAnnotationComposer,
          $$SongStatsTableCreateCompanionBuilder,
          $$SongStatsTableUpdateCompanionBuilder,
          (SongStat, BaseReferences<_$AppDatabase, $SongStatsTable, SongStat>),
          SongStat,
          PrefetchHooks Function()
        > {
  $$SongStatsTableTableManager(_$AppDatabase db, $SongStatsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SongStatsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SongStatsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SongStatsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> songId = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<int?> lastPlayedAt = const Value.absent(),
                Value<String?> mood = const Value.absent(),
              }) => SongStatsCompanion(
                songId: songId,
                isFavorite: isFavorite,
                playCount: playCount,
                lastPlayedAt: lastPlayedAt,
                mood: mood,
              ),
          createCompanionCallback:
              ({
                Value<int> songId = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<int?> lastPlayedAt = const Value.absent(),
                Value<String?> mood = const Value.absent(),
              }) => SongStatsCompanion.insert(
                songId: songId,
                isFavorite: isFavorite,
                playCount: playCount,
                lastPlayedAt: lastPlayedAt,
                mood: mood,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SongStatsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SongStatsTable,
      SongStat,
      $$SongStatsTableFilterComposer,
      $$SongStatsTableOrderingComposer,
      $$SongStatsTableAnnotationComposer,
      $$SongStatsTableCreateCompanionBuilder,
      $$SongStatsTableUpdateCompanionBuilder,
      (SongStat, BaseReferences<_$AppDatabase, $SongStatsTable, SongStat>),
      SongStat,
      PrefetchHooks Function()
    >;
typedef $$PlaylistsTableCreateCompanionBuilder = PlaylistsCompanion Function({
  Value<int> id,
  required String name,
  Value<bool> pinned,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});
typedef $$PlaylistsTableUpdateCompanionBuilder = PlaylistsCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<bool> pinned,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

final class $$PlaylistsTableReferences
    extends BaseReferences<_$AppDatabase, $PlaylistsTable, Playlist> {
  $$PlaylistsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$PlaylistSongsTable, List<PlaylistSong>>
  _playlistSongsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.playlistSongs,
    aliasName: 'playlists__id__playlist_songs__playlist_id',
  );

  $$PlaylistSongsTableProcessedTableManager get playlistSongsRefs {
    final manager = $$PlaylistSongsTableTableManager(
      $_db,
      $_db.playlistSongs,
    ).filter((f) => f.playlistId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_playlistSongsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PlaylistsTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> playlistSongsRefs(
    Expression<bool> Function($$PlaylistSongsTableFilterComposer f) f,
  ) {
    final $$PlaylistSongsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.playlistSongs,
      getReferencedColumn: (t) => t.playlistId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistSongsTableFilterComposer(
            $db: $db,
            $table: $db.playlistSongs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PlaylistsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaylistsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> playlistSongsRefs<T extends Object>(
    Expression<T> Function($$PlaylistSongsTableAnnotationComposer a) f,
  ) {
    final $$PlaylistSongsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.playlistSongs,
      getReferencedColumn: (t) => t.playlistId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistSongsTableAnnotationComposer(
            $db: $db,
            $table: $db.playlistSongs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PlaylistsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistsTable,
          Playlist,
          $$PlaylistsTableFilterComposer,
          $$PlaylistsTableOrderingComposer,
          $$PlaylistsTableAnnotationComposer,
          $$PlaylistsTableCreateCompanionBuilder,
          $$PlaylistsTableUpdateCompanionBuilder,
          (Playlist, $$PlaylistsTableReferences),
          Playlist,
          PrefetchHooks Function({bool playlistSongsRefs})
        > {
  $$PlaylistsTableTableManager(_$AppDatabase db, $PlaylistsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => PlaylistsCompanion(
                id: id,
                name: name,
                pinned: pinned,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<bool> pinned = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => PlaylistsCompanion.insert(
                id: id,
                name: name,
                pinned: pinned,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PlaylistsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({playlistSongsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (playlistSongsRefs) db.playlistSongs,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (playlistSongsRefs)
                    await $_getPrefetchedData<
                      Playlist,
                      $PlaylistsTable,
                      PlaylistSong
                    >(
                      currentTable: table,
                      referencedTable: $$PlaylistsTableReferences
                          ._playlistSongsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$PlaylistsTableReferences(
                            db,
                            table,
                            p0,
                          ).playlistSongsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.playlistId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$PlaylistsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistsTable,
      Playlist,
      $$PlaylistsTableFilterComposer,
      $$PlaylistsTableOrderingComposer,
      $$PlaylistsTableAnnotationComposer,
      $$PlaylistsTableCreateCompanionBuilder,
      $$PlaylistsTableUpdateCompanionBuilder,
      (Playlist, $$PlaylistsTableReferences),
      Playlist,
      PrefetchHooks Function({bool playlistSongsRefs})
    >;
typedef $$PlaylistSongsTableCreateCompanionBuilder =
    PlaylistSongsCompanion Function({
      Value<int> id,
      required int playlistId,
      required int songRowId,
      required int position,
    });
typedef $$PlaylistSongsTableUpdateCompanionBuilder =
    PlaylistSongsCompanion Function({
      Value<int> id,
      Value<int> playlistId,
      Value<int> songRowId,
      Value<int> position,
    });

final class $$PlaylistSongsTableReferences
    extends BaseReferences<_$AppDatabase, $PlaylistSongsTable, PlaylistSong> {
  $$PlaylistSongsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PlaylistsTable _playlistIdTable(_$AppDatabase db) =>
      db.playlists.createAlias('playlist_songs__playlist_id__playlists__id');

  $$PlaylistsTableProcessedTableManager get playlistId {
    final $_column = $_itemColumn<int>('playlist_id')!;

    final manager = $$PlaylistsTableTableManager(
      $_db,
      $_db.playlists,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_playlistIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SongsTable _songRowIdTable(_$AppDatabase db) =>
      db.songs.createAlias('playlist_songs__song_row_id__songs__id');

  $$SongsTableProcessedTableManager get songRowId {
    final $_column = $_itemColumn<int>('song_row_id')!;

    final manager = $$SongsTableTableManager(
      $_db,
      $_db.songs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_songRowIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PlaylistSongsTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistSongsTable> {
  $$PlaylistSongsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  $$PlaylistsTableFilterComposer get playlistId {
    final $$PlaylistsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.playlistId,
      referencedTable: $db.playlists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistsTableFilterComposer(
            $db: $db,
            $table: $db.playlists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SongsTableFilterComposer get songRowId {
    final $$SongsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.songRowId,
      referencedTable: $db.songs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongsTableFilterComposer(
            $db: $db,
            $table: $db.songs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlaylistSongsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistSongsTable> {
  $$PlaylistSongsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  $$PlaylistsTableOrderingComposer get playlistId {
    final $$PlaylistsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.playlistId,
      referencedTable: $db.playlists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistsTableOrderingComposer(
            $db: $db,
            $table: $db.playlists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SongsTableOrderingComposer get songRowId {
    final $$SongsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.songRowId,
      referencedTable: $db.songs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongsTableOrderingComposer(
            $db: $db,
            $table: $db.songs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlaylistSongsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistSongsTable> {
  $$PlaylistSongsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  $$PlaylistsTableAnnotationComposer get playlistId {
    final $$PlaylistsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.playlistId,
      referencedTable: $db.playlists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistsTableAnnotationComposer(
            $db: $db,
            $table: $db.playlists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SongsTableAnnotationComposer get songRowId {
    final $$SongsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.songRowId,
      referencedTable: $db.songs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongsTableAnnotationComposer(
            $db: $db,
            $table: $db.songs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlaylistSongsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistSongsTable,
          PlaylistSong,
          $$PlaylistSongsTableFilterComposer,
          $$PlaylistSongsTableOrderingComposer,
          $$PlaylistSongsTableAnnotationComposer,
          $$PlaylistSongsTableCreateCompanionBuilder,
          $$PlaylistSongsTableUpdateCompanionBuilder,
          (PlaylistSong, $$PlaylistSongsTableReferences),
          PlaylistSong,
          PrefetchHooks Function({bool playlistId, bool songRowId})
        > {
  $$PlaylistSongsTableTableManager(_$AppDatabase db, $PlaylistSongsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistSongsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistSongsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistSongsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> playlistId = const Value.absent(),
                Value<int> songRowId = const Value.absent(),
                Value<int> position = const Value.absent(),
              }) => PlaylistSongsCompanion(
                id: id,
                playlistId: playlistId,
                songRowId: songRowId,
                position: position,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int playlistId,
                required int songRowId,
                required int position,
              }) => PlaylistSongsCompanion.insert(
                id: id,
                playlistId: playlistId,
                songRowId: songRowId,
                position: position,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PlaylistSongsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({playlistId = false, songRowId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (playlistId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.playlistId,
                        referencedTable: $$PlaylistSongsTableReferences
                            ._playlistIdTable(db),
                        referencedColumn: $$PlaylistSongsTableReferences
                            ._playlistIdTable(db)
                            .id,
                      ) as T;
                    }
                    if (songRowId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.songRowId,
                        referencedTable: $$PlaylistSongsTableReferences
                            ._songRowIdTable(db),
                        referencedColumn: $$PlaylistSongsTableReferences
                            ._songRowIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PlaylistSongsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistSongsTable,
      PlaylistSong,
      $$PlaylistSongsTableFilterComposer,
      $$PlaylistSongsTableOrderingComposer,
      $$PlaylistSongsTableAnnotationComposer,
      $$PlaylistSongsTableCreateCompanionBuilder,
      $$PlaylistSongsTableUpdateCompanionBuilder,
      (PlaylistSong, $$PlaylistSongsTableReferences),
      PlaylistSong,
      PrefetchHooks Function({bool playlistId, bool songRowId})
    >;
typedef $$KvEntriesTableCreateCompanionBuilder = KvEntriesCompanion Function({
  required String key,
  Value<String?> valueText,
  Value<int> rowid,
});
typedef $$KvEntriesTableUpdateCompanionBuilder = KvEntriesCompanion Function({
  Value<String> key,
  Value<String?> valueText,
  Value<int> rowid,
});

class $$KvEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $KvEntriesTable> {
  $$KvEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueText => $composableBuilder(
    column: $table.valueText,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KvEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $KvEntriesTable> {
  $$KvEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueText => $composableBuilder(
    column: $table.valueText,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KvEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $KvEntriesTable> {
  $$KvEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get valueText =>
      $composableBuilder(column: $table.valueText, builder: (column) => column);
}

class $$KvEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KvEntriesTable,
          KvEntry,
          $$KvEntriesTableFilterComposer,
          $$KvEntriesTableOrderingComposer,
          $$KvEntriesTableAnnotationComposer,
          $$KvEntriesTableCreateCompanionBuilder,
          $$KvEntriesTableUpdateCompanionBuilder,
          (KvEntry, BaseReferences<_$AppDatabase, $KvEntriesTable, KvEntry>),
          KvEntry,
          PrefetchHooks Function()
        > {
  $$KvEntriesTableTableManager(_$AppDatabase db, $KvEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KvEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KvEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KvEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String?> valueText = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KvEntriesCompanion(
                key: key,
                valueText: valueText,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                Value<String?> valueText = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KvEntriesCompanion.insert(
                key: key,
                valueText: valueText,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KvEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KvEntriesTable,
      KvEntry,
      $$KvEntriesTableFilterComposer,
      $$KvEntriesTableOrderingComposer,
      $$KvEntriesTableAnnotationComposer,
      $$KvEntriesTableCreateCompanionBuilder,
      $$KvEntriesTableUpdateCompanionBuilder,
      (KvEntry, BaseReferences<_$AppDatabase, $KvEntriesTable, KvEntry>),
      KvEntry,
      PrefetchHooks Function()
    >;
typedef $$ScanStatesTableCreateCompanionBuilder = ScanStatesCompanion Function({
  required String source,
  Value<DateTime?> lastCompletedAt,
  Value<int?> totalSongs,
  Value<int> schemaVersion,
  Value<int> rowid,
});
typedef $$ScanStatesTableUpdateCompanionBuilder = ScanStatesCompanion Function({
  Value<String> source,
  Value<DateTime?> lastCompletedAt,
  Value<int?> totalSongs,
  Value<int> schemaVersion,
  Value<int> rowid,
});

class $$ScanStatesTableFilterComposer
    extends Composer<_$AppDatabase, $ScanStatesTable> {
  $$ScanStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastCompletedAt => $composableBuilder(
    column: $table.lastCompletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalSongs => $composableBuilder(
    column: $table.totalSongs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ScanStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $ScanStatesTable> {
  $$ScanStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastCompletedAt => $composableBuilder(
    column: $table.lastCompletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalSongs => $composableBuilder(
    column: $table.totalSongs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ScanStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScanStatesTable> {
  $$ScanStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<DateTime> get lastCompletedAt => $composableBuilder(
    column: $table.lastCompletedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalSongs => $composableBuilder(
    column: $table.totalSongs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => column,
  );
}

class $$ScanStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ScanStatesTable,
          ScanStateEntry,
          $$ScanStatesTableFilterComposer,
          $$ScanStatesTableOrderingComposer,
          $$ScanStatesTableAnnotationComposer,
          $$ScanStatesTableCreateCompanionBuilder,
          $$ScanStatesTableUpdateCompanionBuilder,
          (
            ScanStateEntry,
            BaseReferences<_$AppDatabase, $ScanStatesTable, ScanStateEntry>,
          ),
          ScanStateEntry,
          PrefetchHooks Function()
        > {
  $$ScanStatesTableTableManager(_$AppDatabase db, $ScanStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScanStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ScanStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScanStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> source = const Value.absent(),
                Value<DateTime?> lastCompletedAt = const Value.absent(),
                Value<int?> totalSongs = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScanStatesCompanion(
                source: source,
                lastCompletedAt: lastCompletedAt,
                totalSongs: totalSongs,
                schemaVersion: schemaVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String source,
                Value<DateTime?> lastCompletedAt = const Value.absent(),
                Value<int?> totalSongs = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScanStatesCompanion.insert(
                source: source,
                lastCompletedAt: lastCompletedAt,
                totalSongs: totalSongs,
                schemaVersion: schemaVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ScanStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ScanStatesTable,
      ScanStateEntry,
      $$ScanStatesTableFilterComposer,
      $$ScanStatesTableOrderingComposer,
      $$ScanStatesTableAnnotationComposer,
      $$ScanStatesTableCreateCompanionBuilder,
      $$ScanStatesTableUpdateCompanionBuilder,
      (
        ScanStateEntry,
        BaseReferences<_$AppDatabase, $ScanStatesTable, ScanStateEntry>,
      ),
      ScanStateEntry,
      PrefetchHooks Function()
    >;
typedef $$LyricsCacheTableCreateCompanionBuilder =
    LyricsCacheCompanion Function({
      required String contentHash,
      required String identityKey,
      required String lyricsJson,
      required String source,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$LyricsCacheTableUpdateCompanionBuilder =
    LyricsCacheCompanion Function({
      Value<String> contentHash,
      Value<String> identityKey,
      Value<String> lyricsJson,
      Value<String> source,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$LyricsCacheTableFilterComposer
    extends Composer<_$AppDatabase, $LyricsCacheTable> {
  $$LyricsCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lyricsJson => $composableBuilder(
    column: $table.lyricsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LyricsCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $LyricsCacheTable> {
  $$LyricsCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lyricsJson => $composableBuilder(
    column: $table.lyricsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LyricsCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $LyricsCacheTable> {
  $$LyricsCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lyricsJson => $composableBuilder(
    column: $table.lyricsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$LyricsCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LyricsCacheTable,
          LyricsCacheEntry,
          $$LyricsCacheTableFilterComposer,
          $$LyricsCacheTableOrderingComposer,
          $$LyricsCacheTableAnnotationComposer,
          $$LyricsCacheTableCreateCompanionBuilder,
          $$LyricsCacheTableUpdateCompanionBuilder,
          (
            LyricsCacheEntry,
            BaseReferences<_$AppDatabase, $LyricsCacheTable, LyricsCacheEntry>,
          ),
          LyricsCacheEntry,
          PrefetchHooks Function()
        > {
  $$LyricsCacheTableTableManager(_$AppDatabase db, $LyricsCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LyricsCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LyricsCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LyricsCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> contentHash = const Value.absent(),
                Value<String> identityKey = const Value.absent(),
                Value<String> lyricsJson = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LyricsCacheCompanion(
                contentHash: contentHash,
                identityKey: identityKey,
                lyricsJson: lyricsJson,
                source: source,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String contentHash,
                required String identityKey,
                required String lyricsJson,
                required String source,
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => LyricsCacheCompanion.insert(
                contentHash: contentHash,
                identityKey: identityKey,
                lyricsJson: lyricsJson,
                source: source,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LyricsCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LyricsCacheTable,
      LyricsCacheEntry,
      $$LyricsCacheTableFilterComposer,
      $$LyricsCacheTableOrderingComposer,
      $$LyricsCacheTableAnnotationComposer,
      $$LyricsCacheTableCreateCompanionBuilder,
      $$LyricsCacheTableUpdateCompanionBuilder,
      (
        LyricsCacheEntry,
        BaseReferences<_$AppDatabase, $LyricsCacheTable, LyricsCacheEntry>,
      ),
      LyricsCacheEntry,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AlbumsTableTableManager get albums =>
      $$AlbumsTableTableManager(_db, _db.albums);
  $$ArtistsTableTableManager get artists =>
      $$ArtistsTableTableManager(_db, _db.artists);
  $$SongsTableTableManager get songs =>
      $$SongsTableTableManager(_db, _db.songs);
  $$SongStatsTableTableManager get songStats =>
      $$SongStatsTableTableManager(_db, _db.songStats);
  $$PlaylistsTableTableManager get playlists =>
      $$PlaylistsTableTableManager(_db, _db.playlists);
  $$PlaylistSongsTableTableManager get playlistSongs =>
      $$PlaylistSongsTableTableManager(_db, _db.playlistSongs);
  $$KvEntriesTableTableManager get kvEntries =>
      $$KvEntriesTableTableManager(_db, _db.kvEntries);
  $$ScanStatesTableTableManager get scanStates =>
      $$ScanStatesTableTableManager(_db, _db.scanStates);
  $$LyricsCacheTableTableManager get lyricsCache =>
      $$LyricsCacheTableTableManager(_db, _db.lyricsCache);
}

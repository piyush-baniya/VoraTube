import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';

import '../../../core/db/app_database.dart';
import '../../../core/models/lyrics.dart';
import '../../../core/player/player_controller.dart';
import 'lrclib_client.dart';

class LyricsService {
  LyricsService({required AppDatabase db, required LrclibClient lrclib})
    : _db = db,
      _lrclib = lrclib;

  final AppDatabase _db;
  final LrclibClient _lrclib;

  /// Computes a content-addressable hash for lyrics caching.
  ///
  /// Uses pipe delimiters to prevent hash collisions between
  /// different combinations of artist/title/album fields.
  String _contentHash(String artist, String title, String? album) {
    final normalized = StringBuffer()
      ..write(artist.toLowerCase().trim())
      ..write('|')
      ..write(title.toLowerCase().trim())
      ..write('|')
      ..write((album ?? '').toLowerCase().trim());
    return md5.convert(utf8.encode(normalized.toString())).toString();
  }

  Future<LyricsResult> getLyrics(SongRef song) async {
    final embedded = await _tryEmbedded(song);
    if (embedded != null && !embedded.isEmpty) {
      return LyricsResult.loaded(embedded, LyricsSource.embedded);
    }

    final cached = await _tryCache(song);
    if (cached != null) {
      return LyricsResult.loaded(cached, LyricsSource.cache);
    }

    final online = await _tryOnline(song);
    return switch (online.kind) {
      _OnlineKind.found => LyricsResult.loaded(
        online.data!,
        LyricsSource.lrclib,
      ),
      _OnlineKind.offline => const LyricsResult.offline(),
      _OnlineKind.error => const LyricsResult.error(),
      _OnlineKind.notFound => const LyricsResult.notFound(),
    };
  }

  Future<LyricsData?> _tryEmbedded(SongRef song) async {
    final path = song.uri;
    if (path.isEmpty) return null;

    try {
      final file = File(path);
      if (!await file.exists()) return null;

      final metadata = readMetadata(file, getImage: false);
      final lyricsText = metadata.lyrics;
      if (lyricsText == null || lyricsText.trim().isEmpty) return null;

      final trimmed = lyricsText.trim();

      // Try parsing as LRC first (supports synced lyrics in embedded metadata)
      final lrcLines = parseLrc(trimmed);
      if (lrcLines.isNotEmpty && lrcLines.any((l) => l.isTimestamped)) {
        return LyricsData(
          lines: lrcLines,
          plainText: plainTextFromLines(lrcLines),
          syncedLrc: trimmed,
        );
      }

      // Fall back to plain text
      return _buildFromPlainText(trimmed);
    } catch (_) {
      return null;
    }
  }

  Future<LyricsData?> _tryCache(SongRef song) async {
    try {
      final hash = _contentHash(song.artist ?? '', song.title, song.album);

      final entry =
          await (_db.select(_db.lyricsCache)
                ..where((t) => t.contentHash.equals(hash))
                ..limit(1))
              .getSingleOrNull();

      if (entry == null) return null;

      final json = jsonDecode(entry.lyricsJson) as Map<String, dynamic>;
      return LyricsData(
        lines:
            (json['lines'] as List?)
                ?.map(
                  (l) => LyricsLine(
                    text: l['text'] as String,
                    startTimeMs: (l['startTimeMs'] as num?)?.toInt(),
                  ),
                )
                .toList() ??
            [],
        plainText: (json['plainText'] as String?) ?? '',
        syncedLrc: json['syncedLrc'] as String?,
        isInstrumental: json['isInstrumental'] == true,
        source: LyricsSource.cache,
      );
    } catch (_) {
      return null;
    }
  }

  Future<_OnlineOutcome> _tryOnline(SongRef song) async {
    try {
      final durationSec = song.durationMs > 0
          ? (song.durationMs ~/ 1000)
          : null;

      // Try exact match first
      var result = await _lrclib.fetchByTrack(
        trackName: song.title,
        artistName: song.artist ?? '',
        albumName: song.album,
        durationSec: durationSec,
      );

      // Fall back to fuzzy search if exact match fails
      if (result == null || !result.hasLyrics) {
        result = await _lrclib.searchByTrack(
          trackName: song.title,
          artistName: song.artist ?? '',
          albumName: song.album,
        );
      }

      if (result == null || !result.hasLyrics) {
        return const _OnlineOutcome.notFound();
      }

      // Verify the result plausibly matches the requested song
      if (song.artist != null &&
          song.artist!.isNotEmpty &&
          !lyricsMatchesSong(
            resultTrackName: result.trackName,
            resultArtistName: result.artistName,
            requestedTrackName: song.title,
            requestedArtistName: song.artist!,
          )) {
        return const _OnlineOutcome.notFound();
      }

      final data = _buildFromLrclib(result);

      if (!data.isEmpty) {
        await _cache(song, data);
      }

      return _OnlineOutcome.found(data);
    } on LyricsNetworkException {
      // Could not reach the lyrics service — the user is likely offline.
      return const _OnlineOutcome.offline();
    } on RateLimitException {
      return const _OnlineOutcome.error();
    } catch (_) {
      return const _OnlineOutcome.error();
    }
  }

  LyricsData _buildFromLrclib(LrclibResult result) {
    if (result.isInstrumental) {
      return const LyricsData(lines: [], plainText: '', isInstrumental: true);
    }

    final syncedLrc = result.syncedLyrics;
    if (syncedLrc != null && syncedLrc.trim().isNotEmpty) {
      final lines = parseLrc(syncedLrc);
      if (lines.isNotEmpty) {
        final plainText = result.plainLyrics?.trim().isNotEmpty == true
            ? result.plainLyrics!.trim()
            : plainTextFromLines(lines);
        return LyricsData(
          lines: lines,
          plainText: plainText,
          syncedLrc: syncedLrc,
        );
      }
    }

    final plainLyrics = result.plainLyrics;
    if (plainLyrics != null && plainLyrics.trim().isNotEmpty) {
      final lines = plainLyrics
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) => LyricsLine(text: l.trim()))
          .toList();
      return LyricsData(lines: lines, plainText: plainLyrics.trim());
    }

    return LyricsData.empty;
  }

  LyricsData _buildFromPlainText(String text) {
    final lines = text
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map((l) => LyricsLine(text: l.trim()))
        .toList();
    return LyricsData(lines: lines, plainText: text);
  }

  Future<void> _cache(SongRef song, LyricsData data) async {
    try {
      final hash = _contentHash(song.artist ?? '', song.title, song.album);

      final lyricsJson = jsonEncode({
        'lines': data.lines
            .map(
              (l) => {
                'text': l.text,
                if (l.startTimeMs != null) 'startTimeMs': l.startTimeMs,
              },
            )
            .toList(),
        'plainText': data.plainText,
        'syncedLrc': data.syncedLrc,
        'isInstrumental': data.isInstrumental,
      });

      await _db
          .into(_db.lyricsCache)
          .insertOnConflictUpdate(
            LyricsCacheCompanion.insert(
              contentHash: hash,
              identityKey: song.identityKey,
              lyricsJson: lyricsJson,
              source: 'lrclib',
              fetchedAt: DateTime.now(),
            ),
          );
    } catch (_) {
      // Cache writes are best-effort
    }
  }
}

/// Distinguishes the possible outcomes of a remote lyrics lookup so the
/// caller can surface the right message (offline vs error vs no lyrics).
enum _OnlineKind { found, offline, error, notFound }

class _OnlineOutcome {
  const _OnlineOutcome._(this.data, this.kind);

  const _OnlineOutcome.found(LyricsData data) : this._(data, _OnlineKind.found);
  const _OnlineOutcome.offline() : this._(null, _OnlineKind.offline);
  const _OnlineOutcome.error() : this._(null, _OnlineKind.error);
  const _OnlineOutcome.notFound() : this._(null, _OnlineKind.notFound);

  final LyricsData? data;
  final _OnlineKind kind;

  bool get isFound => kind == _OnlineKind.found && data != null;
}

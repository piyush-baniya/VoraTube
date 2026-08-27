import 'dart:convert';

import 'package:http/http.dart' as http;

/// Local + online genre enrichment for songs that have no genre tagged yet.
///
/// Resolution order is deliberately local-first and never blocks playback:
///   1. existing genre from local metadata (always wins — we never override the
///      user's file metadata with a guessed value);
///   2. locally cached enrichment stored in the KV table (TTL-gated);
///   3. an online iTunes lookup, attempted best-effort with a short timeout.
///
/// The service is plain Dart (no Flutter types) so it can be unit-tested with a
/// fake [http.Client] and in-memory cache callbacks.
class GenreEnrichmentService {
  GenreEnrichmentService({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Cached enrichments are reused for this long before a refresh is considered.
  static const cacheTtl = Duration(days: 30);

  /// Failed lookups are remembered (as an empty sentinel) for this long so an
  /// offline song isn't re-hammered on every launch, but the enrichment still
  /// recovers once this window has passed.
  static const suppressTtl = Duration(days: 7);

  /// Network lookup is capped so an unreachable host can't stall the UI.
  static const lookupTimeout = Duration(seconds: 3);

  /// KV key under which an enrichment for [rowId] is stored.
  static String cacheKeyForRow(int rowId) => 'genreCache:$rowId';

  /// Extracts the best genre guess from an iTunes Search API response body.
  ///
  /// iTunes returns a `primaryGenreName` string per result. Some responses also
  /// include a more specific `genres` array — we prefer the first non-empty
  /// array entry, since it is usually more useful than the coarse primary genre.
  static String? parseITunesResponse(String body) {
    try {
      final Object? parsed = jsonDecode(body);
      if (parsed is! Map<String, dynamic>) return null;
      final int count = parsed['resultCount'] as int? ?? 0;
      if (count == 0) return null;
      final results = parsed['results'] as List<dynamic>? ?? [];
      if (results.isEmpty) return null;
      final first = results.first;
      if (first is! Map<String, dynamic>) return null;
      // Prefer the specific `genres` array when available.
      final genres = first['genres'] as List<dynamic>?;
      if (genres != null) {
        for (final g in genres) {
          final label = g is Map<String, dynamic>
              ? g['name']?.toString()
              : g?.toString();
          if (label != null && label.isNotEmpty) return label;
        }
      }
      final primary = first['primaryGenreName']?.toString();
      if (primary != null && primary.isNotEmpty) return primary;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Returns `true` when [cached] encodes an entry younger than the relevant
  /// TTL. Suppression sentinels (a `s` flag) use a shorter window so a song
  /// whose lookup failed offline is retried sooner than a real cached genre.
  static bool isCacheFresh(String? cached, DateTime now) {
    if (cached == null || cached.isEmpty) return false;
    try {
      final Map<String, dynamic> json =
          jsonDecode(cached) as Map<String, dynamic>;
      final t = json['t'] as int?;
      if (t == null) return false;
      final fetched = DateTime.fromMillisecondsSinceEpoch(t);
      final isSuppressed = json['s'] == true;
      final ttl = isSuppressed ? suppressTtl : cacheTtl;
      return now.difference(fetched) < ttl;
    } catch (_) {
      return false;
    }
  }

  /// Decodes the genre field previously written by [enrichIfNeeded].
  static String? decodeCachedGenre(String? cached) {
    if (cached == null || cached.isEmpty) return null;
    try {
      final Map<String, dynamic> json =
          jsonDecode(cached) as Map<String, dynamic>;
      final g = json['g'] as String?;
      return g == null || g.isEmpty ? null : g;
    } catch (_) {
      return null;
    }
  }

  /// Writes a stale sentinel into the cache so the next [enrichIfNeeded] forces
  /// an online lookup instead of trusting a previous (possibly wrong) entry.
  static Future<void> invalidateCache({
    required int rowId,
    required Future<void> Function(String key, String value) writeCache,
  }) => writeCache(cacheKeyForRow(rowId), jsonEncode({'g': '', 't': 0}));

  /// Records that no genre could be found for [rowId] so the background
  /// enrichment pass does not retry it aggressively. The entry decodes to
  /// `null` (see [decodeCachedGenre]) and is treated as fresh for
  /// [suppressTtl], after which the lookup may be attempted again.
  static Future<void> suppressLookup({
    required int rowId,
    required Future<void> Function(String key, String value) writeCache,
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();
    return writeCache(
      cacheKeyForRow(rowId),
      jsonEncode({'g': '', 't': now.millisecondsSinceEpoch, 's': true}),
    );
  }

  /// Resolves the effective genre for a song.
  ///
  /// [existingGenre] is the value read straight off the local file/metadata.
  /// When it is present it is returned immediately — enrichment never fights
  /// trusted local data.
  ///
  /// [readCache]/[writeCache] are thin wrappers over the repository's KV access
  /// so the service stays DB-agnostic and unit-testable.
  Future<String?> enrichIfNeeded({
    required int rowId,
    required String title,
    required String? artist,
    required String? existingGenre,
    required Future<String?> Function(String key) readCache,
    required Future<void> Function(String key, String value) writeCache,
  }) async {
    final trimmed = existingGenre?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }

    final cacheKey = cacheKeyForRow(rowId);
    final cached = await readCache(cacheKey);
    final now = DateTime.now();
    if (isCacheFresh(cached, now)) {
      return decodeCachedGenre(cached);
    }

    // Best-effort online lookup. Any failure (offline, DNS, timeout, non-200)
    // simply yields `null` — the song simply stays without a genre rather than
    // breaking. Playback and browsing are unaffected.
    String? genre;
    try {
      genre = await _lookupITunes(
        title: title,
        artist: artist,
      ).timeout(lookupTimeout);
    } catch (_) {
      genre = null;
    }

    final nonEmpty = genre?.trim();
    if (nonEmpty != null && nonEmpty.isNotEmpty) {
      await writeCache(
        cacheKey,
        jsonEncode({'g': nonEmpty, 't': now.millisecondsSinceEpoch}),
      );
    }
    return nonEmpty;
  }

  Future<String?> _lookupITunes({
    required String title,
    required String? artist,
  }) async {
    final String query = (artist == null || artist.isEmpty)
        ? title
        : '$artist $title';
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': query,
      'entity': 'song',
      'limit': '5',
      'country': 'US',
    });
    final response = await _http.get(uri);
    if (response.statusCode != 200) return null;
    return parseITunesResponse(response.body);
  }
}

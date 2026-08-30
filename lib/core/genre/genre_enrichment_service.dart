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
  /// Returns `true` only when [cached] is a fresh MULTI-GENRE (`gs`) entry
  /// written by [suggestGenres]. Legacy single-genre (`g`) entries — including
  /// fresh ones written by the background enrichment pass — return `false` so
  /// the suggestion flow always runs its own lookup and never collapses to a
  /// single option.
  static bool isFreshGenreListCache(String? cached, DateTime now) {
    if (cached == null || cached.isEmpty) return false;
    try {
      final Map<String, dynamic> json =
          jsonDecode(cached) as Map<String, dynamic>;
      if (json['gs'] is! List<dynamic>) return false;
      return isCacheFresh(cached, now);
    } catch (_) {
      return false;
    }
  }

  /// Returns `true` when [cached] encodes an entry younger than the relevant
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

  /// Extracts ALL genre options from an iTunes Search API response body.
  ///
  /// Where [parseITunesResponse] picks only the single best guess (used for
  /// automatic enrichment), this variant exposes every genre the lookup
  /// generated for the song: every entry of the specific `genres` array, in
  /// API order, followed by `primaryGenreName` when it is not already present.
  /// The list is trimmed, de-duplicated (case-insensitively) and contains no
  /// empty entries — but is NOT capped: whatever the genre engine produced is
  /// returned in full.
  static List<String> parseITunesGenres(String body) {
    final options = <String>[];

    try {
      final Object? parsed = jsonDecode(body);
      if (parsed is! Map<String, dynamic>) return options;
      final int count = parsed['resultCount'] as int? ?? 0;
      if (count == 0) return options;
      final results = parsed['results'] as List<dynamic>? ?? [];
      if (results.isEmpty) return options;
      // Every search result carries its own genre data. Collect the genres of
      // ALL results — usually several distinct genres across the matches —
      // not just the first one, which is what made Suggest Genre show a
      // single option.
      for (final result in results) {
        if (result is! Map<String, dynamic>) continue;
        final genres = result['genres'] as List<dynamic>?;
        if (genres != null) {
          for (final g in genres) {
            final label = g is Map<String, dynamic>
                ? g['name']?.toString()
                : g?.toString();
            addOptionLabel(options, label);
          }
        }
        addOptionLabel(options, result['primaryGenreName']?.toString());
      }
      return options;
    } catch (_) {
      return options;
    }
  }

  static void addOptionLabel(List<String> options, String? label) {
    final trimmed = label?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    final exists = options.any((o) => o.toLowerCase() == trimmed.toLowerCase());
    if (!exists) options.add(trimmed);
  }

  /// Returns ALL genre options VoraTube's genre engine generated for a song.
  ///
  /// Mirrors [enrichIfNeeded]'s local-first resolution:
  ///   1. a locally cached suggestion list (TTL-gated, shared with the
  ///      single-genre cache so old entries still work);
  ///   2. an online iTunes lookup, best-effort with a short timeout, returning
  ///      every generated genre rather than just the best one.
  /// Returns an empty list when the genre engine produces nothing — callers
  /// must show an empty state instead of inventing genres.
  Future<List<String>> suggestGenres({
    required int rowId,
    required String title,
    required String? artist,
    String? existingGenre,
    required Future<String?> Function(String key) readCache,
    required Future<void> Function(String key, String value) writeCache,
  }) async {
    // The song's current genre is always a valid choice: seed the option list
    // with it so the user sees what the song is currently tagged as, even
    // when the lookup produces nothing new.
    final options = <String>[];
    addOptionLabel(options, existingGenre);

    final cacheKey = cacheKeyForRow(rowId);
    final cached = await readCache(cacheKey);
    final now = DateTime.now();
    // Only a FRESH MULTI-GENRE (`gs`) entry may short-circuit the lookup.
    // The background enrichment pass writes fresh SINGLE-genre legacy (`g`)
    // entries; trusting those here would collapse the suggestion list back
    // to one option, so they are ignored and a fresh lookup runs instead.
    if (isFreshGenreListCache(cached, now)) {
      for (final g in decodeCachedGenres(cached)) {
        addOptionLabel(options, g);
      }
      return List.unmodifiable(options);
    }

    List<String> genres;
    try {
      genres = await _lookupITunesGenres(
        title: title,
        artist: artist,
      ).timeout(lookupTimeout);
    } catch (_) {
      genres = const [];
    }

    for (final g in genres) {
      addOptionLabel(options, g);
    }

    if (genres.isNotEmpty) {
      await writeCache(
        cacheKey,
        jsonEncode({'gs': genres, 't': now.millisecondsSinceEpoch}),
      );
    }
    return List.unmodifiable(options);
  }

  /// Decodes a cached suggestion entry. Supports the list form (`gs`) written
  /// by [suggestGenres] and falls back to the legacy single-genre form (`g`)
  /// written by [enrichIfNeeded].
  static List<String> decodeCachedGenres(String? cached) {
    if (cached == null || cached.isEmpty) return const [];
    try {
      final Map<String, dynamic> json =
          jsonDecode(cached) as Map<String, dynamic>;
      final gs = json['gs'];
      if (gs is List<dynamic>) {
        return gs
            .map((g) => g?.toString().trim() ?? '')
            .where((g) => g.isNotEmpty)
            .toList(growable: false);
      }
      final single = decodeCachedGenre(cached);
      return single == null ? const [] : [single];
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> _lookupITunesGenres({
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
    if (response.statusCode != 200) return const [];
    return parseITunesGenres(response.body);
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

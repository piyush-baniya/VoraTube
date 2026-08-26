import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const _baseUrl = 'https://lrclib.net/api';
const _userAgent = 'VoraTube/1.0.0 (https://github.com/vora-tube/vora-tube)';
const _requestDelay = Duration(milliseconds: 300);
const _requestTimeout = Duration(seconds: 10);

class LrclibClient {
  LrclibClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  DateTime? _lastRequestTime;

  Future<void> _throttle() async {
    if (_lastRequestTime != null) {
      final elapsed = DateTime.now().difference(_lastRequestTime!);
      if (elapsed < _requestDelay) {
        await Future<void>.delayed(_requestDelay - elapsed);
      }
    }
    _lastRequestTime = DateTime.now();
  }

  Future<http.Response> _get(Uri uri) async {
    await _throttle();
    final response = await _client
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(_requestTimeout);
    return response;
  }

  /// Fetches lyrics using the exact-match `/get` endpoint.
  ///
  /// Returns null on 404, throws [RateLimitException] on 429.
  Future<LrclibResult?> fetchByTrack({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSec,
  }) async {
    final params = <String, String>{
      'track_name': trackName,
      'artist_name': artistName,
    };
    if (albumName != null && albumName.isNotEmpty) {
      params['album_name'] = albumName;
    }
    if (durationSec != null && durationSec > 0 && durationSec <= 3600) {
      params['duration'] = durationSec.toString();
    }

    final uri = Uri.parse('$_baseUrl/get').replace(queryParameters: params);

    try {
      final response = await _get(uri);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return LrclibResult.fromJson(json);
      }
      if (response.statusCode == 404) {
        return null;
      }
      if (response.statusCode == 429) {
        final retryAfter = response.headers['retry-after'];
        final seconds = retryAfter != null ? int.tryParse(retryAfter) : null;
        throw RateLimitException(retrySeconds: seconds);
      }
      return null;
    } on RateLimitException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  /// Searches for lyrics using the fuzzy `/search` endpoint.
  ///
  /// Falls back to this when the exact `/get` endpoint returns 404.
  /// Returns the best matching result, or null if nothing matches.
  Future<LrclibResult?> searchByTrack({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSec,
  }) async {
    final params = <String, String>{
      'track_name': trackName,
      'artist_name': artistName,
    };
    if (albumName != null && albumName.isNotEmpty) {
      params['album_name'] = albumName;
    }

    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: params);

    try {
      final response = await _get(uri);

      if (response.statusCode == 200) {
        final jsonList = jsonDecode(response.body) as List<dynamic>;
        if (jsonList.isEmpty) return null;

        // Pick the first result (LRCLIB sorts by relevance)
        return LrclibResult.fromJson(jsonList.first as Map<String, dynamic>);
      }
      if (response.statusCode == 429) {
        final retryAfter = response.headers['retry-after'];
        final seconds = retryAfter != null ? int.tryParse(retryAfter) : null;
        throw RateLimitException(retrySeconds: seconds);
      }
      return null;
    } on RateLimitException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    _client.close();
  }
}

class RateLimitException implements Exception {
  const RateLimitException({this.retrySeconds});

  final int? retrySeconds;

  @override
  String toString() => 'RateLimitException(retryAfter: $retrySeconds)';
}

class LrclibResult {
  const LrclibResult({
    required this.trackName,
    required this.artistName,
    this.albumName,
    this.duration,
    this.plainLyrics,
    this.syncedLyrics,
    this.isInstrumental = false,
  });

  factory LrclibResult.fromJson(Map<String, dynamic> json) {
    return LrclibResult(
      trackName: (json['trackName'] as String?) ?? '',
      artistName: (json['artistName'] as String?) ?? '',
      albumName: json['albumName'] as String?,
      duration: (json['duration'] as num?)?.toInt(),
      plainLyrics: json['plainLyrics'] as String?,
      syncedLyrics: json['syncedLyrics'] as String?,
      isInstrumental: json['instrumental'] == true,
    );
  }

  final String trackName;
  final String artistName;
  final String? albumName;
  final int? duration;
  final String? plainLyrics;
  final String? syncedLyrics;
  final bool isInstrumental;

  bool get hasLyrics =>
      (plainLyrics != null && plainLyrics!.isNotEmpty) ||
      (syncedLyrics != null && syncedLyrics!.isNotEmpty) ||
      isInstrumental;
}

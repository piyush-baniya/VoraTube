import 'dart:convert';

enum LyricsSource { embedded, userLrc, cache, lrclib, none }

enum LyricsStatus { loading, loaded, notFound, error, offline }

class LyricsLine {
  const LyricsLine({required this.text, this.startTimeMs});

  final String text;
  final int? startTimeMs;

  bool get isTimestamped => startTimeMs != null;
}

class LyricsData {
  const LyricsData({
    required this.lines,
    required this.plainText,
    this.syncedLrc,
    this.isInstrumental = false,
    this.source = LyricsSource.none,
  });

  final List<LyricsLine> lines;
  final String plainText;
  final String? syncedLrc;
  final bool isInstrumental;
  final LyricsSource source;

  bool get hasSyncedLines => lines.any((l) => l.isTimestamped);

  bool get isEmpty => plainText.trim().isEmpty && !isInstrumental;

  static const empty = LyricsData(lines: [], plainText: '');
}

class LyricsResult {
  const LyricsResult({
    required this.status,
    this.data,
    this.source = LyricsSource.none,
  });

  final LyricsStatus status;
  final LyricsData? data;
  final LyricsSource source;

  const LyricsResult.loading()
    : status = LyricsStatus.loading,
      data = null,
      source = LyricsSource.none;

  const LyricsResult.offline()
    : status = LyricsStatus.offline,
      data = null,
      source = LyricsSource.none;

  const LyricsResult.notFound()
    : status = LyricsStatus.notFound,
      data = null,
      source = LyricsSource.none;

  const LyricsResult.error()
    : status = LyricsStatus.error,
      data = null,
      source = LyricsSource.none;

  factory LyricsResult.loaded(LyricsData data, LyricsSource source) =>
      LyricsResult(status: LyricsStatus.loaded, data: data, source: source);
}

/// Standard LRC metadata header keys that should not be displayed as lyrics.
const _lrcMetadataKeys = {'ti', 'ar', 'al', 'by', 'offset', 're', 've'};

/// Parses LRC format lyrics into [LyricsLine]s.
///
/// LRC format: `[mm:ss.xx] Text` or `[mm:ss.xxx] Text`
/// Also supports `[mm:ss:xx]` and `[mm:ss]` variants.
/// Filters out standard LRC metadata headers ([ti:...], [ar:...], etc.).
List<LyricsLine> parseLrc(String lrc) {
  final lines = <LyricsLine>[];
  final lrcLines = const LineSplitter().convert(lrc);

  for (final raw in lrcLines) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;

    final parsed = _parseLrcLine(trimmed);
    if (parsed != null) {
      lines.add(parsed);
    }
  }

  lines.sort((a, b) {
    if (a.startTimeMs == null) return 1;
    if (b.startTimeMs == null) return -1;
    return a.startTimeMs!.compareTo(b.startTimeMs!);
  });

  return lines;
}

/// Parses a single LRC line like `[01:23.45] Hello world`.
///
/// Returns a timestamped [LyricsLine] if the timestamp is present,
/// or an untimed line if no timestamp is found.
/// Returns null for LRC metadata headers ([ti:...], [ar:...], etc.)
/// and for empty/whitespace-only lines.
LyricsLine? _parseLrcLine(String line) {
  final timestampRegex = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{2,3}))?\]');
  final timestamps = <int>[];

  var textStartIndex = 0;
  final matches = timestampRegex.allMatches(line);

  for (final match in matches) {
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final msStr = match.group(3);

    var milliseconds = 0;
    if (msStr != null) {
      if (msStr.length == 2) {
        milliseconds = int.parse(msStr) * 10;
      } else {
        milliseconds = int.parse(msStr);
      }
    }

    final totalMs = (minutes * 60 + seconds) * 1000 + milliseconds;
    timestamps.add(totalMs);
    textStartIndex = match.end;
  }

  final text = line.substring(textStartIndex).trim();

  if (text.isEmpty && timestamps.isEmpty) return null;
  if (text.isEmpty) return null;

  // Filter LRC metadata headers: lines like [ti:Song Title], [ar:Artist], etc.
  // These match the timestamp regex (e.g., [ti:...] → group(1)="t" fails int.parse)
  // but the regex won't match non-numeric first group, so they become untimed
  // lines with text like "[ti:Song Title]". We detect and skip these.
  if (timestamps.isEmpty && text.startsWith('[') && text.contains(']')) {
    final innerContent = text.substring(1, text.indexOf(']'));
    final colonIndex = innerContent.indexOf(':');
    if (colonIndex > 0) {
      final key = innerContent.substring(0, colonIndex).trim().toLowerCase();
      if (_lrcMetadataKeys.contains(key)) {
        return null;
      }
    }
  }

  final primaryTimestamp = timestamps.isNotEmpty ? timestamps.first : null;

  return LyricsLine(text: text, startTimeMs: primaryTimestamp);
}

/// Builds plain text from a list of [LyricsLine]s.
String plainTextFromLines(List<LyricsLine> lines) =>
    lines.map((l) => l.text).join('\n');

/// Normalizes text for lyrics matching.
///
/// Strips parenthetical content, feat./ft. variations, common suffixes,
/// normalizes Unicode, removes extra punctuation and whitespace.
/// Does NOT strip content that could change the meaning of the song title
/// (e.g., language-specific characters are preserved).
String normalizeForMatching(String text) {
  var result = text.toLowerCase().trim();

  // Normalize Unicode: decompose then strip combining marks for consistency
  // This helps with accented characters but preserves base characters
  result = result.replaceAll(RegExp(r'[\u0300-\u036f]'), '');

  // Remove parenthetical content: (feat. Artist), (From "Movie"), (Remix), etc.
  // But preserve content in square brackets [Original] as some titles use them.
  result = result.replaceAll(RegExp(r'\([^)]*\)'), '');

  // Remove bracket content except [Original] type markers
  result = result.replaceAll(RegExp(r'\[[^\]]*\]'), '');

  // Normalize feat./ft./featuring variations (consume trailing dot/space)
  result = result.replaceAll(RegExp(r'\b(feat\.?|ft\.?|featuring)\.?\s*'), ' ');

  // Remove common title suffixes that don't affect identity
  result = result.replaceAll(
    RegExp(
      r'\b(remix|remastered|remaster|deluxe|single|album|version|edit|'
      r'live|acoustic|unplugged|instrumental|karaoke|cover|'
      r'original|radio|extended|clean|explicit|edited)\b',
    ),
    '',
  );

  // Remove dashes / Devanagari danda and common separators
  // "Song Title - From Movie", "Song Title | Artist", "गीत ।"
  result = result.replaceAll(RegExp(r'\s*[-–—|।\u0964\u0965]\s*'), ' ');

  // Remove common prefixes: "Original Motion Picture Soundtrack", etc.
  result = result.replaceAll(
    RegExp(
      r'\b(original motion picture soundtrack|soundtrack|'
      r'from the|from|original title|title)\b',
    ),
    '',
  );

  // Collapse multiple spaces and trim
  result = result.replaceAll(RegExp(r'\s+'), ' ').trim();

  return result;
}

/// Checks if LRCLIB result metadata plausibly matches the requested song.
///
/// Returns true if the track name and artist name from the result
/// are close enough to the requested song to be considered a match.
/// Uses normalized comparison plus token-overlap to handle Hindi/English
/// variations without being too permissive.
bool lyricsMatchesSong({
  required String resultTrackName,
  required String resultArtistName,
  required String requestedTrackName,
  required String requestedArtistName,
}) {
  final normResultTrack = normalizeForMatching(resultTrackName);
  final normResultArtist = normalizeForMatching(resultArtistName);
  final normReqTrack = normalizeForMatching(requestedTrackName);
  final normReqArtist = normalizeForMatching(requestedArtistName);

  if (normReqTrack.isEmpty || normResultTrack.isEmpty) return false;
  if (normReqArtist.isEmpty || normResultArtist.isEmpty) return false;

  bool tokenOverlap(String a, String b) {
    if (a.contains(b) || b.contains(a)) return true;
    final ta = a.split(' ').where((w) => w.length > 2).toSet();
    final tb = b.split(' ').where((w) => w.length > 2).toSet();
    if (ta.isEmpty || tb.isEmpty) return false;
    final inter = ta.intersection(tb).length;
    final union = ta.union(tb).length;
    final jaccard = union == 0 ? 0.0 : inter / union;
    if (jaccard >= 0.5) return true;
    // Hindi / transliteration fallback: at least half tokens overlap
    final minLen = ta.length < tb.length ? ta.length : tb.length;
    if (minLen > 0 && inter / minLen >= 0.5) return true;
    return false;
  }

  final trackMatch = tokenOverlap(normResultTrack, normReqTrack);
  final artistMatch = tokenOverlap(normResultArtist, normReqArtist);

  return trackMatch && artistMatch;
}

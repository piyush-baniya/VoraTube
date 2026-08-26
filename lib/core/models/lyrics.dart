import 'dart:convert';

enum LyricsSource { embedded, cache, lrclib, none }

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

/// Parses LRC format lyrics into [LyricsLine]s.
///
/// LRC format: `[mm:ss.xx] Text` or `[mm:ss.xxx] Text`
/// Also supports `[mm:ss:xx]` and `[mm:ss]` variants.
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

  final primaryTimestamp = timestamps.isNotEmpty ? timestamps.first : null;

  return LyricsLine(text: text, startTimeMs: primaryTimestamp);
}

/// Builds plain text from a list of [LyricsLine]s.
String plainTextFromLines(List<LyricsLine> lines) =>
    lines.map((l) => l.text).join('\n');

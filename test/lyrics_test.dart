import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/core/models/lyrics.dart';
import 'package:vora_tube/features/lyrics/data/lrclib_client.dart';

void main() {
  group('parseLrc', () {
    test('parses standard LRC timestamps', () {
      final lrc = '[01:23.45] Hello\n[02:34.56] World';
      final lines = parseLrc(lrc);

      expect(lines, hasLength(2));
      expect(lines[0].text, 'Hello');
      expect(lines[0].startTimeMs, 83450);
      expect(lines[1].text, 'World');
      expect(lines[1].startTimeMs, 154560);
    });

    test('parses LRC with three-digit milliseconds', () {
      final lrc = '[00:05.123] Test';
      final lines = parseLrc(lrc);

      expect(lines, hasLength(1));
      expect(lines[0].startTimeMs, 5123);
    });

    test('parses LRC with colon separator for ms', () {
      final lrc = '[01:30:50] Test';
      final lines = parseLrc(lrc);

      expect(lines, hasLength(1));
      // 50 is treated as 2-digit ms → 50 * 10 = 500
      expect(lines[0].startTimeMs, 90500);
    });

    test('parses LRC without milliseconds', () {
      final lrc = '[02:15] Simple';
      final lines = parseLrc(lrc);

      expect(lines, hasLength(1));
      expect(lines[0].text, 'Simple');
      expect(lines[0].startTimeMs, 135000);
    });

    test('skips empty lines', () {
      final lrc = '[00:10.00] First\n\n[00:20.00] Second\n';
      final lines = parseLrc(lrc);

      expect(lines, hasLength(2));
    });

    test('parses metadata lines as untimed lyrics', () {
      final lrc = '[ti:Song Title]\n[ar:Artist]\n[00:10.00] Actual lyric';
      final lines = parseLrc(lrc);

      // Metadata lines without valid timestamps become untimed lyrics.
      // The parser doesn't filter them — that's expected behavior.
      expect(lines, hasLength(3));
      expect(lines.any((l) => l.text == 'Actual lyric'), true);
      expect(lines.any((l) => l.text.contains('Song Title')), true);
    });

    test('sorts lines by timestamp', () {
      final lrc = '[00:30.00] Third\n[00:10.00] First\n[00:20.00] Second';
      final lines = parseLrc(lrc);

      expect(lines[0].text, 'First');
      expect(lines[1].text, 'Second');
      expect(lines[2].text, 'Third');
    });

    test('handles multiple timestamps per line', () {
      final lrc = '[00:10.00][00:30.00] Same line';
      final lines = parseLrc(lrc);

      expect(lines, hasLength(1));
      expect(lines[0].text, 'Same line');
      expect(lines[0].startTimeMs, 10000);
    });

    test('returns empty for empty input', () {
      expect(parseLrc(''), isEmpty);
    });

    test('returns empty for whitespace-only input', () {
      expect(parseLrc('   \n  \n  '), isEmpty);
    });
  });

  group('LyricsData', () {
    test('hasSyncedLines returns true when lines have timestamps', () {
      const data = LyricsData(
        lines: [
          LyricsLine(text: 'Hello', startTimeMs: 0),
          LyricsLine(text: 'World', startTimeMs: 5000),
        ],
        plainText: 'Hello\nWorld',
      );

      expect(data.hasSyncedLines, true);
    });

    test('hasSyncedLines returns false for plain lyrics', () {
      const data = LyricsData(
        lines: [
          LyricsLine(text: 'Hello'),
          LyricsLine(text: 'World'),
        ],
        plainText: 'Hello\nWorld',
      );

      expect(data.hasSyncedLines, false);
    });

    test('isEmpty returns true for empty plain text', () {
      const data = LyricsData(lines: [], plainText: '');
      expect(data.isEmpty, true);
    });

    test('isEmpty returns false for non-empty plain text', () {
      const data = LyricsData(
        lines: [LyricsLine(text: 'Hello')],
        plainText: 'Hello',
      );
      expect(data.isEmpty, false);
    });

    test('isEmpty returns false for instrumental tracks', () {
      const data = LyricsData(lines: [], plainText: '', isInstrumental: true);
      // Instrumental tracks are NOT empty — they have semantic meaning.
      expect(data.isEmpty, false);
    });

    test('empty constant has empty plain text', () {
      expect(LyricsData.empty.plainText, '');
      expect(LyricsData.empty.lines, isEmpty);
    });
  });

  group('LyricsResult', () {
    test('loading factory creates loading status', () {
      const result = LyricsResult.loading();
      expect(result.status, LyricsStatus.loading);
      expect(result.data, isNull);
    });

    test('offline factory creates offline status', () {
      const result = LyricsResult.offline();
      expect(result.status, LyricsStatus.offline);
    });

    test('notFound factory creates notFound status', () {
      const result = LyricsResult.notFound();
      expect(result.status, LyricsStatus.notFound);
    });

    test('loaded factory creates loaded status with data', () {
      const data = LyricsData(lines: [], plainText: 'Test');
      final result = LyricsResult.loaded(data, LyricsSource.lrclib);

      expect(result.status, LyricsStatus.loaded);
      expect(result.data, data);
      expect(result.source, LyricsSource.lrclib);
    });
  });

  group('LyricsLine', () {
    test('isTimestamped returns true when startTimeMs is set', () {
      const line = LyricsLine(text: 'Hello', startTimeMs: 5000);
      expect(line.isTimestamped, true);
    });

    test('isTimestamped returns false when startTimeMs is null', () {
      const line = LyricsLine(text: 'Hello');
      expect(line.isTimestamped, false);
    });
  });

  group('plainTextFromLines', () {
    test('joins lines with newline', () {
      const lines = [LyricsLine(text: 'Hello'), LyricsLine(text: 'World')];
      expect(plainTextFromLines(lines), 'Hello\nWorld');
    });

    test('returns empty string for empty list', () {
      expect(plainTextFromLines(const []), '');
    });
  });

  group('LrclibResult', () {
    test('parses JSON correctly', () {
      final json = {
        'trackName': 'Test Song',
        'artistName': 'Test Artist',
        'albumName': 'Test Album',
        'duration': 180,
        'plainLyrics': 'Hello\nWorld',
        'syncedLyrics': '[00:10.00] Hello\n[00:20.00] World',
        'instrumental': false,
      };

      final result = LrclibResult.fromJson(json);

      expect(result.trackName, 'Test Song');
      expect(result.artistName, 'Test Artist');
      expect(result.albumName, 'Test Album');
      expect(result.duration, 180);
      expect(result.plainLyrics, 'Hello\nWorld');
      expect(result.syncedLyrics, '[00:10.00] Hello\n[00:20.00] World');
      expect(result.isInstrumental, false);
    });

    test('hasLyrics returns true when plainLyrics exists', () {
      const result = LrclibResult(
        trackName: 'Song',
        artistName: 'Artist',
        plainLyrics: 'Hello',
      );
      expect(result.hasLyrics, true);
    });

    test('hasLyrics returns true for instrumental tracks', () {
      const result = LrclibResult(
        trackName: 'Song',
        artistName: 'Artist',
        isInstrumental: true,
      );
      expect(result.hasLyrics, true);
    });

    test('hasLyrics returns false when no lyrics', () {
      const result = LrclibResult(trackName: 'Song', artistName: 'Artist');
      expect(result.hasLyrics, false);
    });

    test('parses missing fields as null', () {
      final json = <String, dynamic>{
        'trackName': 'Song',
        'artistName': 'Artist',
      };

      final result = LrclibResult.fromJson(json);

      expect(result.albumName, isNull);
      expect(result.duration, isNull);
      expect(result.plainLyrics, isNull);
      expect(result.syncedLyrics, isNull);
      expect(result.isInstrumental, false);
    });
  });
}

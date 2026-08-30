import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/core/models/lyrics.dart';
import 'package:vora_tube/core/player/just_audio_controller.dart';
import 'package:vora_tube/features/lyrics/presentation/providers/lyrics_providers.dart';

LyricsLine _line(String text, int? startMs) =>
    LyricsLine(text: text, startTimeMs: startMs);

LyricsData _synced(List<(int, String)> entries) => LyricsData(
  lines: [for (final (ms, text) in entries) _line(text, ms)],
  plainText: '',
);

void main() {
  group('lyricLineIndexAt — basic progression', () {
    final lines = _synced([(10000, 'A'), (20000, 'B'), (30000, 'C')]).lines;

    test('before first line → -1', () {
      expect(lyricLineIndexAt(lines, const Duration(milliseconds: 9999)), -1);
    });

    test('at 00:10 → A', () {
      expect(lyricLineIndexAt(lines, const Duration(seconds: 10)), 0);
    });

    test('at 00:15 → A', () {
      expect(lyricLineIndexAt(lines, const Duration(milliseconds: 15000)), 0);
    });

    test('at 00:19.999 → still A', () {
      expect(lyricLineIndexAt(lines, const Duration(milliseconds: 19999)), 0);
    });

    test('at 00:20 → B', () {
      expect(lyricLineIndexAt(lines, const Duration(seconds: 20)), 1);
    });

    test('at 00:29.999 → still B', () {
      expect(lyricLineIndexAt(lines, const Duration(milliseconds: 29999)), 1);
    });

    test('at 00:30 → C', () {
      expect(lyricLineIndexAt(lines, const Duration(seconds: 30)), 2);
    });

    test('end of song → final line stays selected', () {
      expect(lyricLineIndexAt(lines, const Duration(minutes: 4)), 2);
    });
  });

  group('lyricLineIndexAt — fractional precision', () {
    final lines = _synced([(10250, 'A'), (10750, 'B'), (11125, 'C')]).lines;

    test('selects the close-together fractional lines correctly', () {
      expect(lyricLineIndexAt(lines, const Duration(milliseconds: 10249)), -1);
      expect(lyricLineIndexAt(lines, const Duration(milliseconds: 10250)), 0);
      expect(lyricLineIndexAt(lines, const Duration(milliseconds: 10749)), 0);
      expect(lyricLineIndexAt(lines, const Duration(milliseconds: 10750)), 1);
      expect(lyricLineIndexAt(lines, const Duration(milliseconds: 11125)), 2);
    });
  });

  group('lyricLineIndexAt — seeking', () {
    final lines = _synced([
      (5000, 'A'),
      (15000, 'B'),
      (25000, 'C'),
      (60000, 'D'),
      (90000, 'E'),
    ]).lines;

    test('seek forward jumps straight to the later lyric', () {
      // Was on A (00:05), seek to 01:30 → E immediately.
      expect(lyricLineIndexAt(lines, const Duration(seconds: 90)), 4);
    });

    test('seek backward jumps straight back to the earlier lyric', () {
      // Was on E (01:30), seek to 00:20 → B immediately.
      expect(lyricLineIndexAt(lines, const Duration(seconds: 20)), 1);
    });
  });

  group('lyricLineIndexAt — edge cases', () {
    test('duplicate timestamps resolve deterministically (no crash)', () {
      final lines = _synced([(30000, 'A'), (30000, 'B'), (40000, 'C')]).lines;
      final at30 = lyricLineIndexAt(lines, const Duration(seconds: 30));
      expect(lines[at30].startTimeMs, 30000);
      expect(lyricLineIndexAt(lines, const Duration(seconds: 40)), 2);
    });

    test('empty lyrics → -1', () {
      expect(lyricLineIndexAt(const [], const Duration(seconds: 10)), -1);
    });

    test('untimed-only lyrics → -1 (no sync attempted)', () {
      final lines = [_line('plain', null), _line('lines', null)];
      expect(lyricLineIndexAt(lines, const Duration(seconds: 10)), -1);
    });

    test('unordered timestamps are sorted by the parser', () {
      final lrc = ['[00:30] C', '[00:10] A', '[00:20] B'].join('\n');
      final lines = parseLrc(lrc);
      expect([for (final l in lines) l.startTimeMs], [10000, 20000, 30000]);
      // Selection follows the sorted order.
      expect(lyricLineIndexAt(lines, const Duration(seconds: 15)), 0);
      expect(lyricLineIndexAt(lines, const Duration(seconds: 25)), 1);
    });

    test('track reset: new track lines evaluated from actual position', () {
      // Song A index 3 was active; Song B starts at 00:02 → no line, and
      // B's own lines are used for matching.
      final trackB = _synced([(5000, 'B1'), (12000, 'B2')]).lines;
      expect(lyricLineIndexAt(trackB, const Duration(seconds: 2)), -1);
      expect(lyricLineIndexAt(trackB, const Duration(seconds: 6)), 0);
    });
  });

  group('position stream resolution (the fix boundary)', () {
    // The lyrics highlight follows PlayerController.positions, which is the
    // controller's createPositionStream. Previously it used steps:120 with
    // maxPeriod:1s, so during steady playback the position — and therefore the
    // highlighted line — updated at most once per second, lagging the actual
    // position by up to 1s. The fix pins a uniform ~200ms cadence.
    test('fixed 200ms cadence: minPeriod == maxPeriod', () {
      expect(positionStreamMinPeriod, const Duration(milliseconds: 200));
      expect(positionStreamMaxPeriod, const Duration(milliseconds: 200));
      expect(positionStreamMaxPeriod, positionStreamMinPeriod);
    });

    test('steps is fine enough that min/max clamp dominates', () {
      // duration/steps for any realistic song (>= 800 steps needed before the
      // period could exceed 200ms) keeps the period pinned at minPeriod.
      expect(positionStreamSteps, greaterThanOrEqualTo(800));
    });
  });
}

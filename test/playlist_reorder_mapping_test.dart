import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/features/playlists/presentation/screens/playlist_detail_screen.dart';

void main() {
  group('playlistDropTarget', () {
    test('maps a downward drop between items correctly', () {
      // [A,B,C]: drag A between B and C => target 1 (post-removal space).
      expect(playlistDropTarget(0, 1, 3), 1);
    });

    test('maps a downward drop onto the very end', () {
      // [A,B,C]: drag A to the end => target 2 (post-removal space).
      expect(playlistDropTarget(0, 2, 3), 2);
      // [A,B]: drag A past B => target 1.
      expect(playlistDropTarget(0, 1, 2), 1);
    });

    test('maps a drop onto/past the loading footer to the end slot', () {
      // Footer is outside the reorderable items: drop beyond the last loaded
      // song must become "move to last position" instead of being rejected.
      expect(playlistDropTarget(0, 199, 200), 199);
      expect(playlistDropTarget(0, 500, 200), 199);
    });

    test('maps an upward drop without shifting', () {
      // [A,B,C]: drag C above A => target 0.
      expect(playlistDropTarget(2, 0, 3), 0);
      // [A,B,C]: drag B above A => target 0.
      expect(playlistDropTarget(1, 0, 3), 0);
    });

    test('no-ops when the item is already in place', () {
      // Dragging the last item to the very bottom changes nothing.
      expect(playlistDropTarget(2, 2, 3), -1);
      // Drag dropped back onto its own slot.
      expect(playlistDropTarget(1, 1, 3), -1);
      expect(playlistDropTarget(0, 0, 2), -1);
    });

    test('rejects invalid indexes and tiny lists', () {
      expect(playlistDropTarget(-1, 0, 3), -1);
      expect(playlistDropTarget(3, 0, 3), -1);
      expect(playlistDropTarget(0, 0, 1), -1);
      expect(playlistDropTarget(0, 1, 1), -1);
    });

    test('keeps moves within bounds for a large pinned list', () {
      // A 205-song playlist with the first 200 loaded: moving song 5 to the
      // end of the loaded range stays a valid in-page move.
      expect(playlistDropTarget(5, 200, 200), 199);
    });
  });
}

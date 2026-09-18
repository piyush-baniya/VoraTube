import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/ui_customization/layout_edit_session.dart';
import 'package:vora_tube/core/ui_customization/ui_layout.dart';

LayoutProfile _profile(int step) => LayoutProfile(
  layouts: {
    const LayoutKey('home', LayoutVariant.portrait): ScreenLayout(
      screenId: 'home',
      components: [
        ComponentLayout(id: 'home.playlists', styleId: 'style$step'),
      ],
    ),
  },
);

void main() {
  group('LayoutEditSession', () {
    test('starts clean with no history', () {
      final session = LayoutEditSession(baseline: _profile(0));
      expect(session.isDirty, isFalse);
      expect(session.canUndo, isFalse);
      expect(session.canRedo, isFalse);
      expect(session.undo(), isFalse);
      expect(session.redo(), isFalse);
    });

    test('apply marks dirty and enables undo', () {
      final session = LayoutEditSession(baseline: _profile(0))
        ..apply(_profile(1));
      expect(session.current, _profile(1));
      expect(session.isDirty, isTrue);
      expect(session.canUndo, isTrue);
      expect(session.canRedo, isFalse);
    });

    test('ignores an identical apply', () {
      final session = LayoutEditSession(baseline: _profile(0))
        ..apply(_profile(0));
      expect(session.canUndo, isFalse);
      expect(session.isDirty, isFalse);
    });

    test('undo and redo walk the history', () {
      final session = LayoutEditSession(baseline: _profile(0))
        ..apply(_profile(1))
        ..apply(_profile(2));
      expect(session.undo(), isTrue);
      expect(session.current, _profile(1));
      expect(session.canRedo, isTrue);
      expect(session.redo(), isTrue);
      expect(session.current, _profile(2));
      expect(session.redo(), isFalse);
    });

    test('a new edit clears the redo stack', () {
      final session = LayoutEditSession(baseline: _profile(0))
        ..apply(_profile(1));
      session.undo();
      expect(session.canRedo, isTrue);
      session.apply(_profile(3));
      expect(session.canRedo, isFalse);
      expect(session.current, _profile(3));
    });

    test('markSaved rebases dirty tracking without touching history', () {
      final session = LayoutEditSession(baseline: _profile(0))
        ..apply(_profile(1));
      session.markSaved();
      expect(session.isDirty, isFalse);
      expect(session.canUndo, isTrue);
      session.undo();
      expect(session.isDirty, isTrue);
    });

    test('undo history is bounded to historyLimit', () {
      final session = LayoutEditSession(baseline: _profile(0));
      for (var i = 1; i <= LayoutEditSession.historyLimit + 10; i++) {
        session.apply(_profile(i));
      }
      var undos = 0;
      while (session.undo()) {
        undos++;
      }
      expect(undos, LayoutEditSession.historyLimit);
      expect(session.canUndo, isFalse);
    });
  });
}

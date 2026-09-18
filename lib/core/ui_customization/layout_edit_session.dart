import 'ui_layout.dart';

/// A bounded undo/redo buffer over an in-progress [LayoutProfile].
///
/// The editor mutates a session rather than the saved profile, so Cancel
/// simply drops the session and Save commits [current]. History is capped at
/// [historyLimit] snapshots; the oldest entry is evicted first, which bounds
/// memory for long editing sessions.
class LayoutEditSession {
  LayoutEditSession({required LayoutProfile baseline})
    : _saved = baseline,
      _current = baseline;

  static const int historyLimit = 50;

  final List<LayoutProfile> _undoStack = [];
  final List<LayoutProfile> _redoStack = [];
  LayoutProfile _saved;
  LayoutProfile _current;
  LayoutProfile? _gestureStart;

  LayoutProfile get current => _current;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// True while [current] differs from the last saved (or baseline) profile.
  bool get isDirty => _current != _saved;

  /// Records a new profile as an undoable step. Applying an identical profile
  /// is ignored so no-op rebuilds never pollute the history.
  void apply(LayoutProfile next) {
    if (next == _current) return;
    _undoStack.add(_current);
    if (_undoStack.length > historyLimit) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    _current = next;
  }

  /// Snapshots the current profile as the start of a drag/resize gesture.
  /// Every pointer move updates the profile through [applyLive] (no history);
  /// a single [commitGesture] collapses the whole gesture into ONE undo entry.
  void beginGesture() {
    _gestureStart = _current;
  }

  /// Mutates the profile during a gesture WITHOUT pushing an undo entry, so
  /// the canvas can follow the pointer at frame rate without polluting the
  /// history with one step per frame.
  void applyLive(LayoutProfile next) {
    _current = next;
  }

  /// Ends an in-flight gesture, turning its net change into exactly one undo
  /// entry (or none when nothing actually moved).
  void commitGesture() {
    final start = _gestureStart;
    _gestureStart = null;
    if (start == null || start == _current) return;
    _undoStack.add(start);
    if (_undoStack.length > historyLimit) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// Discards an in-flight gesture, restoring the profile to its start so a
  /// snapped-back drop never half-commits.
  void cancelGesture() {
    final start = _gestureStart;
    _gestureStart = null;
    if (start != null && start != _current) {
      _current = start;
    }
  }

  /// Marks the current profile as the saved reference (called after a
  /// successful commit) without touching the undo/redo history.
  void markSaved() {
    _saved = _current;
  }

  bool undo() {
    if (_undoStack.isEmpty) return false;
    _redoStack.add(_current);
    _current = _undoStack.removeLast();
    return true;
  }

  bool redo() {
    if (_redoStack.isEmpty) return false;
    _undoStack.add(_current);
    if (_undoStack.length > historyLimit) {
      _undoStack.removeAt(0);
    }
    _current = _redoStack.removeLast();
    return true;
  }
}

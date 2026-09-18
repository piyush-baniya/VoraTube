import 'package:flutter/widgets.dart';

import '../../../../core/ui_customization/ui_component_registry.dart';

/// Mutable state shared by every live-editing frame on one screen: which
/// component is currently selected (frames highlight themselves and expose
/// their contextual menu / resize handle) and the screen's registry.
class LayoutEditBridge extends ChangeNotifier {
  LayoutEditBridge({required this.screenId, required this.registry});

  final String screenId;
  final UiComponentRegistry registry;

  String? _selectedId;
  String? get selectedId => _selectedId;

  void select(String? id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  void clearSelection() => select(null);
}

/// Marks a subtree as being inside the live customization editor. When present,
/// a screen renders its real blocks wrapped in editable frames and puts its
/// non-block chrome (navigation, toggles, gestures) into an inert state.
class LayoutEditScope extends InheritedNotifier<LayoutEditBridge> {
  const LayoutEditScope({
    super.key,
    required LayoutEditBridge bridge,
    required super.child,
  }) : super(notifier: bridge);

  static LayoutEditBridge? maybeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LayoutEditScope>();
    return scope?.notifier;
  }

  static LayoutEditBridge of(BuildContext context) {
    final bridge = maybeOf(context);
    assert(bridge != null, 'LayoutEditScope is not present above this widget.');
    return bridge!;
  }

  /// True while the subtree is being live-edited (regardless of selection).
  static bool isEditing(BuildContext context) => maybeOf(context) != null;
}

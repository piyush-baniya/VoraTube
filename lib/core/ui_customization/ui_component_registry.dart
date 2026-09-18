import 'package:flutter/foundation.dart';

import 'ui_layout.dart';

/// Declares a customizable component: its stable id, how it may be changed and
/// the defaults a missing or invalid layout entry falls back to.
///
/// Definitions are pure data. They never build widgets, so the registry can be
/// consumed by the normalizer, the editor and persistence without dragging UI
/// code along.
@immutable
class UiComponentDefinition {
  const UiComponentDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.defaultSize,
    this.allowedSizes = const [
      ComponentSize.small,
      ComponentSize.medium,
      ComponentSize.large,
    ],
    this.allowedStyleIds = const [],
    this.defaultStyleId,
    this.canHide = true,
    this.canReorder = true,
    this.canResize = true,
  });

  final String id;
  final String label;
  final String description;
  final ComponentSize defaultSize;
  final List<ComponentSize> allowedSizes;

  /// Registry-declared style variants. An empty list means the component has
  /// one fixed presentation.
  final List<String> allowedStyleIds;
  final String? defaultStyleId;

  final bool canHide;
  final bool canReorder;
  final bool canResize;

  bool supportsSize(ComponentSize size) => allowedSizes.contains(size);

  bool supportsStyle(String? id) => id == null || allowedStyleIds.contains(id);

  /// The style a component uses when no (valid) style is stored.
  String? get effectiveDefaultStyleId =>
      defaultStyleId ??
      (allowedStyleIds.isEmpty ? null : allowedStyleIds.first);

  /// First-run layout for this component.
  ComponentLayout defaultLayout({bool visible = true}) => ComponentLayout(
    id: id,
    visible: visible,
    size: defaultSize,
    styleId: effectiveDefaultStyleId,
  );
}

/// The set of customizable components for one or more screens, in default
/// order. Order in [definitions] is the canonical fallback order.
@immutable
class UiComponentRegistry {
  const UiComponentRegistry(this.definitions);

  final List<UiComponentDefinition> definitions;

  UiComponentDefinition? definitionFor(String id) {
    for (final d in definitions) {
      if (d.id == id) return d;
    }
    return null;
  }

  bool contains(String id) => definitionFor(id) != null;

  List<String> get ids => [for (final d in definitions) d.id];
}

/// Screen id for the Home dashboard.
const String kHomeScreenId = 'home';

/// Home dashboard components, in the original pre-customization order so the
/// default profile reproduces the existing UI exactly.
const UiComponentRegistry homeComponentRegistry = UiComponentRegistry([
  UiComponentDefinition(
    id: 'home.continueListening',
    label: 'Continue Listening',
    description: 'Resume the track you were last playing',
    defaultSize: ComponentSize.medium,
    allowedStyleIds: ['hero', 'compact'],
    defaultStyleId: 'hero',
  ),
  UiComponentDefinition(
    id: 'home.listeningInsights',
    label: 'Your Listening',
    description: 'Play counts, listening time and your most played track',
    defaultSize: ComponentSize.medium,
    allowedStyleIds: ['full', 'chips'],
    defaultStyleId: 'full',
  ),
  UiComponentDefinition(
    id: 'home.playlists',
    label: 'Playlists',
    description: 'Your playlists with a quick create action',
    defaultSize: ComponentSize.medium,
    allowedStyleIds: ['carousel', 'grid'],
    defaultStyleId: 'carousel',
  ),
  UiComponentDefinition(
    id: 'home.allSongs',
    label: 'All Songs',
    description: 'A preview of the songs in your library',
    defaultSize: ComponentSize.medium,
    // The library preview is the dashboard's anchor: it stays visible, but it
    // can still be moved or resized.
    canHide: false,
  ),
]);

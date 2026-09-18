import 'ui_component_registry.dart';
import 'ui_layout.dart';

/// Coerces a stored screen layout into a valid one for [registry]:
///
/// * drops unknown and duplicate component ids,
/// * appends components added by a newer app version,
/// * clamps size/style to what the definition allows,
/// * forces non-hideable components visible.
///
/// Normalization is idempotent: normalizing an already-normal layout is a
/// no-op.
ScreenLayout normalizeScreenLayout(
  ScreenLayout layout,
  UiComponentRegistry registry,
) {
  final result = <ComponentLayout>[];
  final seen = <String>{};
  for (final component in layout.components) {
    final definition = registry.definitionFor(component.id);
    if (definition == null || !seen.add(component.id)) continue;
    result.add(_clamp(component, definition));
  }
  for (final definition in registry.definitions) {
    if (seen.contains(definition.id)) continue;
    result.add(definition.defaultLayout());
  }
  return ScreenLayout(screenId: layout.screenId, components: result);
}

ComponentLayout _clamp(
  ComponentLayout component,
  UiComponentDefinition definition,
) {
  final size = definition.canResize && definition.supportsSize(component.size)
      ? component.size
      : definition.defaultSize;
  final style = definition.supportsStyle(component.styleId)
      ? component.styleId
      : definition.effectiveDefaultStyleId;
  final visible = definition.canHide ? component.visible : true;
  return ComponentLayout(
    id: component.id,
    visible: visible,
    size: size,
    styleId: style,
  );
}

/// The untouched registry order for a screen.
ScreenLayout defaultScreenLayout(
  String screenId,
  UiComponentRegistry registry,
) {
  return ScreenLayout(
    screenId: screenId,
    components: [for (final d in registry.definitions) d.defaultLayout()],
  );
}

/// A complete first-run profile covering every variant of every screen.
LayoutProfile defaultLayoutProfile(
  UiComponentRegistry registry, {
  LayoutPreset preset = LayoutPreset.standard,
  List<String> screens = const [kHomeScreenId],
  List<LayoutVariant> variants = LayoutVariant.values,
}) {
  final layouts = <LayoutKey, ScreenLayout>{};
  for (final screen in screens) {
    for (final variant in variants) {
      layouts[LayoutKey(screen, variant)] = defaultScreenLayout(
        screen,
        registry,
      );
    }
  }
  return LayoutProfile(preset: preset, layouts: layouts);
}

/// Validates and completes a decoded profile. A profile written by a different
/// schema version is discarded wholesale; a malformed screen is repaired rather
/// than thrown away with the whole profile.
LayoutProfile normalizeLayoutProfile(
  LayoutProfile profile,
  UiComponentRegistry registry,
) {
  if (profile.schemaVersion != kUiLayoutSchemaVersion) {
    return defaultLayoutProfile(registry);
  }
  final layouts = <LayoutKey, ScreenLayout>{};
  for (final entry in profile.layouts.entries) {
    if (entry.key.screenId != kHomeScreenId) continue;
    if (entry.value.screenId != entry.key.screenId) continue;
    layouts[entry.key] = normalizeScreenLayout(entry.value, registry);
  }
  if (layouts.isEmpty) {
    return defaultLayoutProfile(registry, preset: profile.preset);
  }
  // Ensure a missing variant never fails to render: fall back to its default.
  for (final variant in LayoutVariant.values) {
    layouts.putIfAbsent(
      LayoutKey(kHomeScreenId, variant),
      () => defaultScreenLayout(kHomeScreenId, registry),
    );
  }
  return LayoutProfile(
    schemaVersion: kUiLayoutSchemaVersion,
    preset: profile.preset,
    layouts: layouts,
  );
}

/// Builds the screen layout for one curated [preset]. An unknown screen (or a
/// preset with no screen-specific arrangement) falls back to the default
/// registry order.
ScreenLayout applyLayoutPreset(
  LayoutPreset preset,
  String screenId,
  UiComponentRegistry registry,
) {
  final byId = <String, ComponentLayout>{
    for (final d in registry.definitions) d.id: d.defaultLayout(),
  };

  void size(String id, ComponentSize value) =>
      _mutate(byId, id, (c) => c.copyWith(size: value));
  void hide(String id) => _mutate(byId, id, (c) => c.copyWith(visible: false));
  void style(String id, String value) =>
      _mutate(byId, id, (c) => c.copyWith(styleId: value));

  var order = registry.ids;

  switch (preset) {
    case LayoutPreset.standard:
      break;
    case LayoutPreset.minimal:
      hide('home.listeningInsights');
      hide('home.playlists');
      size('home.continueListening', ComponentSize.small);
      break;
    case LayoutPreset.compact:
      for (final id in registry.ids) {
        size(id, ComponentSize.small);
      }
      break;
    case LayoutPreset.immersive:
      size('home.continueListening', ComponentSize.large);
      size('home.listeningInsights', ComponentSize.large);
      size('home.playlists', ComponentSize.large);
      break;
    case LayoutPreset.discovery:
      if (screenId == kHomeScreenId) {
        order = const [
          'home.playlists',
          'home.listeningInsights',
          'home.continueListening',
          'home.allSongs',
        ];
        size('home.playlists', ComponentSize.large);
        style('home.playlists', 'grid');
        style('home.continueListening', 'compact');
        size('home.continueListening', ComponentSize.small);
      }
      break;
  }

  final components = [
    for (final id in order)
      if (byId[id] != null) byId[id]!,
  ];
  return normalizeScreenLayout(
    ScreenLayout(screenId: screenId, components: components),
    registry,
  );
}

void _mutate(
  Map<String, ComponentLayout> byId,
  String id,
  ComponentLayout Function(ComponentLayout) update,
) {
  final current = byId[id];
  if (current != null) byId[id] = update(current);
}

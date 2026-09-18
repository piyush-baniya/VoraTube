import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Bump when the persisted layout shape changes incompatibly. A profile whose
/// stored [LayoutProfile.schemaVersion] does not match is discarded and the
/// default layout is used instead of risking a mis-parse.
const int kUiLayoutSchemaVersion = 1;

/// Wide layouts (tablets / desktop windows) are selected from the shortest
/// side so a landscape phone is not mistaken for a large screen.
const double kLargeScreenMinSide = 900;

/// Which device shape a screen layout targets. Layouts are kept per variant so
/// a portrait phone, a landscape phone and a tablet can each be tuned without
/// fighting over one shared set of rows.
enum LayoutVariant {
  portrait('Portrait'),
  landscape('Landscape'),
  largeScreen('Large screen');

  const LayoutVariant(this.label);

  final String label;
}

/// Chooses the layout variant for a viewport size.
LayoutVariant layoutVariantForSize(Size size) {
  if (size.shortestSide >= kLargeScreenMinSide) {
    return LayoutVariant.largeScreen;
  }
  return size.width > size.height
      ? LayoutVariant.landscape
      : LayoutVariant.portrait;
}

/// Global / Home layout presets. They are deliberate, curated arrangements
/// rather than a free-form editor: a component stays where the registry says,
/// and a preset only chooses order, visibility, size and style.
enum LayoutPreset {
  standard('Default'),
  minimal('Minimal'),
  compact('Compact'),
  immersive('Immersive'),
  discovery('Discovery'),
  studio('Studio');

  const LayoutPreset(this.label);

  final String label;
}

/// Size presets, never raw pixels. Widgets translate a size into concrete
/// dimensions, so a future screen can honor the same vocabulary.
enum ComponentSize {
  small('Small'),
  medium('Medium'),
  large('Large');

  const ComponentSize(this.label);

  final String label;
}

/// Identifies one screen layout in one device variant.
@immutable
class LayoutKey {
  const LayoutKey(this.screenId, this.variant);

  final String screenId;
  final LayoutVariant variant;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutKey &&
          other.screenId == screenId &&
          other.variant == variant;

  @override
  int get hashCode => Object.hash(screenId, variant);

  @override
  String toString() => '$screenId/${variant.name}';
}

/// The persisted arrangement of a single component on a screen.
@immutable
class ComponentLayout {
  const ComponentLayout({
    required this.id,
    this.visible = true,
    this.size = ComponentSize.medium,
    this.styleId,
  });

  /// Stable component id declared by the registry (e.g. `home.playlists`).
  final String id;

  /// Whether the component is rendered at all. Ignored for components the
  /// registry marks as not hideable.
  final bool visible;

  final ComponentSize size;

  /// Registry-declared style variant (e.g. `carousel`), or null for the
  /// registry default.
  final String? styleId;

  ComponentLayout copyWith({
    bool? visible,
    ComponentSize? size,
    String? styleId,
    bool clearStyle = false,
  }) {
    return ComponentLayout(
      id: id,
      visible: visible ?? this.visible,
      size: size ?? this.size,
      styleId: clearStyle ? null : (styleId ?? this.styleId),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'visible': visible,
    'size': size.name,
    if (styleId != null) 'style': styleId,
  };

  static ComponentLayout? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return ComponentLayout(
      id: id,
      visible: json['visible'] is bool ? json['visible'] as bool : true,
      size: ComponentSize.values.firstWhere(
        (s) => s.name == json['size'],
        orElse: () => ComponentSize.medium,
      ),
      styleId: json['style'] is String ? json['style'] as String : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComponentLayout &&
          other.id == id &&
          other.visible == visible &&
          other.size == size &&
          other.styleId == styleId;

  @override
  int get hashCode => Object.hash(id, visible, size, styleId);
}

/// An ordered list of component layouts for one screen.
@immutable
class ScreenLayout {
  const ScreenLayout({required this.screenId, required this.components});

  final String screenId;
  final List<ComponentLayout> components;

  ComponentLayout? component(String id) {
    for (final c in components) {
      if (c.id == id) return c;
    }
    return null;
  }

  ScreenLayout copyWith({List<ComponentLayout>? components}) => ScreenLayout(
    screenId: screenId,
    components: components ?? this.components,
  );

  /// Returns a copy with [component] replacing the existing entry of the same
  /// id, preserving its position.
  ScreenLayout replaceComponent(ComponentLayout component) {
    return ScreenLayout(
      screenId: screenId,
      components: [
        for (final c in components)
          if (c.id == component.id) component else c,
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'screen': screenId,
    'components': [for (final c in components) c.toJson()],
  };

  static ScreenLayout? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final screenId = json['screen'];
    if (screenId is! String || screenId.isEmpty) return null;
    final rawComponents = json['components'];
    if (rawComponents is! List) return null;
    final components = <ComponentLayout>[];
    for (final raw in rawComponents) {
      final component = ComponentLayout.tryFromJson(raw);
      if (component != null) components.add(component);
    }
    return ScreenLayout(screenId: screenId, components: components);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScreenLayout &&
          other.screenId == screenId &&
          listEquals(other.components, components);

  @override
  int get hashCode => Object.hash(screenId, Object.hashAll(components));
}

/// The complete persisted customization state: schema version, the last
/// applied preset and one [ScreenLayout] per (screen, variant) pair.
@immutable
class LayoutProfile {
  const LayoutProfile({
    this.schemaVersion = kUiLayoutSchemaVersion,
    this.preset = LayoutPreset.standard,
    this.layouts = const {},
  });

  final int schemaVersion;
  final LayoutPreset preset;
  final Map<LayoutKey, ScreenLayout> layouts;

  ScreenLayout? screenLayout(String screenId, LayoutVariant variant) =>
      layouts[LayoutKey(screenId, variant)];

  LayoutProfile replaceScreen(
    String screenId,
    LayoutVariant variant,
    ScreenLayout layout,
  ) {
    return LayoutProfile(
      schemaVersion: schemaVersion,
      preset: preset,
      layouts: {...layouts, LayoutKey(screenId, variant): layout},
    );
  }

  LayoutProfile copyWith({
    int? schemaVersion,
    LayoutPreset? preset,
    Map<LayoutKey, ScreenLayout>? layouts,
  }) {
    return LayoutProfile(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      preset: preset ?? this.preset,
      layouts: layouts ?? this.layouts,
    );
  }

  String encode() => jsonEncode({
    'v': schemaVersion,
    'preset': preset.name,
    'layouts': [
      for (final entry in layouts.entries)
        {'variant': entry.key.variant.name, ...entry.value.toJson()},
    ],
  });

  /// Decodes a persisted profile, returning null for malformed data. Never
  /// throws: a corrupt or truncated blob must fall back to the default layout
  /// rather than blank Home.
  static LayoutProfile? tryDecode(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return null;
      final version = decoded['v'];
      if (version is! int) return null;
      final preset = LayoutPreset.values.firstWhere(
        (p) => p.name == decoded['preset'],
        orElse: () => LayoutPreset.standard,
      );
      final rawLayouts = decoded['layouts'];
      if (rawLayouts is! List) return null;
      final layouts = <LayoutKey, ScreenLayout>{};
      for (final raw in rawLayouts) {
        if (raw is! Map) continue;
        final variant = LayoutVariant.values.firstWhere(
          (v) => v.name == raw['variant'],
          orElse: () => LayoutVariant.portrait,
        );
        final layout = ScreenLayout.tryFromJson(raw);
        if (layout == null) continue;
        layouts[LayoutKey(layout.screenId, variant)] = layout;
      }
      if (layouts.isEmpty) return null;
      return LayoutProfile(
        schemaVersion: version,
        preset: preset,
        layouts: layouts,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutProfile &&
          other.schemaVersion == schemaVersion &&
          other.preset == preset &&
          _mapsEqual(other.layouts, layouts);

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    preset,
    Object.hashAllUnordered(
      layouts.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

bool _mapsEqual(
  Map<LayoutKey, ScreenLayout> a,
  Map<LayoutKey, ScreenLayout> b,
) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

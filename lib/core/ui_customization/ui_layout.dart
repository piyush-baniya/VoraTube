import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Bump when the persisted layout shape changes incompatibly. A profile whose
/// stored [LayoutProfile.schemaVersion] is NEWER than this is discarded and
/// the default layout is used instead of risking a mis-parse; older versions
/// are migrated by the normalizer (see [normalizeLayoutProfile]).
const int kUiLayoutSchemaVersion = 2;

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

/// A component's placement on the freeform edit canvas, normalized to the
/// canvas bounds (each value is a fraction of the canvas width/height in the
/// inclusive range 0.0..1.0). Only normalized geometry is persisted — raw
/// pixel coordinates are never stored, so a saved layout re-flows cleanly
/// across orientations and device sizes.
@immutable
class NormalizedRect {
  const NormalizedRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  double get right => x + width;
  double get bottom => y + height;
  double get centerX => x + width / 2;
  double get centerY => y + height / 2;

  /// Fully inside 0..1 with a positive area.
  bool get isValid =>
      width > 0 && height > 0 && x >= 0 && y >= 0 && right <= 1 && bottom <= 1;

  NormalizedRect copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    return NormalizedRect(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  Map<String, Object?> toJson() => {'x': x, 'y': y, 'w': width, 'h': height};

  /// Reads a stored rect, clamping out-of-range values into the canvas and
  /// returning null when the entry is unusable (not a map or no positive
  /// area after clamping).
  static NormalizedRect? tryFromJson(Object? json) {
    if (json is! Map) return null;
    num? numField(Object? value) => value is num ? value : null;
    double clamp01(num value) => value.toDouble().clamp(0.0, 1.0).toDouble();
    final x = numField(json['x']);
    final y = numField(json['y']);
    final w = numField(json['w']);
    final h = numField(json['h']);
    if (x == null || y == null || w == null || h == null) return null;
    final rect = NormalizedRect(
      x: clamp01(x),
      y: clamp01(y),
      width: clamp01(w),
      height: clamp01(h),
    );
    return rect.isValid ? rect : null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalizedRect &&
          other.x == x &&
          other.y == y &&
          other.width == width &&
          other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() =>
      'NormalizedRect(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, '
      '${width.toStringAsFixed(3)}, ${height.toStringAsFixed(3)})';
}

/// The persisted arrangement of a single component on a screen.
@immutable
class ComponentLayout {
  const ComponentLayout({
    required this.id,
    this.visible = true,
    this.size = ComponentSize.medium,
    this.styleId,
    this.rect,
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

  /// Normalized freeform placement on the edit canvas. Null while the profile
  /// still describes a legacy order-only layout; the editor and the save path
  /// materialize it via the geometry defaults ([DefaultGeometry]).
  final NormalizedRect? rect;

  ComponentLayout copyWith({
    bool? visible,
    ComponentSize? size,
    String? styleId,
    NormalizedRect? rect,
    bool clearStyle = false,
    bool clearRect = false,
  }) {
    return ComponentLayout(
      id: id,
      visible: visible ?? this.visible,
      size: size ?? this.size,
      styleId: clearStyle ? null : (styleId ?? this.styleId),
      rect: clearRect ? null : (rect ?? this.rect),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'visible': visible,
    'size': size.name,
    if (styleId != null) 'style': styleId,
    if (rect != null) 'rect': rect!.toJson(),
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
      rect: NormalizedRect.tryFromJson(json['rect']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComponentLayout &&
          other.id == id &&
          other.visible == visible &&
          other.size == size &&
          other.styleId == styleId &&
          other.rect == rect;

  @override
  int get hashCode => Object.hash(id, visible, size, styleId, rect);
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

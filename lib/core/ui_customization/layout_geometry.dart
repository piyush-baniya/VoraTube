import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'ui_component_registry.dart';
import 'ui_layout.dart';

/// Pure geometry rules for the freeform editor. Everything here is normalized
/// (canvas fractions) so it is unit-testable without widgets and never stores
/// raw pixels.

/// Constrains one component's freeform geometry.
@immutable
class ComponentGeometryConstraint {
  const ComponentGeometryConstraint({
    this.minWidth = 0.08,
    this.minHeight = 0.04,
    this.maxWidth = 1,
    this.maxHeight = 1,
    this.square = false,
  });

  final double minWidth;
  final double minHeight;
  final double maxWidth;
  final double maxHeight;

  /// Locks the block to a square footprint (used by artwork so the circular
  /// disc never distorts — portrait or landscape).
  final bool square;

  double get effectiveMinWidth =>
      square ? math.max(minWidth, minHeight) : minWidth;
  double get effectiveMinHeight => square ? effectiveMinWidth : minHeight;
}

/// Geometry constraint per (screen, component). Unknown components get a
/// generic freeform rule so the editor never blocks a resize.
ComponentGeometryConstraint geometryConstraintFor(
  String screenId,
  String componentId,
) {
  switch (screenId) {
    case kPlayerScreenId:
      switch (componentId) {
        case 'player.artwork':
          return const ComponentGeometryConstraint(
            square: true,
            minWidth: 0.18,
            minHeight: 0.18,
            maxWidth: 0.7,
            maxHeight: 0.7,
          );
        case 'player.progress':
          return const ComponentGeometryConstraint(
            minWidth: 0.3,
            minHeight: 0.04,
          );
        case 'player.trackInfo':
          return const ComponentGeometryConstraint(
            minWidth: 0.4,
            minHeight: 0.06,
          );
        default:
          return const ComponentGeometryConstraint(
            minWidth: 0.5,
            minHeight: 0.05,
          );
      }
    case kEqualizerScreenId:
      if (componentId == 'equalizer.curve') {
        return const ComponentGeometryConstraint(
          minWidth: 0.5,
          minHeight: 0.22,
        );
      }
      return const ComponentGeometryConstraint(minWidth: 0.5, minHeight: 0.05);
    case kMiniScreenId:
      return const ComponentGeometryConstraint(minWidth: 0.08, minHeight: 0.05);
    default:
      return const ComponentGeometryConstraint(minWidth: 0.55, minHeight: 0.06);
  }
}

/// The region a block may occupy on the edit canvas. The mini player keeps its
/// blocks inside the bar strip; every other screen edits against the whole
/// canvas (the toolbar and system insets are already outside the canvas).
NormalizedRect safeBoundsFor(String screenId) {
  return screenId == kMiniScreenId
      ? const NormalizedRect(x: 0, y: 0.8, width: 1, height: 0.2)
      : const NormalizedRect(x: 0, y: 0, width: 1, height: 1);
}

/// True when two rectangles overlap by more than [tolerance] on both axes.
bool rectsOverlap(
  NormalizedRect a,
  NormalizedRect b, {
  double tolerance = 0.004,
}) {
  return a.x + tolerance < b.right &&
      b.x + tolerance < a.right &&
      a.y + tolerance < b.bottom &&
      b.y + tolerance < a.bottom;
}

/// Clamps [rect] inside [bounds] while honoring the constraint's min/max and
/// (when locked) its aspect ratio.
NormalizedRect clampRectToBounds(
  NormalizedRect rect,
  NormalizedRect bounds,
  ComponentGeometryConstraint constraint,
) {
  var width = rect.width
      .clamp(
        constraint.effectiveMinWidth,
        math.min(constraint.maxWidth, bounds.width),
      )
      .toDouble();
  var height = rect.height
      .clamp(
        constraint.effectiveMinHeight,
        math.min(constraint.maxHeight, bounds.height),
      )
      .toDouble();
  if (constraint.square) {
    final side = math.min(width, height);
    width = side;
    height = side;
  }
  final x = rect.x.clamp(bounds.x, bounds.right - width).toDouble();
  final y = rect.y.clamp(bounds.y, bounds.bottom - height).toDouble();
  return NormalizedRect(x: x, y: y, width: width, height: height);
}

/// A snap guide offered during a drag/resize: a vertical or horizontal line
/// drawn across the canvas at a normalized position.
@immutable
class SnapGuide {
  const SnapGuide({required this.position, required this.vertical});

  final double position;
  final bool vertical;
}

/// The outcome of a snapped drag/resize move.
class SnapResult {
  const SnapResult({required this.rect, required this.guides});

  final NormalizedRect rect;
  final List<SnapGuide> guides;
}

/// Snap lines considered when moving/resizing [candidate]: the canvas center,
/// the safe-boundary edges, and every neighbor edge + center.
List<SnapGuide> _collectGuides(
  NormalizedRect candidate,
  List<NormalizedRect> neighbors,
  NormalizedRect bounds,
) {
  final guides = <SnapGuide>[
    const SnapGuide(position: 0.5, vertical: true),
    const SnapGuide(position: 0.5, vertical: false),
    SnapGuide(position: bounds.x, vertical: true),
    SnapGuide(position: bounds.right, vertical: true),
    SnapGuide(position: bounds.y, vertical: false),
    SnapGuide(position: bounds.bottom, vertical: false),
    for (final r in neighbors)
      if (r != candidate) ...[
        SnapGuide(position: r.x, vertical: true),
        SnapGuide(position: r.right, vertical: true),
        SnapGuide(position: r.centerX, vertical: true),
        SnapGuide(position: r.y, vertical: false),
        SnapGuide(position: r.bottom, vertical: false),
        SnapGuide(position: r.centerY, vertical: false),
      ],
  ];
  return guides;
}

double? _snapFeature(
  double value,
  List<SnapGuide> guides,
  bool vertical,
  double threshold,
) {
  SnapGuide? best;
  var bestDist = threshold;
  for (final guide in guides) {
    if (guide.vertical != vertical) continue;
    final dist = (value - guide.position).abs();
    if (dist <= bestDist) {
      bestDist = dist;
      best = guide;
    }
  }
  return best?.position;
}

/// Rounds the candidate to the nearest [gridPx]-aligned grid in pixel space
/// (via [canvasSize]) so persisted geometry sits on a tidy 4/8dp grid.
double _gridSnap(double v, double canvasExtent, double gridPx) {
  if (canvasExtent <= 0 || gridPx <= 0) return v;
  return (v * canvasExtent / gridPx).round() * gridPx / canvasExtent;
}

/// Produces a snapped, bounded candidate during a move or resize gesture.
///
/// [moving] lists which edge/center features follow the finger: for a move all
/// four are true; for a bottom-right resize the fixed anchor is reflected by
/// passing [resizeRight] / [resizeBottom]. Snapping mirrors the primary
/// dragging features against candidate guides; the grid always rounds.
SnapResult snapNormalizedRect({
  required NormalizedRect candidate,
  required List<NormalizedRect> neighbors,
  required NormalizedRect bounds,
  required ComponentGeometryConstraint constraint,
  required Size canvasSize,
  required double gridPx,
  double snapPx = 6,
  bool moveX = true,
  bool moveY = true,
  bool resizeRight = false,
  bool resizeBottom = false,
}) {
  var rect = clampRectToBounds(candidate, bounds, constraint);
  final guides = _collectGuides(rect, neighbors, bounds);

  final thresholdX = snapPx / math.max(1.0, canvasSize.width);
  final thresholdY = snapPx / math.max(1.0, canvasSize.height);

  // Snap on the axis the gesture is actually changing.
  if (moveX) {
    final snappedLeft = _snapFeature(rect.x, guides, true, thresholdX);
    if (snappedLeft != null) {
      rect = rect.copyWith(x: snappedLeft);
    } else if (resizeRight) {
      final snappedRight = _snapFeature(rect.right, guides, true, thresholdX);
      if (snappedRight != null) {
        rect = rect.copyWith(
          width: (snappedRight - rect.x)
              .clamp(constraint.effectiveMinWidth, bounds.right - rect.x)
              .toDouble(),
        );
      }
    }
  }
  if (moveY) {
    final snappedTop = _snapFeature(rect.y, guides, false, thresholdY);
    if (snappedTop != null) {
      rect = rect.copyWith(y: snappedTop);
    } else if (resizeBottom) {
      final snappedBottom = _snapFeature(
        rect.bottom,
        guides,
        false,
        thresholdY,
      );
      if (snappedBottom != null) {
        rect = rect.copyWith(
          height: (snappedBottom - rect.y)
              .clamp(constraint.effectiveMinHeight, bounds.bottom - rect.y)
              .toDouble(),
        );
      }
    }
  }

  // Round to the logical grid last so guides stay authoritative.
  var snapped = NormalizedRect(
    x: _gridSnap(rect.x, canvasSize.width, gridPx),
    y: _gridSnap(rect.y, canvasSize.height, gridPx),
    width: _gridSnap(rect.width, canvasSize.width, gridPx),
    height: _gridSnap(rect.height, canvasSize.height, gridPx),
  );
  snapped = clampRectToBounds(snapped, bounds, constraint);

  final activeGuides = <SnapGuide>[];
  for (final guide in guides) {
    final followsX =
        (snapped.x - guide.position).abs() < 0.001 ||
        (resizeRight && (snapped.right - guide.position).abs() < 0.001);
    final followsY =
        (snapped.y - guide.position).abs() < 0.001 ||
        (resizeBottom && (snapped.bottom - guide.position).abs() < 0.001);
    if ((guide.vertical && followsX) || (!guide.vertical && followsY)) {
      activeGuides.add(guide);
    }
  }
  return SnapResult(rect: snapped, guides: activeGuides);
}

/// Default freeform placement per screen/variant/component, tuned so the
/// editor canvas opens looking like the intended premium UI.
///
/// [index] / [count] back the generic stacked fallback so an unknown screen
/// still gets a tidy vertical default.
NormalizedRect defaultGeometryFor(
  String screenId,
  LayoutVariant variant,
  String componentId, {
  int index = 0,
  int count = 1,
}) {
  switch (screenId) {
    case kPlayerScreenId:
      return variant == LayoutVariant.portrait
          ? _playerPortraitDefault(componentId)
          : _playerSideDefault(componentId);
    case kHomeScreenId:
      return _homeDefault(componentId);
    case kMiniScreenId:
      return _miniDefault(componentId);
    case kEqualizerScreenId:
      return variant == LayoutVariant.portrait
          ? _equalizerPortraitDefault(componentId)
          : _equalizerLandscapeDefault(componentId);
    default:
      final height = 1 / count;
      return NormalizedRect(
        x: 0.02,
        y: height * index,
        width: 0.96,
        height: height - 0.01,
      );
  }
}

NormalizedRect _playerPortraitDefault(String id) {
  switch (id) {
    case 'player.artwork':
      return const NormalizedRect(x: 0.19, y: 0.02, width: 0.62, height: 0.62);
    case 'player.trackInfo':
      return const NormalizedRect(x: 0.06, y: 0.67, width: 0.88, height: 0.11);
    case 'player.secondaryControls':
      return const NormalizedRect(x: 0.03, y: 0.81, width: 0.94, height: 0.08);
    case 'player.progress':
      return const NormalizedRect(x: 0.06, y: 0.9, width: 0.88, height: 0.06);
    case 'player.primaryControls':
      return const NormalizedRect(x: 0.02, y: 0.97, width: 0.96, height: 0.03);
    default:
      return const NormalizedRect(x: 0.02, y: 0.02, width: 0.96, height: 0.2);
  }
}

NormalizedRect _playerSideDefault(String id) {
  switch (id) {
    case 'player.artwork':
      return const NormalizedRect(x: 0.03, y: 0.12, width: 0.4, height: 0.4);
    case 'player.trackInfo':
      return const NormalizedRect(x: 0.48, y: 0.04, width: 0.49, height: 0.16);
    case 'player.secondaryControls':
      return const NormalizedRect(x: 0.48, y: 0.68, width: 0.49, height: 0.11);
    case 'player.progress':
      return const NormalizedRect(x: 0.48, y: 0.82, width: 0.49, height: 0.07);
    case 'player.primaryControls':
      return const NormalizedRect(x: 0.46, y: 0.9, width: 0.51, height: 0.1);
    default:
      return const NormalizedRect(x: 0.02, y: 0.02, width: 0.96, height: 0.2);
  }
}

NormalizedRect _homeDefault(String id) {
  switch (id) {
    case 'home.continueListening':
      return const NormalizedRect(x: 0.025, y: 0.02, width: 0.95, height: 0.3);
    case 'home.listeningInsights':
      return const NormalizedRect(x: 0.025, y: 0.36, width: 0.95, height: 0.17);
    case 'home.playlists':
      return const NormalizedRect(x: 0.025, y: 0.57, width: 0.95, height: 0.2);
    case 'home.allSongs':
      return const NormalizedRect(x: 0.025, y: 0.81, width: 0.95, height: 0.17);
    default:
      return const NormalizedRect(x: 0.02, y: 0.02, width: 0.96, height: 0.2);
  }
}

NormalizedRect _miniDefault(String id) {
  switch (id) {
    case 'mini.artwork':
      return const NormalizedRect(
        x: 0.035,
        y: 0.826,
        width: 0.09,
        height: 0.09,
      );
    case 'mini.trackInfo':
      return const NormalizedRect(x: 0.16, y: 0.837, width: 0.36, height: 0.08);
    case 'mini.progress':
      return const NormalizedRect(x: 0.55, y: 0.865, width: 0.17, height: 0.04);
    case 'mini.controls':
      return const NormalizedRect(x: 0.76, y: 0.826, width: 0.2, height: 0.09);
    case 'mini.secondaryControls':
      return const NormalizedRect(
        x: 0.965,
        y: 0.826,
        width: 0.045,
        height: 0.09,
      );
    default:
      return const NormalizedRect(x: 0.02, y: 0.82, width: 0.3, height: 0.09);
  }
}

NormalizedRect _equalizerPortraitDefault(String id) {
  switch (id) {
    case 'equalizer.nowPlaying':
      return const NormalizedRect(x: 0.04, y: 0.04, width: 0.92, height: 0.1);
    case 'equalizer.curve':
      return const NormalizedRect(x: 0.04, y: 0.18, width: 0.92, height: 0.38);
    case 'equalizer.presets':
      return const NormalizedRect(x: 0.04, y: 0.6, width: 0.92, height: 0.11);
    case 'equalizer.quickControls':
      return const NormalizedRect(x: 0.04, y: 0.74, width: 0.92, height: 0.11);
    case 'equalizer.bandControls':
      return const NormalizedRect(x: 0.04, y: 0.74, width: 0.92, height: 0.11);
    case 'equalizer.preamp':
      return const NormalizedRect(x: 0.04, y: 0.88, width: 0.92, height: 0.07);
    case 'equalizer.processing':
      return const NormalizedRect(
        x: 0.04,
        y: 0.965,
        width: 0.92,
        height: 0.035,
      );
    default:
      return const NormalizedRect(x: 0.02, y: 0.02, width: 0.96, height: 0.2);
  }
}

NormalizedRect _equalizerLandscapeDefault(String id) {
  switch (id) {
    case 'equalizer.nowPlaying':
      return const NormalizedRect(x: 0.03, y: 0.04, width: 0.46, height: 0.13);
    case 'equalizer.curve':
      return const NormalizedRect(x: 0.03, y: 0.24, width: 0.46, height: 0.55);
    case 'equalizer.presets':
      return const NormalizedRect(x: 0.54, y: 0.08, width: 0.43, height: 0.14);
    case 'equalizer.quickControls':
      return const NormalizedRect(x: 0.54, y: 0.27, width: 0.43, height: 0.18);
    case 'equalizer.bandControls':
      return const NormalizedRect(x: 0.54, y: 0.27, width: 0.43, height: 0.18);
    case 'equalizer.preamp':
      return const NormalizedRect(x: 0.54, y: 0.52, width: 0.43, height: 0.12);
    case 'equalizer.processing':
      return const NormalizedRect(x: 0.54, y: 0.7, width: 0.43, height: 0.12);
    default:
      return const NormalizedRect(x: 0.02, y: 0.02, width: 0.96, height: 0.2);
  }
}

/// Returns a copy of [layout] where every component is guaranteed a valid
/// normalized [ComponentLayout.rect]; components still on a legacy (rect-less)
/// profile get their premium default geometry.
ScreenLayout ensureScreenGeometry(
  ScreenLayout layout, {
  required String screenId,
  required LayoutVariant variant,
  required UiComponentRegistry registry,
}) {
  final count = registry.definitions.length;
  final components = <ComponentLayout>[];
  for (final component in layout.components) {
    final definition = registry.definitionFor(component.id);
    if (definition == null) continue;
    final withRect = component.rect == null
        ? component.copyWith(
            rect: defaultGeometryFor(
              screenId,
              variant,
              component.id,
              index: layout.components.indexOf(component),
              count: count,
            ),
          )
        : component;
    components.add(withRect);
  }
  return ScreenLayout(screenId: screenId, components: components);
}

/// Applies [ensureScreenGeometry] to every (screen, variant) pair in
/// [profile]. [registries] maps each screen id to its registry; entries whose
/// screen has no registry are left untouched.
LayoutProfile ensureProfileGeometry(
  LayoutProfile profile, {
  Map<String, UiComponentRegistry> registries = const {},
}) {
  final layouts = <LayoutKey, ScreenLayout>{};
  for (final entry in profile.layouts.entries) {
    final registry = registries[entry.key.screenId];
    if (registry == null) {
      layouts[entry.key] = entry.value;
      continue;
    }
    layouts[entry.key] = ensureScreenGeometry(
      entry.value,
      screenId: entry.key.screenId,
      variant: entry.key.variant,
      registry: registry,
    );
  }
  return profile.copyWith(layouts: layouts);
}

/// Returns a human-readable problem when [profile]'s layout for one
/// (screen, variant) is not safe to save, or null when it is valid.
///
/// Checks: every visible component has a valid placement inside its safe
/// bounds honoring its constraint, and no two visible components overlap.
/// The equalizer's mutually exclusive band/quick controls never collide with
/// each other, matching how the real screen shows only one of them at a time.
String? validateProfileGeometry(
  LayoutProfile profile, {
  required String screenId,
  required LayoutVariant variant,
  UiComponentRegistry? registry,
}) {
  final layout = profile.screenLayout(screenId, variant);
  if (layout == null) return null;
  String label(String problem) => '$problem ($screenId $variant)';
  final bounds = safeBoundsFor(screenId);
  final visible = layout.components.where((c) => c.visible).toList();
  for (final c in visible) {
    final rect = c.rect;
    if (rect == null || !rect.isValid) {
      return label('${c.id} has an invalid placement');
    }
    if (rect.x < bounds.x - 1e-6 ||
        rect.y < bounds.y - 1e-6 ||
        rect.right > bounds.right + 1e-6 ||
        rect.bottom > bounds.bottom + 1e-6) {
      return label('${c.id} is outside the safe area');
    }
    final constraint = geometryConstraintFor(screenId, c.id);
    if (rect.width < constraint.effectiveMinWidth - 1e-6 ||
        rect.height < constraint.effectiveMinHeight - 1e-6) {
      return label('${c.id} is too small');
    }
    if (rect.width > constraint.maxWidth + 1e-6 ||
        rect.height > constraint.maxHeight + 1e-6) {
      return label('${c.id} is too large');
    }
  }
  final mutuallyExclusive = screenId == kEqualizerScreenId
      ? const {'equalizer.quickControls', 'equalizer.bandControls'}
      : const <String>{};
  for (var i2 = 0; i2 < visible.length; i2++) {
    for (var j = i2 + 1; j < visible.length; j++) {
      final a = visible[i2];
      final b = visible[j];
      if (mutuallyExclusive.contains(a.id) &&
          mutuallyExclusive.contains(b.id)) {
        continue;
      }
      final ra = a.rect;
      final rb = b.rect;
      if (ra != null && rb != null && rectsOverlap(ra, rb)) {
        return label('${a.id} overlaps ${b.id}');
      }
    }
  }
  return null;
}

/// Walks the candidate rect in [stepPx] grid steps toward the bottom-right
/// until it no longer overlaps a [neighbor], returning the first collision-free
/// placement (or null when the bounds are exhausted). This is the "snap-back to
/// nearest valid placement" fallback for a dropped invalid position.
NormalizedRect? nearestNonOverlappingRect(
  NormalizedRect requested,
  List<NormalizedRect> neighbors, {
  required NormalizedRect bounds,
  required ComponentGeometryConstraint constraint,
  required Size canvasSize,
  double stepPx = 8,
}) {
  var rect = clampRectToBounds(requested, bounds, constraint);
  final stepX = stepPx / math.max(1.0, canvasSize.width);
  final stepY = stepPx / math.max(1.0, canvasSize.height);
  final maxTries = 200;
  for (var attempt = 0; attempt < maxTries; attempt++) {
    var collides = false;
    for (final neighbor in neighbors) {
      if (neighbor == rect) continue;
      if (neighbor != rect && rectsOverlap(rect, neighbor)) {
        collides = true;
        break;
      }
    }
    if (!collides) return rect;
    // Slide the candidate down-right by one grid step and clamp again.
    rect = clampRectToBounds(
      NormalizedRect(
        x: rect.x + stepX,
        y: rect.y + stepY,
        width: rect.width,
        height: rect.height,
      ),
      bounds,
      constraint,
    );
  }
  return null;
}

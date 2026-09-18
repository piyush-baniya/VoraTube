import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../app/widgets/vora_snackbar.dart';
import '../../../../core/audio/audio_effects.dart';
import '../../../../core/ui_customization/layout_geometry.dart';
import '../../../../core/ui_customization/ui_component_registry.dart';
import '../../../../core/ui_customization/ui_layout.dart';
import '../../../../shared/widgets/artwork_view.dart';
import '../../../player/presentation/providers/equalizer_providers.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../../player/presentation/widgets/equalizer_curve.dart';
import '../../../player/presentation/widgets/player_edit_blocks.dart';
import '../../../player/presentation/widgets/player_track_info.dart';
import '../../../player/presentation/widgets/rotating_artwork.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../providers/layout_providers.dart';

/// Freeform customization surface.
///
/// Unlike the old order/snap editor this does NOT re-render the real screens:
/// it is a dedicated canvas where each visible layout component is a movable,
/// resizable block whose placement persists as normalized geometry. The real
/// screens keep their curated hierarchy and only interpret visibility / size /
/// style / order; this canvas is purely additive.
///
/// Gestures update only the dragged block (via a per-block [ValueNotifier]) and
/// commit to the [LayoutEditSession] once on release, so an entire drag/resize
/// is a single undo entry and drag frames never hammer Riverpod.
class FreeformLayoutCanvas extends ConsumerStatefulWidget {
  const FreeformLayoutCanvas({super.key, required this.screenId});

  final String screenId;

  @override
  ConsumerState<FreeformLayoutCanvas> createState() =>
      FreeformLayoutCanvasState();
}

class FreeformLayoutCanvasState extends ConsumerState<FreeformLayoutCanvas> {
  static const double _gridPx = 8;

  final Map<String, ValueNotifier<NormalizedRect>> _rects = {};
  final Map<String, Widget> _surfaceCache = {};
  final ValueNotifier<List<SnapGuide>> _guides = ValueNotifier(const []);
  Size _canvasSize = Size.zero;
  ScreenLayout? _cachedLayout;

  String? _selectedId;
  String? _activeId;
  NormalizedRect? _dragStart;
  Offset? _dragOrigin;
  bool _dragResizeRight = false;
  bool _dragResizeBottom = false;
  bool _invalid = false;

  LayoutVariant get _variant => layoutVariantForSize(_canvasSize);

  LayoutEditController get _controller =>
      ref.read(layoutEditSessionProvider.notifier);

  UiComponentRegistry get _registry =>
      ref.read(screenRegistryProvider(widget.screenId));

  void clearSelection() => setState(() => _selectedId = null);

  ScreenLayout? get _layout => ref
      .watch(layoutEditSessionProvider)
      ?.screenLayout(widget.screenId, _variant);

  /// The ids rendered on the canvas: every visible component in layout order,
  /// minus the equalizer's mode-exclusive block (only the mode actually in use
  /// is shown, mirroring the real screen).
  List<String> _visibleIds(ScreenLayout layout) {
    final ids = <String>[];
    final eqMode = widget.screenId == kEqualizerScreenId
        ? ref.read(equalizerSettingsProvider).mode
        : null;
    for (final component in layout.components) {
      if (!component.visible) continue;
      if (eqMode != null &&
          ((eqMode == EqMode.simple &&
                  component.id == 'equalizer.bandControls') ||
              (eqMode == EqMode.advanced &&
                  component.id == 'equalizer.quickControls'))) {
        continue;
      }
      ids.add(component.id);
    }
    return ids;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRects();
  }

  @override
  void didUpdateWidget(covariant FreeformLayoutCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRects();
  }

  @override
  void dispose() {
    _guides.dispose();
    for (final notifier in _rects.values) {
      notifier.dispose();
    }
    super.dispose();
  }

  /// Keeps the notifier map aligned with the current session profile, reusing
  /// notifier identities so dragged blocks never flicker on rebuilds.
  void _syncRects() {
    final layout = _layout;
    if (layout == null) return;
    if (!identical(layout, _cachedLayout)) {
      _surfaceCache.clear();
      _cachedLayout = layout;
    }
    final ids = _visibleIds(layout);
    final wanted = <String>{};
    for (final id in ids) {
      wanted.add(id);
      final component = layout.component(id);
      final rect =
          component?.rect ?? defaultGeometryFor(widget.screenId, _variant, id);
      final existing = _rects[id];
      if (existing == null) {
        _rects[id] = ValueNotifier(rect);
      } else if (existing.value != rect) {
        existing.value = rect;
      }
    }
    _rects.removeWhere((id, _) => !wanted.contains(id));
    if (_selectedId != null && !wanted.contains(_selectedId)) {
      _selectedId = null;
    }
  }

  List<NormalizedRect> _neighborsOf(String id) => [
    for (final entry in _rects.entries)
      if (entry.key != id) entry.value.value,
  ];

  void _startDrag(
    String id,
    DragStartDetails details, {
    bool resizeRight = false,
    bool resizeBottom = false,
  }) {
    final start = _rects[id]?.value;
    if (start == null) return;
    _activeId = id;
    _dragStart = start;
    _dragOrigin = details.globalPosition;
    _dragResizeRight = resizeRight;
    _dragResizeBottom = resizeBottom;
    _invalid = false;
    _selectedId = id;
    setState(() {});
  }

  void _updateDrag(String id, DragUpdateDetails details) {
    final start = _dragStart;
    final origin = _dragOrigin;
    if (start == null || origin == null) return;
    if (_canvasSize.width <= 0 || _canvasSize.height <= 0) return;
    final dx = (details.globalPosition.dx - origin.dx) / _canvasSize.width;
    final dy = (details.globalPosition.dy - origin.dy) / _canvasSize.height;

    final NormalizedRect candidate;
    if (_dragResizeRight || _dragResizeBottom) {
      candidate = NormalizedRect(
        x: start.x,
        y: start.y,
        width: start.width + (_dragResizeRight ? dx : 0),
        height: start.height + (_dragResizeBottom ? dy : 0),
      );
    } else {
      candidate = NormalizedRect(
        x: start.x + dx,
        y: start.y + dy,
        width: start.width,
        height: start.height,
      );
    }

    final constraint = geometryConstraintFor(widget.screenId, id);
    final result = snapNormalizedRect(
      candidate: candidate,
      neighbors: _neighborsOf(id),
      bounds: safeBoundsFor(widget.screenId),
      constraint: constraint,
      canvasSize: _canvasSize,
      gridPx: _gridPx,
      moveX: !_dragResizeRight,
      moveY: !_dragResizeBottom,
      resizeRight: _dragResizeRight,
      resizeBottom: _dragResizeBottom,
    );

    var invalid = false;
    for (final neighbor in _neighborsOf(id)) {
      if (rectsOverlap(result.rect, neighbor)) {
        invalid = true;
        break;
      }
    }
    _invalid = invalid;
    _rects[id]?.value = result.rect;
    _guides.value = result.guides;
  }

  void _endDrag(String id) {
    if (_invalid) {
      // Snap-back to the last valid placement: collisions are never saved.
      final start = _dragStart;
      if (start != null) _rects[id]?.value = start;
      _invalid = false;
      if (mounted) {
        VoraSnackbar.error(context, 'Blocks cannot overlap.');
      }
    } else {
      final rect = _rects[id]?.value;
      if (rect != null) {
        _controller.commitRect(widget.screenId, _variant, id, rect);
      }
    }
    _activeId = null;
    _dragStart = null;
    _dragOrigin = null;
    _guides.value = const [];
  }

  /// Nudges/resizes a block from a menu stepper (one undo entry per tap).
  void _step(String id, NormalizedRect candidate) {
    final current = _rects[id]?.value;
    if (current == null) return;
    final constraint = geometryConstraintFor(widget.screenId, id);
    final clamped = clampRectToBounds(
      candidate,
      safeBoundsFor(widget.screenId),
      constraint,
    );
    for (final neighbor in _neighborsOf(id)) {
      if (rectsOverlap(clamped, neighbor)) return;
    }
    _rects[id]?.value = clamped;
    _controller.commitRect(widget.screenId, _variant, id, clamped);
  }

  Widget _surface(Rect rectPx, ComponentLayout? component) {
    final id = component?.id ?? '';
    final cached = _surfaceCache[id];
    if (cached != null) return cached;
    final surface = _buildSurface(context, rectPx, component);
    _surfaceCache[id] = surface;
    return surface;
  }

  @override
  Widget build(BuildContext context) {
    final layout = _layout;
    if (layout == null) {
      return const SizedBox.expand();
    }
    _syncRects();
    final ids = _visibleIds(layout);
    final mini = widget.screenId == kMiniScreenId;

    return LayoutBuilder(
      builder: (context, constraints) {
        final nextSize = Size(constraints.maxWidth, constraints.maxHeight);
        _canvasSize = nextSize;
        final size = nextSize;
        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: _GridSurface(canvasSize: size, gridPx: _gridPx),
              ),
              if (mini)
                Positioned(
                  left: 4,
                  right: 4,
                  top: size.height * 0.8,
                  bottom: 4,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(AppTokens.rLg),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant
                              .withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned.fill(child: GuideOverlay(guides: _guides)),
              for (final id in ids)
                AnimatedBuilder(
                  animation: _rects[id]!,
                  builder: (context, _) {
                    final rect = _rects[id]!.value;
                    final rectPx = Rect.fromLTWH(
                      rect.x * size.width,
                      rect.y * size.height,
                      rect.width * size.width,
                      rect.height * size.height,
                    );
                    final component = layout.component(id);
                    return Positioned.fromRect(
                      rect: rectPx,
                      child: _CanvasBlock(
                        id: id,
                        surface: _surface(rectPx, component),
                        isSelected: _selectedId == id,
                        invalid: _invalid && _activeId == id,
                        dragging: _activeId == id,
                        onTap: () => setState(() => _selectedId = id),
                        onDragStart: (d) => _startDrag(id, d),
                        onDragUpdate: (d) => _updateDrag(id, d),
                        onDragEnd: (d) => _endDrag(id),
                        onResizeStart: (d) => _startDrag(
                          id,
                          d,
                          resizeRight: true,
                          resizeBottom: true,
                        ),
                        onResizeUpdate: (d) => _updateDrag(id, d),
                        onResizeEnd: (d) => _endDrag(id),
                      ),
                    );
                  },
                ),
              if (_selectedId != null && _rects[_selectedId] != null)
                AnimatedBuilder(
                  animation: _rects[_selectedId]!,
                  builder: (context, _) {
                    final rect = _rects[_selectedId]!.value;
                    final component = _layout?.component(_selectedId!);
                    final definition = _registry.definitionFor(_selectedId!);
                    final label =
                        '${definition?.label ?? ''} '
                        '(${(component?.size ?? ComponentSize.medium).label})';
                    final left = (rect.x * size.width)
                        .clamp(0.0, math.max(0.0, size.width - 190))
                        .toDouble();
                    final top = rect.y * size.height - 34 < 4
                        ? rect.bottom * size.height + 6
                        : rect.y * size.height - 34;
                    return Positioned(
                      left: left,
                      top: top,
                      child: _SelectedChip(
                        label: label,
                        onTap: () => _openBlockMenu(_selectedId!),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openBlockMenu(String id) async {
    final definition = _registry.definitionFor(id);
    if (definition == null) return;
    final screenId = widget.screenId;
    final variant = _variant;
    final step = 0.02;

    Future<void> move(double dx, double dy) async {
      final current = _rects[id]?.value;
      if (current == null) return;
      _step(
        id,
        NormalizedRect(
          x: current.x + dx,
          y: current.y + dy,
          width: current.width,
          height: current.height,
        ),
      );
    }

    Future<void> resize(double dw, double dh) async {
      final current = _rects[id]?.value;
      if (current == null) return;
      _step(
        id,
        NormalizedRect(
          x: current.x,
          y: current.y,
          width: current.width + dw,
          height: current.height + dh,
        ),
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        Widget chip({
          required IconData icon,
          required String title,
          required VoidCallback onTap,
        }) {
          return ActionChip(
            avatar: Icon(icon, size: 16),
            label: Text(title),
            onPressed: onTap,
          );
        }

        final rows = <Widget>[
          ListTile(
            title: Text(
              definition.label,
              style: Theme.of(sheetContext).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(definition.description),
          ),
          const Divider(height: 1),
        ];
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.s2),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                chip(
                  icon: Icons.arrow_upward_rounded,
                  title: 'Move up',
                  onTap: () => move(0, -step),
                ),
                chip(
                  icon: Icons.arrow_downward_rounded,
                  title: 'Move down',
                  onTap: () => move(0, step),
                ),
                chip(
                  icon: Icons.arrow_back_rounded,
                  title: 'Move left',
                  onTap: () => move(-step, 0),
                ),
                chip(
                  icon: Icons.arrow_forward_rounded,
                  title: 'Move right',
                  onTap: () => move(step, 0),
                ),
              ],
            ),
          ),
        );
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.s2),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                chip(
                  icon: Icons.remove_rounded,
                  title: 'Decrease width',
                  onTap: () => resize(-step, 0),
                ),
                chip(
                  icon: Icons.add_rounded,
                  title: 'Increase width',
                  onTap: () => resize(step, 0),
                ),
                chip(
                  icon: Icons.remove_circle_outline_rounded,
                  title: 'Decrease height',
                  onTap: () => resize(0, -step),
                ),
                chip(
                  icon: Icons.add_circle_outline_rounded,
                  title: 'Increase height',
                  onTap: () => resize(0, step),
                ),
              ],
            ),
          ),
        );
        if (definition.canHide) {
          rows.add(const Divider(height: 1));
          rows.add(
            ListTile(
              leading: Icon(
                Icons.visibility_off_outlined,
                color: colorScheme.onSurfaceVariant,
              ),
              title: const Text('Hide'),
              onTap: () {
                Navigator.pop(sheetContext);
                _controller.hide(screenId, variant, id);
                setState(() => _selectedId = null);
              },
            ),
          );
        }
        rows.add(
          ListTile(
            leading: Icon(
              Icons.restart_alt_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
            title: const Text('Reset'),
            onTap: () {
              Navigator.pop(sheetContext);
              _controller.resetComponent(screenId, variant, id);
            },
          ),
        );

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSurface(
    BuildContext context,
    Rect rectPx,
    ComponentLayout? component,
  ) {
    final id = component?.id ?? '';
    final colorScheme = Theme.of(context).colorScheme;
    final w = rectPx.width;
    final h = rectPx.height;
    switch (widget.screenId) {
      case kPlayerScreenId:
        final snapshot = ref.watch(playbackStateProvider);
        if (snapshot.current == null) return const SizedBox.shrink();
        final song = snapshot.current!;
        return switch (id) {
          'player.artwork' => Center(
            child: RotatingArtwork(
              path: song.artPath,
              heroTag: null,
              size: math.min(w, h) * 0.94,
            ),
          ),
          'player.trackInfo' => PlayerTrackInfo(
            title: song.title,
            artist: song.artist,
            album: song.album,
            size: component?.size ?? ComponentSize.medium,
            compact: w < 320,
          ),
          'player.secondaryControls' => PlayerSecondaryHost(snapshot: snapshot),
          'player.progress' => PlayerProgressHost(progress: component),
          'player.primaryControls' => PlayerControlsHost(
            snapshot: snapshot,
            size: component?.size ?? ComponentSize.medium,
          ),
          _ => const SizedBox.shrink(),
        };
      case kMiniScreenId:
        final song = ref.watch(currentTrackProvider);
        return switch (id) {
          'mini.artwork' => Center(
            child: CompactArtwork(
              path: song?.artPath,
              size: math.min(w, h) * 0.9,
              heroTag: null,
              borderRadius: AppTokens.rMd,
            ),
          ),
          'mini.trackInfo' => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song?.title ?? 'Nothing playing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (song?.artist != null)
                  Text(
                    song!.artist!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          'mini.progress' => const _MiniProgressSurface(),
          'mini.controls' => const _MiniControlsSurface(),
          'mini.secondaryControls' => const _MiniSecondarySurface(),
          _ => const SizedBox.shrink(),
        };
      case kHomeScreenId:
        return switch (id) {
          'home.continueListening' => const _HomeContinueSurface(),
          'home.listeningInsights' => const _HomeInsightsSurface(),
          'home.playlists' => const _HomePlaylistsSurface(),
          'home.allSongs' => const _HomeAllSongsSurface(),
          _ => const SizedBox.shrink(),
        };
      case kEqualizerScreenId:
        final audio = ref.watch(audioSettingsProvider);
        final levels = effectiveEqLevels(
          preset: audio.eqPreset,
          customLevels: audio.eqCustomLevels,
        );
        final song = ref.watch(currentTrackProvider);
        return switch (id) {
          'equalizer.nowPlaying' => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ArtworkView(
                  path: song?.artPath,
                  size: 44,
                  radius: AppTokens.rMd,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song?.title ?? 'Nothing playing',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        song?.artist ?? 'Play a track to shape its sound',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          'equalizer.curve' => Center(
            child: EqualizerCurve(
              levels: levels,
              enabled: audio.eqEnabled,
              interactive: false,
              height: math.max(40, h - 8),
              showLabels: h > 160,
            ),
          ),
          'equalizer.presets' => _EqPresetsSurface(preset: audio.eqPreset),
          'equalizer.quickControls' => const _EqQuickControlsSurface(),
          'equalizer.bandControls' => const _EqBandControlsSurface(),
          'equalizer.preamp' => const _EqPreampSurface(),
          'equalizer.processing' => const _EqProcessingSurface(),
          _ => const SizedBox.shrink(),
        };
      default:
        return const SizedBox.shrink();
    }
  }
}

/// One movable/resizable block on the canvas: the surface inside a frame with
/// a bottom-right resize handle; drag repositions, tap selects.
class _CanvasBlock extends StatelessWidget {
  const _CanvasBlock({
    required this.id,
    required this.surface,
    required this.isSelected,
    required this.invalid,
    required this.dragging,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  final String id;
  final Widget surface;
  final bool isSelected;
  final bool invalid;
  final bool dragging;
  final VoidCallback onTap;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final GestureDragStartCallback onResizeStart;
  final GestureDragUpdateCallback onResizeUpdate;
  final GestureDragEndCallback onResizeEnd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = invalid
        ? colorScheme.error
        : isSelected
        ? colorScheme.primary
        : colorScheme.onSurface.withValues(alpha: 0.28);
    final borderWidth = (invalid || isSelected) ? 2.0 : 1.2;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onPanStart: onDragStart,
      onPanUpdate: onDragUpdate,
      onPanEnd: onDragEnd,
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTokens.rLg),
                child: ColoredBox(
                  color: colorScheme.surface.withValues(
                    alpha: invalid ? 0.6 : 0.85,
                  ),
                  child: RepaintBoundary(child: surface),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTokens.rLg),
                    border: Border.all(color: borderColor, width: borderWidth),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              width: 28,
              height: 28,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: onResizeStart,
                onPanUpdate: onResizeUpdate,
                onPanEnd: onResizeEnd,
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.inverseSurface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(AppTokens.rLg),
                    ),
                  ),
                  child: Icon(
                    Icons.open_in_full_rounded,
                    size: 14,
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onInverseSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The small label chip shown over the selected block; tapping it opens the
/// block's action menu (move, resize, hide, reset).
class _SelectedChip extends StatelessWidget {
  const _SelectedChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.s2),
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(AppTokens.rFull),
          border: Border.all(
            color: colorScheme.outlineVariant,
            width: AppTokens.borderHairline,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onInverseSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppTokens.s1),
            Icon(
              Icons.tune_rounded,
              size: 15,
              color: colorScheme.onInverseSurface.withValues(alpha: 0.8),
            ),
          ],
        ),
      ),
    );
  }
}

/// A faint 8dp alignment grid plus stronger center/corner cues.
class _GridSurface extends StatelessWidget {
  const _GridSurface({required this.canvasSize, required this.gridPx});

  final Size canvasSize;
  final double gridPx;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _GridPainter(
          color: Theme.of(context).colorScheme.onSurface
              .withValues(alpha: 0.035),
          strongColor: Theme.of(context).colorScheme.onSurface
              .withValues(alpha: 0.07),
          gridPx: gridPx,
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.color,
    required this.strongColor,
    required this.gridPx,
  });

  final Color color;
  final Color strongColor;
  final double gridPx;

  @override
  void paint(Canvas canvas, Size size) {
    final thin = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    final strong = Paint()
      ..color = strongColor
      ..strokeWidth = 1;
    for (var x = gridPx; x < size.width; x += gridPx) {
      final paint = (x / gridPx) % 8 == 0 ? strong : thin;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = gridPx; y < size.height; y += gridPx) {
      final paint = (y / gridPx) % 8 == 0 ? strong : thin;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.gridPx != gridPx ||
      oldDelegate.color != color ||
      oldDelegate.strongColor != strongColor;
}

/// Draws the active snap guides as full-canvas lines.
class GuideOverlay extends StatelessWidget {
  const GuideOverlay({super.key, required this.guides});

  final ValueListenable<List<SnapGuide>> guides;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary.withValues(alpha: 0.85);
    return ValueListenableBuilder<List<SnapGuide>>(
      valueListenable: guides,
      builder: (context, value, _) {
        if (value.isEmpty) return const SizedBox.shrink();
        return IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _GuidePainter(color: color, guides: value),
          ),
        );
      },
    );
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter({required this.color, required this.guides});

  final Color color;
  final List<SnapGuide> guides;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4;
    for (final guide in guides) {
      if (guide.vertical) {
        canvas.drawLine(
          Offset(guide.position * size.width, 0),
          Offset(guide.position * size.width, size.height),
          paint,
        );
      } else {
        canvas.drawLine(
          Offset(0, guide.position * size.height),
          Offset(size.width, guide.position * size.height),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.guides != guides;
}

// ── Mini surfaces ───────────────────────────────────────────────────────────

class _MiniProgressSurface extends ConsumerWidget {
  const _MiniProgressSurface();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final snapshot = ref.watch(playbackStateProvider);
    final position = ref.watch(playbackPositionProvider).valueOrNull;
    final duration = snapshot.durationMs;
    final value = (duration > 0 && position != null)
        ? (position.inMilliseconds / duration).clamp(0.0, 1.0)
        : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 4,
            backgroundColor: colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
    );
  }
}

class _MiniControlsSurface extends ConsumerWidget {
  const _MiniControlsSurface();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final snapshot = ref.watch(playbackStateProvider);
    IconData icon(IconData base) => base;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.skip_previous_rounded,
          size: 20,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                colorScheme.primary,
                colorScheme.primary.withValues(alpha: 0.8),
              ],
            ),
          ),
          child: Icon(
            icon(
              snapshot.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
            size: 18,
            color: colorScheme.onPrimary,
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          Icons.skip_next_rounded,
          size: 20,
          color: colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _MiniSecondarySurface extends ConsumerWidget {
  const _MiniSecondarySurface();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final snapshot = ref.watch(playbackStateProvider);
    return Center(
      child: Icon(
        snapshot.shuffleEnabled
            ? Icons.shuffle_on_rounded
            : Icons.shuffle_rounded,
        size: 18,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}

// ── Home surfaces ───────────────────────────────────────────────────────────

class _HomeContinueSurface extends ConsumerWidget {
  const _HomeContinueSurface();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final current = ref.watch(currentTrackProvider);
    final accent = colorScheme.primary;

    Widget child;
    if (current != null) {
      child = Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppTokens.s3,
        runSpacing: 4,
        children: [
          CompactArtwork(
            path: current.artPath,
            size: 84,
            heroTag: null,
            borderRadius: AppTokens.rMd,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Continue Listening',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                current.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      child = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.12),
            ),
            child: Icon(
              Icons.music_note_rounded,
              size: 26,
              color: accent.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppTokens.s2),
          Text(
            'Start Listening',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Select any track from your library to begin playback.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    return Center(
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }
}

class _HomeInsightsSurface extends StatelessWidget {
  const _HomeInsightsSurface();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Icon(Icons.insights_rounded, size: 18, color: colorScheme.primary),
            Text(
              'Your Listening',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Stats after more history',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomePlaylistsSurface extends StatelessWidget {
  const _HomePlaylistsSurface();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Icon(
              Icons.queue_music_rounded,
              size: 18,
              color: colorScheme.primary,
            ),
            Text(
              'Playlists',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Your curated collections',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeAllSongsSurface extends StatelessWidget {
  const _HomeAllSongsSurface();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Icon(
              Icons.library_music_rounded,
              size: 18,
              color: colorScheme.primary,
            ),
            Text(
              'All Songs',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Browse your whole library',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Equalizer surfaces ───────────────────────────────────────────────────────

class _EqPresetsSurface extends StatelessWidget {
  const _EqPresetsSurface({required this.preset});

  final EqPreset preset;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          for (final p in EqPreset.values)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: p == preset
                    ? colorScheme.primary.withValues(alpha: 0.14)
                    : colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(AppTokens.rFull),
              ),
              child: Text(
                p.label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: p == preset
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EqQuickControlsSurface extends StatelessWidget {
  const _EqQuickControlsSurface();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const labels = ['Bass Boost', 'Vocals', 'Treble', 'Flat'];
    return Center(
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          for (var i = 0; i < labels.length; i++)
            Chip(
              avatar: Icon(
                Icons.music_note_rounded,
                size: 15,
                color: colorScheme.primary,
              ),
              label: Text(labels[i]),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _EqBandControlsSurface extends StatelessWidget {
  const _EqBandControlsSurface();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            for (final band in const ['60', '230', '910', '3.6k', '14k'])
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      band,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EqPreampSurface extends StatelessWidget {
  const _EqPreampSurface();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Icon(
              Icons.volume_up_rounded,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: const Slider(value: 0.5, onChanged: null),
              ),
            ),
            Text(
              'Preamp',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _EqProcessingSurface extends StatelessWidget {
  const _EqProcessingSurface();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Wrap(
        spacing: 8,
        alignment: WrapAlignment.center,
        children: [
          Chip(
            avatar: Icon(
              Icons.speed_rounded,
              size: 15,
              color: colorScheme.primary,
            ),
            label: const Text('1.0x'),
            visualDensity: VisualDensity.compact,
          ),
          Chip(
            avatar: Icon(
              Icons.compare_arrows_rounded,
              size: 15,
              color: colorScheme.primary,
            ),
            label: const Text('ReplayGain'),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

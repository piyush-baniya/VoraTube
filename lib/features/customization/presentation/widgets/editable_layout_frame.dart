import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/ui_customization/ui_component_registry.dart';
import '../../../../core/ui_customization/ui_layout.dart';
import '../providers/layout_providers.dart';
import 'layout_edit_scope.dart';

/// Wraps one real UI block during live customization.
///
/// While the [LayoutEditScope] is present the frame renders the block with an
/// animated gray outline, exposes a chip that opens the block's action menu
/// (move up/down, resize, style, hide, reset) and lets the block be dragged to
/// a new position. The real child is inert underneath ([AbsorbPointer]) so
/// normal taps never fire while editing, but all real state stays visible.
class EditableLayoutFrame extends ConsumerStatefulWidget {
  const EditableLayoutFrame({
    super.key,
    required this.componentId,
    required this.index,
    required this.itemCount,
    required this.definition,
    required this.child,
  });

  final String componentId;

  /// Position of this block in the full component list (used for reordering).
  final int index;
  final int itemCount;
  final UiComponentDefinition definition;
  final Widget child;

  @override
  ConsumerState<EditableLayoutFrame> createState() =>
      _EditableLayoutFrameState();
}

class _EditableLayoutFrameState extends ConsumerState<EditableLayoutFrame> {
  double _resizeAccum = 0;
  String? _sizeLabel;
  Timer? _sizeTimer;

  @override
  void dispose() {
    _sizeTimer?.cancel();
    super.dispose();
  }

  LayoutVariant get _variant =>
      layoutVariantForSize(MediaQuery.sizeOf(context));

  String get _screenId => LayoutEditScope.of(context).screenId;

  LayoutEditController get _controller =>
      ref.read(layoutEditSessionProvider.notifier);

  void _drop(DragTargetDetails<String> details) {
    final draggedId = details.data;
    if (draggedId == widget.componentId) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.offset);
    final before = local.dy < box.size.height / 2;
    final layout = _controller.screenLayout(_screenId, _variant);
    if (layout == null) return;
    final from = layout.components.indexWhere((c) => c.id == draggedId);
    if (from < 0) return;
    var to = before ? widget.index : widget.index + 1;
    if (to > from) to -= 1;
    _controller.moveComponent(_screenId, _variant, from, to);
  }

  ComponentLayout? _component() => _controller
      .screenLayout(_screenId, _variant)
      ?.component(widget.componentId);

  void _applySize(ComponentSize size) {
    _controller.setSize(_screenId, _variant, widget.componentId, size);
    setState(() => _sizeLabel = '${widget.definition.label}: ${size.label}');
    _sizeTimer?.cancel();
    _sizeTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _sizeLabel = null);
    });
  }

  void _onResizeStart(DragStartDetails details) {
    _resizeAccum = 0;
  }

  void _onResizeUpdate(DragUpdateDetails details) {
    _resizeAccum += details.delta.dy;
    final allowed = widget.definition.allowedSizes;
    final current = _component()?.size ?? widget.definition.defaultSize;
    var index = allowed.indexOf(current);
    if (index < 0) index = allowed.indexOf(widget.definition.defaultSize);
    while (_resizeAccum >= 32) {
      if (index < allowed.length - 1) {
        index += 1;
        _applySize(allowed[index]);
      }
      _resizeAccum -= 32;
    }
    while (_resizeAccum <= -32) {
      if (index > 0) {
        index -= 1;
        _applySize(allowed[index]);
      }
      _resizeAccum += 32;
    }
  }

  Future<void> _showContextMenu() async {
    final component = _component();
    if (component == null) return;
    final canMoveUp = widget.definition.canReorder && widget.index > 0;
    final canMoveDown =
        widget.definition.canReorder && widget.index < widget.itemCount - 1;
    final allowedSizes = widget.definition.allowedSizes;
    final sizeIndex = allowedSizes.indexOf(component.size);
    final canShrink =
        widget.definition.canResize && allowedSizes.length > 1 && sizeIndex > 0;
    final canGrow =
        widget.definition.canResize &&
        allowedSizes.length > 1 &&
        sizeIndex >= 0 &&
        sizeIndex < allowedSizes.length - 1;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  title: Text(
                    widget.definition.label,
                    style: Theme.of(sheetContext).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(widget.definition.description),
                ),
                const Divider(height: 1),
                if (canMoveUp)
                  ListTile(
                    leading: const Icon(Icons.arrow_upward_rounded),
                    title: const Text('Move up'),
                    onTap: () {
                      _controller.moveComponent(
                        _screenId,
                        _variant,
                        widget.index,
                        widget.index - 1,
                      );
                      Navigator.pop(sheetContext);
                    },
                  ),
                if (canMoveDown)
                  ListTile(
                    leading: const Icon(Icons.arrow_downward_rounded),
                    title: const Text('Move down'),
                    onTap: () {
                      _controller.moveComponent(
                        _screenId,
                        _variant,
                        widget.index,
                        widget.index + 2,
                      );
                      Navigator.pop(sheetContext);
                    },
                  ),
                if (canShrink)
                  ListTile(
                    leading: const Icon(Icons.remove_rounded),
                    title: const Text('Decrease size'),
                    onTap: () {
                      _controller.setSize(
                        _screenId,
                        _variant,
                        widget.componentId,
                        allowedSizes[sizeIndex - 1],
                      );
                      Navigator.pop(sheetContext);
                    },
                  ),
                if (canGrow)
                  ListTile(
                    leading: const Icon(Icons.add_rounded),
                    title: const Text('Increase size'),
                    onTap: () {
                      _controller.setSize(
                        _screenId,
                        _variant,
                        widget.componentId,
                        allowedSizes[sizeIndex + 1],
                      );
                      Navigator.pop(sheetContext);
                    },
                  ),
                if (widget.definition.allowedStyleIds.length > 1)
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('Style'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _showStyleSheet();
                    },
                  ),
                if (widget.definition.canHide)
                  ListTile(
                    leading: const Icon(Icons.visibility_off_outlined),
                    title: const Text('Hide'),
                    onTap: () {
                      _controller.hide(_screenId, _variant, widget.componentId);
                      Navigator.pop(sheetContext);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.restart_alt_rounded),
                  title: const Text('Reset'),
                  onTap: () {
                    _controller.resetComponent(
                      _screenId,
                      _variant,
                      widget.componentId,
                    );
                    Navigator.pop(sheetContext);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showStyleSheet() async {
    final component = _component();
    if (component == null) return;
    final effective =
        component.styleId ?? widget.definition.effectiveDefaultStyleId;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.s5,
                  AppTokens.s1,
                  AppTokens.s5,
                  AppTokens.s2,
                ),
                child: Text(
                  '${widget.definition.label} style',
                  style: Theme.of(sheetContext).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              for (final styleId in widget.definition.allowedStyleIds)
                ListTile(
                  title: Text(_styleLabel(styleId)),
                  trailing: styleId == effective
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () {
                    _controller.setStyle(
                      _screenId,
                      _variant,
                      widget.componentId,
                      styleId,
                    );
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  static String _styleLabel(String id) =>
      id.isEmpty ? id : '${id[0].toUpperCase()}${id.substring(1)}';

  @override
  Widget build(BuildContext context) {
    // Outside a customization session the block is passed through untouched so
    // normal playback never shows frames or fires any editor gesture.
    if (!LayoutEditScope.isEditing(context)) {
      return widget.child;
    }
    final bridge = LayoutEditScope.of(context);
    final isSelected = bridge.selectedId == widget.componentId;
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppTokens.rLg);
    final interactive =
        widget.definition.canReorder || widget.definition.canResize;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          details.data != widget.componentId && widget.definition.canReorder,
      onAcceptWithDetails: _drop,
      builder: (context, candidateData, _) {
        final hovered = candidateData.isNotEmpty;
        final outlineColor = isSelected
            ? colorScheme.primary.withValues(alpha: 0.75)
            : colorScheme.onSurface.withValues(alpha: hovered ? 0.6 : 0.34);

        return LongPressDraggable<String>(
          data: widget.componentId,
          maxSimultaneousDrags: 1,
          onDragStarted: () => bridge.select(widget.componentId),
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: outlineColor, width: 1.5),
              ),
              child: Opacity(
                opacity: 0.94,
                child: IgnorePointer(child: widget.child),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: widget.child),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => bridge.select(isSelected ? null : widget.componentId),
            child: Stack(
              children: [
                // The block is the only non-positioned child so the Stack is
                // sized by the block's content even under unbounded list
                // constraints (Positioned children alone would make the Stack
                // expand to an infinite incoming extent).
                IgnorePointer(child: AbsorbPointer(child: widget.child)),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(
                          color: isSelected
                              ? colorScheme.primary.withValues(alpha: 0.75)
                              : colorScheme.onSurface.withValues(
                                  alpha: hovered ? 0.6 : 0.34,
                                ),
                          width: isSelected ? 2 : 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
                if (hovered && interactive)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: colorScheme.onSurface.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                if (isSelected)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: _SelectedChip(
                      label:
                          '${widget.definition.label} '
                          '(${(_component()?.size ?? widget.definition.defaultSize).label})',
                      onTap: () => _showContextMenu(),
                    ),
                  ),
                if (isSelected && _sizeLabel != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 30,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.s3,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.inverseSurface,
                            borderRadius: BorderRadius.circular(
                              AppTokens.rFull,
                            ),
                          ),
                          child: Text(
                            _sizeLabel!,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: colorScheme.onInverseSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (isSelected &&
                    widget.definition.canResize &&
                    widget.definition.allowedSizes.length > 1)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 2,
                    child: Center(
                      child: Tooltip(
                        message: 'Drag up or down to resize',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragStart: _onResizeStart,
                          onVerticalDragUpdate: _onResizeUpdate,
                          child: Container(
                            width: 64,
                            height: 22,
                            decoration: BoxDecoration(
                              color: colorScheme.inverseSurface,
                              borderRadius: BorderRadius.circular(
                                AppTokens.rFull,
                              ),
                              border: Border.all(
                                color: colorScheme.outlineVariant,
                                width: AppTokens.borderHairline,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.swap_vert_rounded,
                              size: 15,
                              color: colorScheme.onInverseSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The small label chip shown over the selected block; tapping it opens the
/// block's action menu (Move up/down, size, style, hide, reset).
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
              constraints: const BoxConstraints(maxWidth: 160),
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

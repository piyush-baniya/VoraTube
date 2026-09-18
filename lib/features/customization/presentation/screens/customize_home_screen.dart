import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/widgets/vora_snackbar.dart';
import '../../../../core/ui_customization/layout_edit_session.dart';
import '../../../../core/ui_customization/ui_component_registry.dart';
import '../../../../core/ui_customization/ui_layout.dart';
import '../../../../core/ui_customization/ui_layout_normalizer.dart';
import '../providers/layout_providers.dart';

/// The Customize Home editor: a live preview plus a reorderable list of
/// sections with visibility, size and style controls.
///
/// Edits are held in a [LayoutEditSession] and only committed on Save, so
/// Cancel (or a system back) leaves the saved Home untouched.
class CustomizeHomeScreen extends ConsumerStatefulWidget {
  const CustomizeHomeScreen({super.key});

  @override
  ConsumerState<CustomizeHomeScreen> createState() =>
      _CustomizeHomeScreenState();
}

class _CustomizeHomeScreenState extends ConsumerState<CustomizeHomeScreen> {
  LayoutEditSession? _session;
  LayoutVariant? _variant;
  bool _saving = false;
  bool _leaving = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(layoutProfileProvider);
    final loaded = async.valueOrNull;
    if (loaded != null) {
      _session ??= LayoutEditSession(baseline: loaded);
      _variant ??= layoutVariantForSize(MediaQuery.sizeOf(context));
    }
    final session = _session;
    return PopScope(
      canPop: _leaving || _saving || !(session?.isDirty ?? false),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Customize Home'),
          actions: [
            IconButton(
              tooltip: 'Undo',
              onPressed: session?.canUndo == true ? _undo : null,
              icon: const Icon(Icons.undo_rounded),
            ),
            IconButton(
              tooltip: 'Redo',
              onPressed: session?.canRedo == true ? _redo : null,
              icon: const Icon(Icons.redo_rounded),
            ),
            IconButton(
              tooltip: 'Reset to default',
              onPressed: session == null ? null : _reset,
              icon: const Icon(Icons.restart_alt_rounded),
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppTokens.s2),
              child: TextButton(
                onPressed: (session?.isDirty ?? false) && !_saving
                    ? _save
                    : null,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              const Center(child: Text('Could not load your layout.')),
          data: (_) => _buildEditor(context, session!),
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context, LayoutEditSession session) {
    final registry = ref.watch(uiComponentRegistryProvider);
    final variant = _variant!;
    final layout =
        session.current.screenLayout(kHomeScreenId, variant) ??
        defaultScreenLayout(kHomeScreenId, registry);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PresetBar(selected: session.current.preset, onSelected: _applyPreset),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
          child: _HomeLayoutPreview(layout: layout, variant: variant),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.s5,
            AppTokens.s4,
            AppTokens.s5,
            AppTokens.s2,
          ),
          child: Text(
            'SECTIONS · drag to reorder',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: AppTokens.s8),
            buildDefaultDragHandles: false,
            itemCount: layout.components.length,
            onReorderItem: _reorder,
            itemBuilder: (context, index) {
              final component = layout.components[index];
              final definition = registry.definitionFor(component.id);
              if (definition == null) {
                return const SizedBox.shrink(key: ValueKey('unknown'));
              }
              return _ComponentEditorTile(
                key: ValueKey(component.id),
                index: index,
                definition: definition,
                component: component,
                onChanged: _updateComponent,
              );
            },
          ),
        ),
      ],
    );
  }

  void _updateComponent(ComponentLayout updated) {
    final session = _session;
    final variant = _variant;
    if (session == null || variant == null) return;
    final layout = session.current.screenLayout(kHomeScreenId, variant);
    if (layout == null) return;
    session.apply(
      session.current.replaceScreen(
        kHomeScreenId,
        variant,
        layout.replaceComponent(updated),
      ),
    );
    setState(() {});
  }

  void _reorder(int oldIndex, int newIndex) {
    final session = _session;
    final variant = _variant;
    if (session == null || variant == null) return;
    final registry = ref.read(uiComponentRegistryProvider);
    final layout = session.current.screenLayout(kHomeScreenId, variant);
    if (layout == null) return;
    final components = [...layout.components];
    final moved = components.removeAt(oldIndex);
    final definition = registry.definitionFor(moved.id);
    if (definition == null || !definition.canReorder) return;
    components.insert(newIndex, moved);
    session.apply(
      session.current.replaceScreen(
        kHomeScreenId,
        variant,
        ScreenLayout(screenId: kHomeScreenId, components: components),
      ),
    );
    setState(() {});
  }

  void _applyPreset(LayoutPreset preset) {
    final session = _session;
    if (session == null) return;
    final registry = ref.read(uiComponentRegistryProvider);
    final layouts = <LayoutKey, ScreenLayout>{...session.current.layouts};
    for (final variant in LayoutVariant.values) {
      layouts[LayoutKey(kHomeScreenId, variant)] = applyLayoutPreset(
        preset,
        kHomeScreenId,
        registry,
      );
    }
    session.apply(session.current.copyWith(preset: preset, layouts: layouts));
    setState(() {});
  }

  void _reset() {
    final registry = ref.read(uiComponentRegistryProvider);
    _session?.apply(defaultLayoutProfile(registry));
    setState(() {});
  }

  void _undo() {
    if (_session?.undo() == true) setState(() {});
  }

  void _redo() {
    if (_session?.redo() == true) setState(() {});
  }

  Future<void> _save() async {
    final session = _session;
    if (session == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(layoutProfileProvider.notifier).save(session.current);
      session.markSaved();
      if (!mounted) return;
      VoraSnackbar.success(context, 'Home layout saved.', title: 'Saved');
      _leave();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      VoraSnackbar.error(context, 'Could not save the layout.');
    }
  }

  Future<void> _confirmDiscard() async {
    if (_session?.isDirty != true) {
      _leave();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'Your Home customization changes have not been saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) _leave();
  }

  void _leave() {
    setState(() => _leaving = true);
    Navigator.of(context).pop();
  }
}

/// Horizontal preset chooser.
class _PresetBar extends StatelessWidget {
  const _PresetBar({required this.selected, required this.onSelected});

  final LayoutPreset selected;
  final ValueChanged<LayoutPreset> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
        itemCount: LayoutPreset.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppTokens.s2),
        itemBuilder: (context, index) {
          final preset = LayoutPreset.values[index];
          return Center(
            child: ChoiceChip(
              label: Text(preset.label),
              selected: preset == selected,
              onSelected: (_) => onSelected(preset),
            ),
          );
        },
      ),
    );
  }
}

/// A stylized, always-updating representation of the configured Home.
class _HomeLayoutPreview extends StatelessWidget {
  const _HomeLayoutPreview({required this.layout, required this.variant});

  final ScreenLayout layout;
  final LayoutVariant variant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.s1),
          child: Text(
            'PREVIEW · ${variant.label.toUpperCase()}',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Container(
          height: 216,
          padding: const EdgeInsets.all(AppTokens.s3),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTokens.rXl),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: AppTokens.borderHairline,
            ),
          ),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final component in layout.components)
                  if (component.visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.s2),
                      child: _PreviewBlock(component: component),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One section's stylized preview block. Dimensions track the component's
/// size preset and shape tracks its style, so the preview reflects edits.
class _PreviewBlock extends StatelessWidget {
  const _PreviewBlock({required this.component});

  final ComponentLayout component;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;
    final soft = colorScheme.onSurfaceVariant.withValues(alpha: 0.18);

    switch (component.id) {
      case 'home.continueListening':
        final height = switch (component.size) {
          ComponentSize.small => 44.0,
          ComponentSize.medium => 62.0,
          ComponentSize.large => 82.0,
        };
        return _block(
          height: height,
          color: accent.withValues(alpha: 0.16),
          child: Row(
            children: [
              _square(height - 16, accent.withValues(alpha: 0.35)),
              const SizedBox(width: AppTokens.s3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bar(0.5, soft),
                    if (component.styleId != 'compact') ...[
                      const SizedBox(height: 6),
                      _bar(0.3, soft),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      case 'home.listeningInsights':
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _block(
                    height: component.size == ComponentSize.small ? 26 : 32,
                    color: accent.withValues(alpha: 0.12),
                    child: _bar(0.5, soft),
                  ),
                ),
                const SizedBox(width: AppTokens.s2),
                Expanded(
                  child: _block(
                    height: component.size == ComponentSize.small ? 26 : 32,
                    color: accent.withValues(alpha: 0.12),
                    child: _bar(0.5, soft),
                  ),
                ),
              ],
            ),
            if (component.styleId != 'chips' &&
                component.size != ComponentSize.small) ...[
              const SizedBox(height: AppTokens.s2),
              _block(
                height: 40,
                color: accent.withValues(alpha: 0.18),
                child: _bar(0.6, soft),
              ),
            ],
          ],
        );
      case 'home.playlists':
        if (component.styleId == 'grid') {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: _squareBlock(accent.withValues(alpha: 0.14))),
                  const SizedBox(width: AppTokens.s2),
                  Expanded(child: _squareBlock(accent.withValues(alpha: 0.14))),
                ],
              ),
              const SizedBox(height: AppTokens.s2),
              Row(
                children: [
                  Expanded(child: _squareBlock(accent.withValues(alpha: 0.14))),
                  const SizedBox(width: AppTokens.s2),
                  Expanded(child: _squareBlock(accent.withValues(alpha: 0.14))),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: AppTokens.s2),
              SizedBox(
                width: 54,
                child: _squareBlock(accent.withValues(alpha: 0.14)),
              ),
            ],
          ],
        );
      case 'home.allSongs':
        final rows = switch (component.size) {
          ComponentSize.small => 2,
          ComponentSize.medium => 3,
          ComponentSize.large => 4,
        };
        return Column(
          children: [
            for (var i = 0; i < rows; i++) ...[
              if (i > 0) const SizedBox(height: AppTokens.s2),
              Row(
                children: [
                  _square(22, accent.withValues(alpha: 0.14)),
                  const SizedBox(width: AppTokens.s2),
                  Expanded(child: _bar(0.7, soft)),
                ],
              ),
            ],
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _block({
    required double height,
    required Color color,
    required Widget child,
  }) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s3),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: child,
    );
  }

  Widget _squareBlock(Color color) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTokens.rSm),
      ),
    );
  }

  Widget _square(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTokens.rSm),
      ),
    );
  }

  Widget _bar(double widthFactor, Color color) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: 6,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppTokens.rFull),
        ),
      ),
    );
  }
}

/// One row in the section list: drag handle, label, visibility toggle and the
/// size/style controls the definition allows.
class _ComponentEditorTile extends StatelessWidget {
  const _ComponentEditorTile({
    super.key,
    required this.index,
    required this.definition,
    required this.component,
    required this.onChanged,
  });

  final int index;
  final UiComponentDefinition definition;
  final ComponentLayout component;
  final ValueChanged<ComponentLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final surfaces = context.surfaces;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppTokens.s4,
        vertical: AppTokens.s1,
      ),
      decoration: BoxDecoration(
        color: surfaces.card,
        borderRadius: BorderRadius.circular(AppTokens.rLg),
        border: Border.all(
          color: surfaces.outlineVariant,
          width: AppTokens.borderHairline,
        ),
      ),
      padding: const EdgeInsets.all(AppTokens.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                enabled: definition.canReorder,
                child: Icon(
                  Icons.drag_indicator_rounded,
                  color: definition.canReorder
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                ),
              ),
              const SizedBox(width: AppTokens.s2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      definition.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      definition.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (definition.canHide)
                Switch(
                  value: component.visible,
                  onChanged: (value) =>
                      onChanged(component.copyWith(visible: value)),
                )
              else
                Tooltip(
                  message: 'This section cannot be hidden',
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (component.visible) ...[
            const SizedBox(height: AppTokens.s2),
            if (definition.canResize)
              _ControlRow(
                label: 'Size',
                child: SegmentedButton<ComponentSize>(
                  showSelectedIcon: false,
                  segments: [
                    for (final size in definition.allowedSizes)
                      ButtonSegment(value: size, label: Text(size.label)),
                  ],
                  selected: {component.size},
                  onSelectionChanged: (selection) =>
                      onChanged(component.copyWith(size: selection.first)),
                ),
              ),
            if (definition.allowedStyleIds.length > 1) ...[
              const SizedBox(height: AppTokens.s2),
              _ControlRow(
                label: 'Style',
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    for (final id in definition.allowedStyleIds)
                      ButtonSegment(value: id, label: Text(_styleLabel(id))),
                  ],
                  selected: {
                    component.styleId ?? definition.effectiveDefaultStyleId!,
                  },
                  onSelectionChanged: (selection) =>
                      onChanged(component.copyWith(styleId: selection.first)),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  static String _styleLabel(String id) =>
      id.isEmpty ? id : '${id[0].toUpperCase()}${id.substring(1)}';
}

class _ControlRow extends StatelessWidget {
  const _ControlRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

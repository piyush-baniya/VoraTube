import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../app/widgets/vora_snackbar.dart';
import '../../../../core/ui_customization/ui_layout.dart';
import '../providers/layout_providers.dart';
import '../widgets/freeform_layout_canvas.dart';

/// Live customization: a dedicated freeform canvas where each customizable
/// block of the target screen is directly draggable/resizable. The real screen
/// keeps its curated hierarchy; the canvas is purely additive.
///
/// Edits go into a [LayoutEditSession] (see [LayoutEditController]): nothing is
/// persisted until Done, the toolbar mirrors the session state, Cancel discards
/// with a confirmation when dirty, and presets / reset stay fully undoable.
class LiveLayoutEditor extends ConsumerStatefulWidget {
  const LiveLayoutEditor({
    super.key,
    required this.screenId,
    required this.title,
  });

  final String screenId;
  final String title;

  @override
  ConsumerState<LiveLayoutEditor> createState() => _LiveLayoutEditorState();
}

class _LiveLayoutEditorState extends ConsumerState<LiveLayoutEditor> {
  final GlobalKey<FreeformLayoutCanvasState> _canvasKey = GlobalKey();
  bool _started = false;
  bool _saving = false;
  bool _leaving = false;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(layoutProfileProvider).valueOrNull;
    if (!_started && profile != null && !_saving) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(layoutEditSessionProvider.notifier)
              .begin(widget.screenId, profile);
        }
      });
    }

    final session = ref.watch(layoutEditSessionProvider);
    final controller = ref.read(layoutEditSessionProvider.notifier);
    final dirty = controller.isDirty;

    return PopScope(
      canPop: _leaving || _saving || session == null || !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: _Toolbar(
                title: 'Customize ${widget.title}',
                canUndo: controller.canUndo,
                canRedo: controller.canRedo,
                saving: _saving,
                onClose: () => _cancel(),
                onDone: _save,
                onUndo: () => controller.undo(),
                onRedo: () => controller.redo(),
                onPresets: () => _showPresetsSheet(),
                onReset: () => controller.reset(widget.screenId),
                onHidden: () => _showHiddenSheet(),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => _canvasKey.currentState?.clearSelection(),
                child: _body(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    return FreeformLayoutCanvas(key: _canvasKey, screenId: widget.screenId);
  }

  Future<void> _save() async {
    final controller = ref.read(layoutEditSessionProvider.notifier);
    if (!controller.isEditing) {
      _leave();
      return;
    }
    setState(() => _saving = true);
    try {
      await controller.save();
      if (!mounted) return;
      VoraSnackbar.success(context, '${widget.title} layout saved.');
      _leave();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      VoraSnackbar.error(context, 'Could not save the layout.');
    }
  }

  void _cancel() {
    final controller = ref.read(layoutEditSessionProvider.notifier);
    if (!controller.isDirty) {
      controller.cancel();
      _leave();
      return;
    }
    _confirmDiscard();
  }

  Future<void> _confirmDiscard() async {
    final controller = ref.read(layoutEditSessionProvider.notifier);
    if (!controller.isDirty) {
      controller.cancel();
      _leave();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: Text('Your ${widget.title} changes have not been saved.'),
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
    if (discard == true && mounted) {
      ref.read(layoutEditSessionProvider.notifier).cancel();
      _leave();
    }
  }

  void _leave() {
    setState(() => _leaving = true);
    Navigator.of(context).pop();
  }

  void _showPresetsSheet() {
    final controller = ref.read(layoutEditSessionProvider.notifier);
    final selected =
        controller.session?.current.preset ?? LayoutPreset.standard;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preset',
                        style: Theme.of(sheetContext).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppTokens.s1),
                      Text(
                        'A curated arrangement for this screen, applied live. '
                        'Undo to revert.',
                        style: Theme.of(sheetContext).textTheme.bodySmall
                            ?.copyWith(
                              color: Theme.of(sheetContext)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                for (final preset in LayoutPreset.values)
                  ListTile(
                    leading: preset == selected
                        ? const Icon(Icons.check_circle_rounded)
                        : const Icon(Icons.circle_outlined),
                    title: Text(preset.label),
                    onTap: () {
                      controller.applyPreset(preset, widget.screenId);
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

  void _showHiddenSheet() {
    final controller = ref.read(layoutEditSessionProvider.notifier);
    final variant = layoutVariantForSize(MediaQuery.sizeOf(context));
    final layout = controller.screenLayout(widget.screenId, variant);
    final hidden = [
      for (final definition
          in ref.read(screenRegistryProvider(widget.screenId)).definitions)
        if (definition.canHide &&
            (layout?.component(definition.id)?.visible ?? true) == false)
          definition,
    ];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
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
                    'Hidden sections',
                    style: Theme.of(sheetContext).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (hidden.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTokens.s5,
                      AppTokens.s1,
                      AppTokens.s5,
                      AppTokens.s4,
                    ),
                    child: Text(
                      'All sections are visible.',
                      style: Theme.of(sheetContext).textTheme.bodyMedium
                          ?.copyWith(
                            color: Theme.of(sheetContext)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  )
                else
                  for (final definition in hidden)
                    ListTile(
                      leading: Icon(
                        Icons.add_rounded,
                        color: Theme.of(sheetContext).colorScheme.primary,
                      ),
                      title: Text(definition.label),
                      subtitle: Text(definition.description),
                      onTap: () {
                        controller.restore(
                          widget.screenId,
                          variant,
                          definition.id,
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
}

/// Compact customization toolbar. On wide screens the actions sit next to the
/// title; on narrow ones the secondary actions wrap to a second row so nothing
/// is ever crowded out.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.title,
    required this.canUndo,
    required this.canRedo,
    required this.saving,
    required this.onClose,
    required this.onDone,
    required this.onUndo,
    required this.onRedo,
    required this.onPresets,
    required this.onReset,
    required this.onHidden,
  });

  final String title;
  final bool canUndo;
  final bool canRedo;
  final bool saving;
  final VoidCallback onClose;
  final VoidCallback onDone;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onPresets;
  final VoidCallback onReset;
  final VoidCallback onHidden;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    );

    final doneButton = FilledButton(
      onPressed: saving ? null : onDone,
      child: const Text('Done'),
    );

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: AppTokens.borderHairline,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 520;
          final actions = <Widget>[
            IconButton(
              tooltip: 'Undo',
              onPressed: canUndo ? onUndo : null,
              icon: const Icon(Icons.undo_rounded),
            ),
            IconButton(
              tooltip: 'Redo',
              onPressed: canRedo ? onRedo : null,
              icon: const Icon(Icons.redo_rounded),
            ),
            IconButton(
              tooltip: 'Presets',
              onPressed: onPresets,
              icon: const Icon(Icons.auto_awesome_rounded),
            ),
            IconButton(
              tooltip: 'Reset this screen',
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt_rounded),
            ),
            IconButton(
              tooltip: 'Hidden sections',
              onPressed: onHidden,
              icon: const Icon(Icons.visibility_off_outlined),
            ),
          ];
          final close = IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          );

          if (wide) {
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.s2,
                vertical: AppTokens.s1,
              ),
              child: Row(
                children: [
                  close,
                  const SizedBox(width: AppTokens.s1),
                  Expanded(child: titleText),
                  ...actions,
                  const SizedBox(width: AppTokens.s1),
                  doneButton,
                ],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s2,
              vertical: 2,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    close,
                    const SizedBox(width: AppTokens.s1),
                    Expanded(child: titleText),
                    doneButton,
                  ],
                ),
                Row(children: [const SizedBox(width: 8), ...actions]),
              ],
            ),
          );
        },
      ),
    );
  }
}

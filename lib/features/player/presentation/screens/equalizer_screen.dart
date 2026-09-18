import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../app/widgets/vora_snackbar.dart';
import '../../../../core/audio/audio_effects.dart';
import '../../../../core/ui_customization/ui_component_registry.dart';
import '../../../../core/ui_customization/ui_layout.dart';
import '../../../../shared/widgets/artwork_view.dart';
import '../../../customization/presentation/providers/layout_providers.dart';
import '../../../customization/presentation/widgets/editable_layout_frame.dart';
import '../../../customization/presentation/widgets/layout_edit_scope.dart';
import '../../../settings/data/settings_models.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../data/equalizer_settings.dart';
import '../providers/equalizer_providers.dart';
import '../providers/player_providers.dart';
import '../widgets/equalizer_curve.dart';
import '../widgets/player_palette_surface.dart';
import '../widgets/speed_sheet.dart';
import '../widgets/volume_booster_sheet.dart';

/// Opens the flagship Equalizer screen.
Future<void> showEqualizer(BuildContext context) {
  return Navigator.of(context)
      .push<void>(MaterialPageRoute(builder: (_) => const EqualizerScreen()));
}

/// The Equalizer: an artwork-aware, interactive 10-band curve with a calm
/// Simple mode and a detailed Advanced mode.
///
/// Everything here drives the one real curve the engine already applies through
/// the existing audio-settings bridge — presets, quick macros and band drags all
/// resolve to the same 10 gain values, so the UI can never disagree with the
/// sound.
class EqualizerScreen extends ConsumerWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variant = layoutVariantForSize(MediaQuery.sizeOf(context));
    final layout = ref.watch(equalizerScreenLayoutProvider(variant));

    return PlayerPaletteSurface(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: _EqualizerBody(variant: variant, layout: layout),
        ),
      ),
    );
  }
}

class _EqualizerBody extends ConsumerStatefulWidget {
  const _EqualizerBody({required this.variant, required this.layout});

  final LayoutVariant variant;
  final ScreenLayout layout;

  @override
  ConsumerState<_EqualizerBody> createState() => _EqualizerBodyState();
}

class _EqualizerBodyState extends ConsumerState<_EqualizerBody> {
  /// Live curve while the user is dragging; committed to the provider once the
  /// gesture ends so a drag does not write storage on every frame.
  List<double>? _draftLevels;
  double? _draftPreamp;

  bool _visible(String id) => widget.layout.component(id)?.visible ?? true;

  ComponentSize _sizeOf(String id) =>
      widget.layout.component(id)?.size ?? ComponentSize.medium;

  /// Wraps a block in its editor frame (a no-op pass-through outside a
  /// customization session).
  Widget _frame(
    BuildContext context,
    String componentId, {
    required Widget child,
  }) {
    final definition = equalizerComponentRegistry.definitionFor(componentId);
    if (definition == null) return child;
    final index = widget.layout.components.indexWhere(
      (c) => c.id == componentId,
    );
    if (index < 0) return child;
    return EditableLayoutFrame(
      componentId: componentId,
      index: index,
      itemCount: widget.layout.components.length,
      definition: definition,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final audio = ref.watch(audioSettingsProvider);
    final ui = ref.watch(equalizerSettingsProvider);
    final song = ref.watch(currentTrackProvider);

    final baseLevels = effectiveEqLevels(
      preset: audio.eqPreset,
      customLevels: audio.eqCustomLevels,
    );
    final levels = _draftLevels ?? baseLevels;
    final preamp = _draftPreamp ?? audio.preampDb;

    final wide = widget.variant != LayoutVariant.portrait;
    final editing = LayoutEditScope.isEditing(context);
    final curve = _curveBlock(context, audio.eqEnabled, levels);
    final controls = _controlsBlock(
      context,
      audio: audio,
      ui: ui,
      levels: levels,
      preamp: preamp,
    );

    return Column(
      children: [
        IgnorePointer(
          ignoring: editing,
          child: _topBar(context, audio.eqEnabled),
        ),
        if (_visible('equalizer.nowPlaying'))
          _frame(
            context,
            'equalizer.nowPlaying',
            child: _nowPlaying(
              context,
              song?.title,
              song?.artist,
              song?.artPath,
            ),
          ),
        IgnorePointer(
          ignoring: editing,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.s4,
              AppTokens.s1,
              AppTokens.s4,
              AppTokens.s1,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _modeBlock(context, ui.mode),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 5,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(
                              AppTokens.s4,
                              AppTokens.s2,
                              AppTokens.s2,
                              AppTokens.s6,
                            ),
                            child: _frame(
                              context,
                              'equalizer.curve',
                              child: curve,
                            ),
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          flex: 4,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(
                              AppTokens.s3,
                              AppTokens.s2,
                              AppTokens.s4,
                              AppTokens.s6,
                            ),
                            child: controls,
                          ),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppTokens.s4,
                        AppTokens.s2,
                        AppTokens.s4,
                        AppTokens.s6,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _frame(context, 'equalizer.curve', child: curve),
                          controls,
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────────

  Widget _topBar(BuildContext context, bool enabled) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s2,
        AppTokens.s2,
        AppTokens.s4,
        AppTokens.s1,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
          ),
          Expanded(
            child: Text(
              'Equalizer',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _BypassToggle(
            enabled: enabled,
            onChanged: (value) {
              ref.read(audioSettingsProvider.notifier).setEqEnabled(value);
            },
          ),
        ],
      ),
    );
  }

  // ── Now playing ──────────────────────────────────────────────────────

  Widget _nowPlaying(
    BuildContext context,
    String? title,
    String? artist,
    String? artPath,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s5,
        AppTokens.s1,
        AppTokens.s5,
        AppTokens.s2,
      ),
      child: Row(
        children: [
          ArtworkView(path: artPath, size: 48, radius: AppTokens.rMd),
          const SizedBox(width: AppTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title ?? 'Nothing playing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  artist ?? 'Play a track to shape its sound',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Curve ────────────────────────────────────────────────────────────

  Widget _curveBlock(BuildContext context, bool enabled, List<double> levels) {
    final height = _sizeOf('equalizer.curve') == ComponentSize.large
        ? 280.0
        : 220.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EqualizerCurve(
            levels: levels,
            enabled: enabled,
            height: height,
            interactive: true,
            onChanged: (index, value) => _onBandChanged(levels, index, value),
            onChangedEnd: _commitDraft,
          ),
          const SizedBox(height: AppTokens.s1),
          Text(
            enabled
                ? 'Drag any node to shape the curve.'
                : 'Bypassed — your curve is kept but not applied.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ── Controls ─────────────────────────────────────────────────────────

  Widget _controlsBlock(
    BuildContext context, {
    required AudioSettings audio,
    required EqualizerUiSettings ui,
    required List<double> levels,
    required double preamp,
  }) {
    final blocks = <Widget>[];
    if (_visible('equalizer.presets')) {
      blocks.add(
        _frame(
          context,
          'equalizer.presets',
          child: _presetsBlock(context, audio, ui, levels),
        ),
      );
    }
    if (ui.mode == EqMode.simple && _visible('equalizer.quickControls')) {
      blocks.add(
        _frame(
          context,
          'equalizer.quickControls',
          child: _quickControlsBlock(context, levels),
        ),
      );
    }
    if (ui.mode == EqMode.advanced && _visible('equalizer.bandControls')) {
      blocks.add(
        _frame(
          context,
          'equalizer.bandControls',
          child: _bandControlsBlock(context, levels),
        ),
      );
    }
    if (_visible('equalizer.preamp')) {
      blocks.add(
        _frame(
          context,
          'equalizer.preamp',
          child: _preampBlock(context, audio, levels, preamp),
        ),
      );
    }
    if (_visible('equalizer.processing')) {
      blocks.add(
        _frame(
          context,
          'equalizer.processing',
          child: _processingBlock(context),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final block in blocks) ...[
          block,
          const SizedBox(height: AppTokens.s3),
        ],
      ],
    );
  }

  // ── Presets ──────────────────────────────────────────────────────────

  Widget _presetsBlock(
    BuildContext context,
    AudioSettings audio,
    EqualizerUiSettings ui,
    List<double> levels,
  ) {
    final builtIns = EqPreset.values
        .where((preset) => preset != EqPreset.custom)
        .toList();
    final saved = ui.presets;

    return _Section(
      title: 'Presets',
      action: TextButton.icon(
        onPressed: () => _resetToFlat(),
        icon: const Icon(Icons.restart_alt_rounded, size: 18),
        label: const Text('Reset'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppTokens.s2,
            runSpacing: AppTokens.s2,
            children: [
              for (final preset in builtIns)
                ChoiceChip(
                  label: Text(preset.label),
                  selected:
                      audio.eqPreset == preset && ui.selectedPresetId == null,
                  onSelected: (_) => _selectBuiltIn(preset),
                ),
            ],
          ),
          if (saved.isNotEmpty) ...[
            const SizedBox(height: AppTokens.s3),
            Text(
              'Your curves',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppTokens.s1),
            Wrap(
              spacing: AppTokens.s2,
              runSpacing: AppTokens.s2,
              children: [
                for (final preset in saved)
                  InputChip(
                    avatar: preset.pinned
                        ? const Icon(Icons.push_pin_rounded, size: 16)
                        : null,
                    label: Text(preset.name),
                    selected:
                        ui.selectedPresetId == preset.id &&
                        audio.eqPreset == EqPreset.custom,
                    onPressed: () => _selectSaved(preset),
                    onDeleted: () => _confirmDeletePreset(preset),
                    deleteIcon: const Icon(Icons.close_rounded, size: 16),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppTokens.s2),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _saveCurrentCurve(levels),
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('Save curve'),
                ),
              ),
              if (saved.isNotEmpty) ...[
                const SizedBox(width: AppTokens.s2),
                IconButton(
                  onPressed: () => _showManagePresets(),
                  icon: const Icon(Icons.reorder_rounded),
                  tooltip: 'Manage curves',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Quick controls ───────────────────────────────────────────────────

  Widget _quickControlsBlock(BuildContext context, List<double> levels) {
    return _Section(
      title: 'Quick controls',
      child: Column(
        children: [
          for (final control in EqQuickControl.values) ...[
            _QuickControlRow(
              control: control,
              value: eqQuickControlValue(levels, control),
              onChanged: (value) {
                _beginEdit();
                _updateDraft(
                  applyEqQuickControl(_draftLevels!, control, value),
                );
              },
              onChangeEnd: _commitDraft,
            ),
            if (control != EqQuickControl.values.last)
              const SizedBox(height: AppTokens.s1),
          ],
        ],
      ),
    );
  }

  // ── Band controls (Advanced) ─────────────────────────────────────────

  Widget _bandControlsBlock(BuildContext context, List<double> levels) {
    return _Section(
      title: 'Bands',
      child: Column(
        children: [
          for (var index = 0; index < eqVirtualBandCount; index++)
            _BandRow(
              index: index,
              value: levels[index],
              onChanged: (value) {
                _beginEdit();
                final draft = List<double>.of(_draftLevels!);
                draft[index] = value;
                _updateDraft(draft);
              },
              onChangeEnd: _commitDraft,
            ),
        ],
      ),
    );
  }

  // ── Preamp + clipping ────────────────────────────────────────────────

  Widget _preampBlock(
    BuildContext context,
    AudioSettings audio,
    List<double> levels,
    double preamp,
  ) {
    final boost = maxEqBoostDb(levels);
    final clipped = audio.eqEnabled && (preamp + boost) > 0.05;
    final suggested = suggestedPreampDb(levels);
    final theme = Theme.of(context);

    return _Section(
      title: 'Preamp',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (clipped)
            _ClippingBanner(
              suggestedDb: suggested,
              onApply: () {
                ref.read(audioSettingsProvider.notifier).setPreampDb(suggested);
                VoraSnackbar.success(
                  context,
                  'Preamp set to ${suggested.toStringAsFixed(1)} dB.',
                );
              },
            ),
          Row(
            children: [
              Text(
                '${preamp >= 0 ? '+' : ''}${preamp.toStringAsFixed(1)} dB',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'Headroom ${(boost + preamp).toStringAsFixed(1)} dB',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: clipped
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Slider(
            min: kEqLevelMin,
            max: 0,
            divisions: 48,
            value: preamp.clamp(kEqLevelMin, 0),
            label: '${preamp.toStringAsFixed(1)} dB',
            onChanged: (value) => setState(() => _draftPreamp = value),
            onChangeEnd: (value) {
              ref.read(audioSettingsProvider.notifier).setPreampDb(value);
              setState(() => _draftPreamp = null);
            },
          ),
          Text(
            'Preamp lowers the whole output so boosted bands do not clip.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ── Processing shortcuts ─────────────────────────────────────────────

  Widget _processingBlock(BuildContext context) {
    return _Section(
      title: 'Processing',
      child: Column(
        children: [
          _ShortcutTile(
            icon: Icons.graphic_eq_rounded,
            title: 'ReplayGain',
            subtitle: 'Normalize loudness between tracks',
            onTap: () => _showReplayGain(context),
          ),
          _ShortcutTile(
            icon: Icons.speed_rounded,
            title: 'Playback speed',
            subtitle: 'Adjust speed without changing pitch',
            onTap: () => showSpeedSheet(context),
          ),
          _ShortcutTile(
            icon: Icons.volume_up_rounded,
            title: 'Volume booster',
            subtitle: 'Lift quiet audio past 100%',
            onTap: () => showVolumeBoosterSheet(context),
          ),
        ],
      ),
    );
  }

  // ── Mode switch ──────────────────────────────────────────────────────

  Widget _modeBlock(BuildContext context, EqMode mode) {
    return SegmentedButton<EqMode>(
      segments: const [
        ButtonSegment(
          value: EqMode.simple,
          label: Text('Simple'),
          icon: Icon(Icons.auto_awesome_rounded, size: 18),
        ),
        ButtonSegment(
          value: EqMode.advanced,
          label: Text('Advanced'),
          icon: Icon(Icons.tune_rounded, size: 18),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (selection) {
        ref.read(equalizerSettingsProvider.notifier).setMode(selection.first);
      },
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────

  void _beginEdit() {
    if (_draftLevels != null) return;
    final audio = ref.read(audioSettingsProvider);
    final seeded = List<double>.of(
      effectiveEqLevels(
        preset: audio.eqPreset,
        customLevels: audio.eqCustomLevels,
      ),
    );
    _draftLevels = seeded;
    ref.read(audioSettingsProvider.notifier).setEqPreset(EqPreset.custom);
    ref.read(equalizerSettingsProvider.notifier).clearSelectedPreset();
  }

  void _updateDraft(List<double> levels) {
    setState(() => _draftLevels = normalizeEqLevels(levels));
  }

  void _commitDraft() {
    final draft = _draftLevels;
    if (draft == null) return;
    ref.read(audioSettingsProvider.notifier).setEqCustomLevels(draft);
    setState(() => _draftLevels = null);
  }

  void _onBandChanged(List<double> levels, int index, double value) {
    _beginEdit();
    final draft = List<double>.of(_draftLevels!);
    draft[index] = value;
    _updateDraft(draft);
  }

  void _selectBuiltIn(EqPreset preset) {
    ref.read(equalizerSettingsProvider.notifier).clearSelectedPreset();
    ref.read(audioSettingsProvider.notifier).setEqPreset(preset);
  }

  void _selectSaved(EqCustomPreset preset) {
    ref.read(equalizerSettingsProvider.notifier).selectPreset(preset.id);
    ref.read(audioSettingsProvider.notifier).setEqPreset(EqPreset.custom);
    ref.read(audioSettingsProvider.notifier).setEqCustomLevels(preset.levels);
  }

  void _resetToFlat() {
    ref.read(equalizerSettingsProvider.notifier).clearSelectedPreset();
    ref.read(audioSettingsProvider.notifier).setEqPreset(EqPreset.flat);
    ref
        .read(audioSettingsProvider.notifier)
        .setEqCustomLevels(List<double>.filled(eqVirtualBandCount, 0.0));
    VoraSnackbar.success(context, 'Equalizer reset to flat.');
  }

  Future<void> _saveCurrentCurve(List<double> levels) async {
    final name = await _promptName(context, title: 'Save curve');
    if (name == null || !mounted) return;
    final saved = ref
        .read(equalizerSettingsProvider.notifier)
        .savePreset(name, levels);
    if (saved == null) return;
    _selectSaved(saved);
    if (mounted) {
      VoraSnackbar.success(context, 'Saved “${saved.name}”.');
    }
  }

  Future<void> _confirmDeletePreset(EqCustomPreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${preset.name}”?'),
        content: const Text('This curve will be removed from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(equalizerSettingsProvider.notifier).deletePreset(preset.id);
  }

  Future<void> _showManagePresets() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ManagePresetsSheet(),
    );
  }

  Future<void> _showReplayGain(BuildContext context) async {
    final audio = ref.read(audioSettingsProvider);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('ReplayGain'),
          children: [
            for (final mode in ReplayGainPreference.values)
              RadioListTile<ReplayGainPreference>(
                value: mode,
                groupValue: audio.replayGain,
                title: Text(switch (mode) {
                  ReplayGainPreference.off => 'Off',
                  ReplayGainPreference.track => 'Per track',
                  ReplayGainPreference.album => 'Per album',
                }),
                onChanged: (value) {
                  if (value == null) return;
                  ref.read(audioSettingsProvider.notifier).setReplayGain(value);
                  Navigator.pop(context);
                },
              ),
          ],
        );
      },
    );
  }
}

// ── Small building blocks ───────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppTokens.s4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppTokens.rXl),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: AppTokens.borderHairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: AppTokens.s2),
          child,
        ],
      ),
    );
  }
}

class _BypassToggle extends StatelessWidget {
  const _BypassToggle({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Semantics(
      button: true,
      toggled: enabled,
      label: enabled ? 'Equalizer on' : 'Equalizer bypassed',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.rFull),
        onTap: () => onChanged(!enabled),
        child: AnimatedContainer(
          duration: AppTokens.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s3,
            vertical: AppTokens.s2,
          ),
          decoration: BoxDecoration(
            color: enabled
                ? colorScheme.primary.withValues(alpha: 0.18)
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppTokens.rFull),
            border: Border.all(
              color: enabled ? colorScheme.primary : colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.power_settings_new_rounded,
                size: 16,
                color: enabled
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppTokens.s1),
              Text(
                enabled ? 'ON' : 'BYPASS',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: enabled
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickControlRow extends StatelessWidget {
  const _QuickControlRow({
    required this.control,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final EqQuickControl control;
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(control.label, style: theme.textTheme.bodyMedium),
            ),
            Text(
              '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)} dB',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        Slider(
          min: kEqLevelMin,
          max: kEqLevelMax,
          divisions: 48,
          value: value.clamp(kEqLevelMin, kEqLevelMax),
          label: '${value.toStringAsFixed(1)} dB',
          onChanged: onChanged,
          onChangeEnd: (_) => onChangeEnd(),
        ),
      ],
    );
  }
}

class _BandRow extends StatelessWidget {
  const _BandRow({
    required this.index,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final int index;
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  String get _label {
    final frequency = kEqVirtualBandFrequencies[index];
    return frequency >= 1000
        ? '${(frequency / 1000).toStringAsFixed(frequency % 1000 == 0 ? 0 : 1)} kHz'
        : '${frequency.toInt()} Hz';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(_label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Slider(
              min: kEqLevelMin,
              max: kEqLevelMax,
              divisions: 48,
              value: value.clamp(kEqLevelMin, kEqLevelMax),
              label: '${value.toStringAsFixed(1)} dB',
              onChanged: onChanged,
              onChangeEnd: (_) => onChangeEnd(),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClippingBanner extends StatelessWidget {
  const _ClippingBanner({required this.suggestedDb, required this.onApply});

  final double suggestedDb;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.s3),
      padding: const EdgeInsets.all(AppTokens.s3),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppTokens.rLg),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: colorScheme.error,
                size: 18,
              ),
              const SizedBox(width: AppTokens.s1),
              Text(
                'Potential clipping',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s1),
          Text(
            'Boosted bands can exceed the output ceiling. '
            'Suggested preamp: ${suggestedDb.toStringAsFixed(1)} dB.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: AppTokens.s2),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: onApply,
              child: Text('Apply ${suggestedDb.toStringAsFixed(1)} dB'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

// ── Custom preset management ────────────────────────────────────────────

class _ManagePresetsSheet extends ConsumerWidget {
  const _ManagePresetsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final presets = ref.watch(equalizerSettingsProvider).presets;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.s4,
          0,
          AppTokens.s4,
          AppTokens.s4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Your curves',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppTokens.s2),
            if (presets.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
                child: Text(
                  'No saved curves yet. Shape the graph and tap Save curve.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  itemCount: presets.length,
                  onReorder: (oldIndex, newIndex) => ref
                      .read(equalizerSettingsProvider.notifier)
                      .reorderPresets(oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final preset = presets[index];
                    return ListTile(
                      key: ValueKey(preset.id),
                      leading: IconButton(
                        icon: Icon(
                          preset.pinned
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                        ),
                        tooltip: preset.pinned ? 'Unpin' : 'Pin',
                        onPressed: () => ref
                            .read(equalizerSettingsProvider.notifier)
                            .togglePin(preset.id),
                      ),
                      title: Text(preset.name),
                      subtitle: Text(
                        '${maxEqBoostDb(preset.levels).toStringAsFixed(1)} dB peak',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Rename',
                            onPressed: () async {
                              final name = await _promptName(
                                context,
                                title: 'Rename curve',
                                initial: preset.name,
                              );
                              if (name == null) return;
                              await ref
                                  .read(equalizerSettingsProvider.notifier)
                                  .renamePreset(preset.id, name);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded),
                            tooltip: 'Duplicate',
                            onPressed: () => ref
                                .read(equalizerSettingsProvider.notifier)
                                .duplicatePreset(preset.id),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            tooltip: 'Delete',
                            onPressed: () => ref
                                .read(equalizerSettingsProvider.notifier)
                                .deletePreset(preset.id),
                          ),
                          const Icon(Icons.drag_handle_rounded),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Dialogs ─────────────────────────────────────────────────────────────

Future<String?> _promptName(
  BuildContext context, {
  required String title,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Curve name',
            hintText: 'e.g. Late night',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}

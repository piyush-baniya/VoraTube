import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/audio/audio_effects.dart';
import '../../../settings/presentation/providers/settings_providers.dart';

/// Opens the Equalizer bottom sheet.
///
/// The sheet edits [audioSettingsProvider] (enable switch, one-tap presets).
/// Picking the Custom preset pops up a dedicated editor with all 10 band
/// sliders. Changes are pushed to the player by the existing bridge — no track
/// reload is ever needed because the equalizer effect applies live on the
/// native audio session.
Future<void> showEqualizerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _EqualizerSheet(),
  );
}

class _EqualizerSheet extends ConsumerWidget {
  const _EqualizerSheet();

  void _openCustomEditor(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const _CustomEqDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final audio = ref.watch(audioSettingsProvider);

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTokens.rXxl),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle.
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: AppTokens.s3),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(AppTokens.rFull),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.s6,
                  AppTokens.s2,
                  AppTokens.s4,
                  AppTokens.s1,
                ),
                child: Row(
                  children: [
                    Text(
                      'Equalizer',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              // A transparent Material so the ListTile paints its ink splashes
              // on a real Material ancestor instead of the sheet's DecoratedBox
              // background hiding them (an M3 framework assertion).
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.s6,
                  ),
                  title: const Text('Enable equalizer'),
                  subtitle: Text(
                    audio.eqEnabled
                        ? 'Applied live to the audio session'
                        : 'Curve is kept but not applied',
                  ),
                  value: audio.eqEnabled,
                  onChanged: (value) {
                    ref
                        .read(audioSettingsProvider.notifier)
                        .setEqEnabled(value);
                  },
                ),
              ),
              const SizedBox(height: AppTokens.s1),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.s6,
                  AppTokens.s1,
                  AppTokens.s6,
                  0,
                ),
                child: Text(
                  'Preset',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.s1),
              // Preset chips (Flat, Rock, Pop, ...) plus Custom. Tapping a
              // preset applies it instantly; tapping Custom also pops up the
              // 10-band editor. The persisted custom curve is untouched by
              // preset picks and reappears when Custom is selected again.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.s6),
                child: Wrap(
                  spacing: AppTokens.s2,
                  runSpacing: AppTokens.s2,
                  children: [
                    for (final preset in EqPreset.values)
                      ChoiceChip(
                        label: Text(preset.label),
                        selected: audio.eqPreset == preset,
                        onSelected: (_) {
                          final notifier =
                              ref.read(audioSettingsProvider.notifier);
                          notifier.setEqPreset(preset);
                          if (preset == EqPreset.custom) {
                            _openCustomEditor(context);
                          }
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.s2),
              Expanded(
                child: audio.eqPreset == EqPreset.custom
                    ? _CustomSummary(
                        enabled: audio.eqEnabled,
                        onEdit: () => _openCustomEditor(context),
                      )
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.s6,
                            vertical: AppTokens.s3,
                          ),
                          child: Text(
                            'Pick a preset above, or\nswitch to Custom to '
                            'shape each band.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: AppTokens.s2),
            ],
          ),
        ),
      ),
    );
  }
}

/// Summary shown while the Custom preset is active: a live preview of the
/// curve plus a button to reopen the band editor.
///
/// The content is scrollable (and vertically centered when it fits) so a short
/// sheet can never overflow it — the region shrinks on small phones and the
/// summary scrolls gracefully instead of clipping.
class _CustomSummary extends ConsumerWidget {
  const _CustomSummary({required this.enabled, required this.onEdit});

  final bool enabled;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final levels = normalizeEqLevels(
      ref.watch(audioSettingsProvider.select((s) => s.eqCustomLevels)),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.s3),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.s6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CurveBars(levels: levels, enabled: enabled),
                    const SizedBox(height: AppTokens.s3),
                    Text(
                      'Custom curve',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppTokens.s1),
                    Text(
                      enabled
                          ? 'Your 10-band curve is shaping the audio.'
                          : 'Enable the equalizer to hear your custom curve.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppTokens.s3),
                    FilledButton.tonalIcon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('Edit bands'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A compact 10-bar preview of the custom curve, one bar per band whose height
/// mirrors the band's gain (boost above the line, cut below).
class _CurveBars extends StatelessWidget {
  const _CurveBars({required this.levels, required this.enabled});

  final List<double> levels;
  final bool enabled;

  double _fraction(double level) =>
      ((level - kEqLevelMin) / (kEqLevelMax - kEqLevelMin)).clamp(0.08, 1.0);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bar = enabled ? colorScheme.primary : colorScheme.outlineVariant;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < levels.length; i++) ...[
          if (i > 0) const SizedBox(width: AppTokens.s2),
          Container(
            width: 16,
            height: 72,
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: _fraction(levels[i]),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bar.withValues(alpha: enabled ? 0.85 : 0.35),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppTokens.rSm),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Popup editor with all 10 equalizer band sliders for the Custom preset.
///
/// Bands apply instantly from the sliders (debounced freshness is committed on
/// [Slider.onChangeEnd], so closing the popup never discards a drag); the draft
/// is seeded from the persisted curve, normalized to [eqVirtualBandCount].
class _CustomEqDialog extends ConsumerStatefulWidget {
  const _CustomEqDialog();

  @override
  ConsumerState<_CustomEqDialog> createState() => _CustomEqDialogState();
}

class _CustomEqDialogState extends ConsumerState<_CustomEqDialog> {
  late List<double> _draftLevels;

  @override
  void initState() {
    super.initState();
    _draftLevels = normalizeEqLevels(
      ref.read(audioSettingsProvider).eqCustomLevels,
    );
  }

  String _bandLabel(int index) {
    final frequency = kEqVirtualBandFrequencies[index];
    return frequency >= 1000
        ? '${(frequency / 1000).toStringAsFixed(0)} kHz'
        : '${frequency.toStringAsFixed(0)} Hz';
  }

  void _commit() {
    ref
        .read(audioSettingsProvider.notifier)
        .setEqCustomLevels(List<double>.of(_draftLevels));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.rXxl),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.s6,
                  AppTokens.s4,
                  AppTokens.s4,
                  0,
                ),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, color: colorScheme.primary),
                    const SizedBox(width: AppTokens.s2),
                    Expanded(
                      child: Text(
                        'Custom equalizer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.s6,
                  AppTokens.s1,
                  AppTokens.s4,
                  0,
                ),
                child: Text(
                  'Drag a band to boost or cut it.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(
                    left: AppTokens.s4,
                    right: AppTokens.s4,
                    top: AppTokens.s2,
                    bottom: AppTokens.s5,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var index = 0;
                          index < eqVirtualBandCount;
                          index++) ...[
                        if (index > 0) const SizedBox(height: AppTokens.s1),
                        _BandSlider(
                          label: _bandLabel(index),
                          value: _draftLevels[index],
                          onChanged: (value) {
                            setState(() {
                              _draftLevels[index] = value;
                            });
                          },
                          onChangeEnd: (_) => _commit(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One band slider: frequency label on the left, value on the right.
class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: AppTokens.s1),
          Expanded(
            child: Slider(
              min: kEqLevelMin,
              max: kEqLevelMax,
              divisions: 48,
              value: value,
              label: '${value.toStringAsFixed(1)} dB',
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          const SizedBox(width: AppTokens.s1),
          SizedBox(
            width: 56,
            child: Text(
              '${value.toStringAsFixed(1)} dB',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
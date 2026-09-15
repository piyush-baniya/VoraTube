import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/audio/audio_effects.dart';
import '../../../settings/presentation/providers/settings_providers.dart';

/// Opens the Equalizer bottom sheet.
///
/// The sheet edits [audioSettingsProvider] (enable switch, one-tap presets,
/// custom 10-band sliders). Changes are pushed to the player by the existing
/// bridge — no track reload is ever needed because the equalizer effect
/// applies live on the native audio session.
Future<void> showEqualizerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _EqualizerSheet(),
  );
}

class _EqualizerSheet extends ConsumerStatefulWidget {
  const _EqualizerSheet();

  @override
  ConsumerState<_EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends ConsumerState<_EqualizerSheet> {
  /// Live-dragged custom levels. Sliders read/write this directly for instant
  /// feedback; persistence is debounced so a fast sweep doesn't spam the KV
  /// store. Never rebuilt from the provider mid-drag, or the thumb would jump.
  late List<double> _draftLevels;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Persisted custom levels may be absent (empty) or shorter than the band
    // count, so normalize to exactly [eqVirtualBandCount] entries — otherwise
    // _draftLevels[index] below would throw a RangeError on first render.
    _draftLevels = normalizeEqLevels(
      ref.read(audioSettingsProvider).eqCustomLevels,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _scheduleCommitDraft() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        ref
            .read(audioSettingsProvider.notifier)
            .setEqCustomLevels(List<double>.of(_draftLevels));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
                  AppTokens.s4,
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
              SwitchListTile(
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
              const SizedBox(height: AppTokens.s2),
              // Preset chips (Flat, Rock, Pop, ...) plus Custom. Tapping a
              // preset applies it instantly; the persisted custom curve is
              // untouched and reappears the next time Custom is picked.
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
                          ref
                              .read(audioSettingsProvider.notifier)
                              .setEqPreset(preset);
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.s3),
              if (audio.eqPreset == EqPreset.custom)
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.s6,
                      vertical: AppTokens.s2,
                    ),
                    itemCount: eqVirtualBandCount,
                    itemBuilder: (context, index) {
                      final frequency = kEqVirtualBandFrequencies[index];
                      final label = frequency >= 1000
                          ? '${(frequency / 1000).toStringAsFixed(0)} kHz'
                          : '${frequency.toStringAsFixed(0)} Hz';
                      return _BandSlider(
                        label: label,
                        value: _draftLevels[index],
                        onChanged: (value) {
                          setState(() {
                            _draftLevels[index] = value;
                          });
                          _scheduleCommitDraft();
                        },
                      );
                    },
                  ),
                )
              else
                Expanded(
                  child: Center(
                    child: Text(
                      'Pick a preset above, or\nswitch to Custom to shape '
                      'each band.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
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

/// One band slider: frequency label on the left, value on the right.
class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Slider(
              min: kEqLevelMin,
              max: kEqLevelMax,
              divisions: 48,
              value: value,
              label: '${value.toStringAsFixed(1)} dB',
              onChanged: onChanged,
            ),
          ),
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
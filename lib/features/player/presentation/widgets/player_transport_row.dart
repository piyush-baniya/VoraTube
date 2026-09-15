import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/audio/audio_effects.dart';
import '../../../../core/player/player_controller.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import 'equalizer_sheet.dart';
import 'speed_sheet.dart';
import 'volume_booster_sheet.dart';

/// Compact transport row for the Full Player.
///
/// Shuffle, repeat, equalizer, speed and boost share one horizontal row of
/// icon buttons, each sized exactly like the shuffle/repeat toggles (22px icon
/// on a full touch target, tooltip for the label). Effect buttons open bottom
/// sheets that edit [audioSettingsProvider]; non-default states highlight the
/// icon (a non-1x speed, a non-flat preset, or any boost).
class PlayerTransportRow extends ConsumerWidget {
  const PlayerTransportRow({
    super.key,
    required this.snapshot,
    required this.onToggleShuffle,
    required this.onToggleRepeat,
  });

  final PlayerSnapshot snapshot;
  final VoidCallback onToggleShuffle;
  final VoidCallback onToggleRepeat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(audioSettingsProvider);
    final speedActive =
        (audio.playbackSpeed - kDefaultPlaybackSpeed).abs() > 1e-9;
    final eqActive = audio.eqEnabled || audio.eqPreset != EqPreset.flat;
    final boostActive = audio.preampDb > 0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _TransportButton(
          icon: snapshot.shuffleEnabled
              ? Icons.shuffle_on_rounded
              : Icons.shuffle_rounded,
          label: 'Shuffle',
          isActive: snapshot.shuffleEnabled,
          onTap: onToggleShuffle,
        ),
        _TransportButton(
          icon: snapshot.repeatMode == RepeatMode.one
              ? Icons.repeat_one_on_rounded
              : snapshot.repeatMode == RepeatMode.all
              ? Icons.repeat_on_rounded
              : Icons.repeat_rounded,
          label: switch (snapshot.repeatMode) {
            RepeatMode.off => 'Repeat',
            RepeatMode.all => 'Repeat all',
            RepeatMode.one => 'Repeat one',
          },
          isActive: snapshot.repeatMode != RepeatMode.off,
          onTap: onToggleRepeat,
        ),
        _TransportButton(
          icon: Icons.speed_rounded,
          label: speedActive
              ? '${audio.playbackSpeed.toStringAsFixed(2)}x'.replaceFirst(
                  '.00',
                  '',
                )
              : 'Playback speed',
          isActive: speedActive,
          onTap: () => showSpeedSheet(context),
        ),
        _TransportButton(
          icon: Icons.equalizer_rounded,
          label: 'Equalizer',
          isActive: eqActive,
          onTap: () => showEqualizerSheet(context),
        ),
        _TransportButton(
          icon: Icons.volume_up_rounded,
          label: boostActive
              ? '+${audio.preampDb.toStringAsFixed(0)} dB'
              : 'Volume boost',
          isActive: boostActive,
          onTap: () => showVolumeBoosterSheet(context),
        ),
      ],
    );
  }
}

/// One compact icon toggle matching the shuffle/repeat button style: a 22px
/// icon on a full 48px touch target with a tooltip for discoverability.
class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color =
        isActive ? colorScheme.primary : colorScheme.onSurfaceVariant;
    return Tooltip(
      message: label,
      child: SizedBox(
        width: AppTokens.touchTarget,
        height: AppTokens.touchTarget,
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, size: 22),
          color: color,
          splashRadius: 24,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
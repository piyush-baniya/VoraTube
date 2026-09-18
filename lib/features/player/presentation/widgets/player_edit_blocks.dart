import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/widgets/top_toast.dart';
import '../../../../core/player/player_controller.dart';
import '../../../../core/ui_customization/ui_layout.dart';
import '../providers/player_providers.dart';
import 'player_controls.dart';
import 'player_progress.dart';
import 'player_transport_row.dart';

/// Shared control-block surfaces used by the real Full Player AND the freeform
/// editor canvas, so the canvas preview always matches the live UI.

/// The fixed transport zone's shuffle/repeat/effects row.
class PlayerSecondaryHost extends ConsumerWidget {
  const PlayerSecondaryHost({super.key, required this.snapshot});

  final PlayerSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlayerTransportRow(
      snapshot: snapshot,
      onToggleShuffle: () {
        final enabling = !snapshot.shuffleEnabled;
        ref.read(playerProvider).setShuffle(enabling);
        showTopToast(
          context,
          icon: Icons.shuffle_rounded,
          message: enabling ? 'Shuffle on' : 'Shuffle off',
        );
      },
      onToggleRepeat: () {
        final next = switch (snapshot.repeatMode) {
          RepeatMode.off => RepeatMode.all,
          RepeatMode.all => RepeatMode.one,
          RepeatMode.one => RepeatMode.off,
        };
        ref.read(playerProvider).setRepeat(next);
        showTopToast(
          context,
          icon: next == RepeatMode.one
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
          message: switch (next) {
            RepeatMode.off => 'Repeat off',
            RepeatMode.all => 'Repeat all',
            RepeatMode.one => 'Repeat one',
          },
        );
      },
    );
  }
}

/// The progress block: watches [playbackPositionProvider] so only it rebuilds
/// on position ticks.
class PlayerProgressHost extends ConsumerWidget {
  const PlayerProgressHost({super.key, required this.progress});

  final ComponentLayout? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(playbackStateProvider);
    final size = progress?.size ?? ComponentSize.medium;
    return ref
        .watch(playbackPositionProvider)
        .when(
          data: (position) => PlayerProgress(
            snapshot: snapshot,
            position: position,
            onSeek: (pos) => ref.read(playerProvider).seek(pos),
            size: size,
          ),
          loading: () => PlayerProgress(
            snapshot: snapshot,
            position: Duration.zero,
            onSeek: (pos) => ref.read(playerProvider).seek(pos),
            size: size,
          ),
          error: (_, _) => PlayerProgress(
            snapshot: snapshot,
            position: Duration.zero,
            onSeek: (pos) => ref.read(playerProvider).seek(pos),
            size: size,
          ),
        );
  }
}

/// The primary transport row.
class PlayerControlsHost extends ConsumerWidget {
  const PlayerControlsHost({
    super.key,
    required this.snapshot,
    required this.size,
  });

  final PlayerSnapshot snapshot;
  final ComponentSize size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlayerControls(
      snapshot: snapshot,
      onToggleShuffle: () {
        final enabling = !snapshot.shuffleEnabled;
        ref.read(playerProvider).setShuffle(enabling);
        showTopToast(
          context,
          icon: Icons.shuffle_rounded,
          message: enabling ? 'Shuffle on' : 'Shuffle off',
        );
      },
      onToggleRepeat: () {
        final next = switch (snapshot.repeatMode) {
          RepeatMode.off => RepeatMode.all,
          RepeatMode.all => RepeatMode.one,
          RepeatMode.one => RepeatMode.off,
        };
        ref.read(playerProvider).setRepeat(next);
        showTopToast(
          context,
          icon: next == RepeatMode.one
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
          message: switch (next) {
            RepeatMode.off => 'Repeat off',
            RepeatMode.all => 'Repeat all',
            RepeatMode.one => 'Repeat one',
          },
        );
      },
      onTogglePlay: () => ref.read(playerProvider).togglePlay(),
      onPrevious: () => ref.read(playerProvider).previous(),
      onNext: () => ref.read(playerProvider).next(),
      onRewind10: () =>
          ref.read(playerProvider).seekBy(const Duration(seconds: -10)),
      onForward10: () =>
          ref.read(playerProvider).seekBy(const Duration(seconds: 10)),
      size: size,
    );
  }
}

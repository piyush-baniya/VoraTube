import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/widgets/top_toast.dart';
import '../../../../core/player/player_controller.dart';
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
  const PlayerProgressHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(playbackStateProvider);
    return ref
        .watch(playbackPositionProvider)
        .when(
          data: (position) => PlayerProgress(
            snapshot: snapshot,
            position: position,
            onSeek: (pos) => ref.read(playerProvider).seek(pos),
          ),
          loading: () => PlayerProgress(
            snapshot: snapshot,
            position: Duration.zero,
            onSeek: (pos) => ref.read(playerProvider).seek(pos),
          ),
          error: (_, _) => PlayerProgress(
            snapshot: snapshot,
            position: Duration.zero,
            onSeek: (pos) => ref.read(playerProvider).seek(pos),
          ),
        );
  }
}

/// The primary transport row.
class PlayerControlsHost extends ConsumerWidget {
  const PlayerControlsHost({
    super.key,
    required this.snapshot,
    this.compact = false,
  });

  final PlayerSnapshot snapshot;

  /// True on compact-height layouts (e.g. landscape phones): drops the
  /// ten-second seek buttons and shrinks the play button.
  final bool compact;

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
      compact: compact,
    );
  }
}

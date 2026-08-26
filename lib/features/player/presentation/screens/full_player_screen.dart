import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/player/player_controller.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../library/presentation/providers/library_view_providers.dart';
import '../providers/player_providers.dart';
import '../widgets/player_artwork.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_progress.dart';
import '../widgets/queue_sheet.dart';

/// Full-screen immersive music player.
///
/// Performance architecture:
/// - Watches [playbackSnapshotProvider] for coarse state (track, modes, queue info).
/// - Only [PlayerProgress] watches [playbackPositionProvider].
/// - Artwork uses [AnimatedSwitcher] to cross-fade on song changes.
/// - Favorite state resolves via [currentSongIsFavoriteProvider].
class FullPlayerScreen extends ConsumerWidget {
  const FullPlayerScreen({super.key});

  static const _heroTag = 'player_artwork_hero';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(playbackSnapshotProvider).value;

    if (snapshot == null || !snapshot.hasTrack) {
      return const _EmptyPlayer();
    }

    final current = snapshot.current!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF09090B),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: _TopBar(onQueueTap: () => QueueSheet.show(context)),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxArtSize = constraints.maxWidth * 0.82;
                  final artSize = maxArtSize.clamp(200.0, 360.0);

                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.s6,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: (constraints.maxHeight * 0.04).clamp(
                            8.0,
                            40.0,
                          ),
                        ),
                        PlayerArtwork(
                          path: current.artPath,
                          heroTag: _heroTag,
                          size: artSize,
                        ),
                        SizedBox(
                          height: (constraints.maxHeight * 0.04).clamp(
                            12.0,
                            40.0,
                          ),
                        ),
                        _SongMetadata(
                          title: current.title,
                          artist: current.artist,
                          identityKey: current.identityKey,
                        ),
                        const SizedBox(height: AppTokens.s4),
                        _PositionConsumer(),
                        const SizedBox(height: AppTokens.s2),
                        _ControlsConsumer(),
                        SizedBox(height: bottomPadding + AppTokens.s4),
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onQueueTap});

  final VoidCallback onQueueTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s1,
        vertical: AppTokens.s1,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
            color: colorScheme.onSurfaceVariant,
            tooltip: 'Close',
          ),
          const Spacer(),
          IconButton(
            onPressed: onQueueTap,
            icon: const Icon(Icons.queue_music_rounded, size: 22),
            color: colorScheme.onSurfaceVariant,
            tooltip: 'Queue',
          ),
        ],
      ),
    );
  }
}

class _SongMetadata extends StatelessWidget {
  const _SongMetadata({
    required this.title,
    required this.artist,
    required this.identityKey,
  });

  final String title;
  final String? artist;
  final String identityKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              if (artist != null) ...[
                const SizedBox(height: AppTokens.s1),
                Text(
                  artist!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppTokens.s2),
        _FavoriteButton(identityKey: identityKey),
      ],
    );
  }
}

class _FavoriteButton extends ConsumerWidget {
  const _FavoriteButton({required this.identityKey});

  final String identityKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFavorite = ref.watch(currentSongIsFavoriteProvider);

    return IconButton(
      onPressed: () {
        final rowIdAsync = ref.read(songRowIdProvider(identityKey));
        rowIdAsync.whenOrNull(
          data: (rowId) {
            if (rowId != null) {
              ref.read(favoriteIdsProvider.notifier).toggle(rowId);
            }
          },
        );
      },
      icon: Icon(
        isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        size: 24,
      ),
      color: isFavorite
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurfaceVariant,
      tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
    );
  }
}

class _PositionConsumer extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(playbackSnapshotProvider).value;
    if (snapshot == null) return const SizedBox.shrink();

    return ref
        .watch(playbackPositionProvider)
        .when(
          data: (position) {
            return PlayerProgress(
              snapshot: snapshot,
              position: position,
              onSeek: (pos) => ref.read(playerProvider).seek(pos),
            );
          },
          loading: () => PlayerProgress(
            snapshot: snapshot,
            position: Duration.zero,
            onSeek: (pos) => ref.read(playerProvider).seek(pos),
          ),
          error: (_, __) => PlayerProgress(
            snapshot: snapshot,
            position: Duration.zero,
            onSeek: (pos) => ref.read(playerProvider).seek(pos),
          ),
        );
  }
}

class _ControlsConsumer extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(playbackSnapshotProvider).value;
    if (snapshot == null) return const SizedBox.shrink();

    return PlayerControls(
      snapshot: snapshot,
      onTogglePlay: () => ref.read(playerProvider).togglePlay(),
      onPrevious: () => ref.read(playerProvider).previous(),
      onNext: () => ref.read(playerProvider).next(),
      onToggleShuffle: () =>
          ref.read(playerProvider).setShuffle(!snapshot.shuffleEnabled),
      onToggleRepeat: () {
        final next = switch (snapshot.repeatMode) {
          RepeatMode.off => RepeatMode.all,
          RepeatMode.all => RepeatMode.one,
          RepeatMode.one => RepeatMode.off,
        };
        ref.read(playerProvider).setRepeat(next);
      },
    );
  }
}

class _EmptyPlayer extends StatelessWidget {
  const _EmptyPlayer();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF09090B),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s1,
                  vertical: AppTokens.s1,
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 30,
                      ),
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.music_note_rounded,
                        size: 56,
                        color: Color(0x409C9CA6),
                      ),
                      SizedBox(height: AppTokens.s4),
                      Text(
                        'No song playing',
                        style: TextStyle(
                          color: Color(0xFF9C9CA6),
                          fontSize: 15,
                        ),
                      ),
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

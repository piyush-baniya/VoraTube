import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/player/player_controller.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../library/presentation/providers/library_view_providers.dart';
import '../../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../../../player/presentation/widgets/compact_lyrics_panel.dart';
import '../../../player/presentation/widgets/rotating_artwork.dart';
import '../providers/player_providers.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_progress.dart';
import '../widgets/queue_sheet.dart';

/// Full-screen immersive music player.
///
/// Performance architecture:
/// - Watches [playbackStateProvider] for coarse state (track, modes, queue info).
/// - Only [PlayerProgress] watches [playbackPositionProvider].
/// - Artwork uses [AnimatedSwitcher] to cross-fade on song changes.
/// - Favorite state resolves via [currentSongIsFavoriteProvider].
/// - Lyrics panel toggles via a button in the top bar.
class FullPlayerScreen extends ConsumerStatefulWidget {
  const FullPlayerScreen({super.key});

  static const _heroTag = 'player_artwork_hero';

  @override
  ConsumerState<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends ConsumerState<FullPlayerScreen> {
  bool _showLyrics = false;

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(playbackStateProvider);

    if (!snapshot.hasTrack) {
      return const _EmptyPlayer();
    }

    final current = snapshot.current!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final isDark = theme.brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: isDark
            ? AppColors.voidBlack
            : AppColors.paperLight,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            // Immersive purple-atmosphere background. No Hero here: the
            // artwork Hero tag belongs to exactly one widget per route.
            _ImmersiveBackground(isPlaying: snapshot.isPlaying),
            // Main content
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // Top bar
                  _TopBar(
                    onQueueTap: () => QueueSheet.show(context),
                    onPlaylistTap: () =>
                        _openPlaylistPicker(current.identityKey),
                    onLyricsTap: () =>
                        setState(() => _showLyrics = !_showLyrics),
                    showLyricsActive: _showLyrics,
                    isDark: isDark,
                  ),
                  // Player content
                  Expanded(
                    child: _showLyrics
                        ? _buildLyricsMode(
                            context,
                            current,
                            snapshot,
                            bottomPadding,
                          )
                        : _buildPlayerMode(
                            context,
                            current,
                            snapshot,
                            bottomPadding,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPlaylistPicker(String identityKey) async {
    final rowId = await ref.read(songRowIdProvider(identityKey).future);
    if (!mounted || rowId == null) {
      return;
    }
    final changed = await showAddToPlaylistSheet(context, rowId);
    if (changed && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Playlist updated')));
    }
  }

  Widget _buildPlayerMode(
    BuildContext context,
    SongRef current,
    PlayerSnapshot snapshot,
    double bottomPadding,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxArtSize = constraints.maxWidth * 0.75;
        final artSize = maxArtSize.clamp(220.0, AppTokens.artworkHeroMax);

        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: (constraints.maxHeight * 0.06).clamp(16.0, 60.0),
              ),
              // Rotating Artwork with Hero transition
              RotatingArtwork(
                path: current.artPath,
                heroTag: FullPlayerScreen._heroTag,
                size: artSize,
              ),
              SizedBox(
                height: (constraints.maxHeight * 0.05).clamp(16.0, 48.0),
              ),
              // Metadata
              _SongMetadata(
                title: current.title,
                artist: current.artist,
                album: current.album,
                identityKey: current.identityKey,
              ),
              const SizedBox(height: AppTokens.s5),
              // Progress
              _PositionConsumer(),
              const SizedBox(height: AppTokens.s3),
              // Controls
              _ControlsConsumer(),
              SizedBox(height: bottomPadding + AppTokens.s6),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLyricsMode(
    BuildContext context,
    SongRef current,
    PlayerSnapshot snapshot,
    double bottomPadding,
  ) {
    return Column(
      children: [
        const SizedBox(height: AppTokens.s3),
        // Compact lyrics panel
        CompactLyricsPanel(height: 240),
        const SizedBox(height: AppTokens.s3),
        _SongMetadata(
          title: current.title,
          artist: current.artist,
          album: current.album,
          identityKey: current.identityKey,
        ),
        const SizedBox(height: AppTokens.s4),
        _PositionConsumer(),
        const SizedBox(height: AppTokens.s2),
        _ControlsConsumer(),
        SizedBox(height: bottomPadding + AppTokens.s4),
      ],
    );
  }
}

/// Immersive dark atmospheric background behind the rotating artwork.
///
/// Uses a violet-tinted radial glow over a near-black base instead of a blurred
/// copy of the album art, keeping the artwork the visual hero while avoiding
/// expensive full-screen blur / decode. This widget holds no [Hero] (the
/// artwork Hero tag belongs to exactly one widget per route).
class _ImmersiveBackground extends StatelessWidget {
  const _ImmersiveBackground({required this.isPlaying});

  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // The background is intentionally a dark atmospheric canvas with a subtle
    // purple glow — NOT a blurred copy of the artwork. The artwork itself stays
    // the hero inside the rotating player, keeping the screen premium and cheap
    // to render (no expensive full-screen blur / decode per frame).
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base void gradient
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? AppColors.voidGradientDark
                  : AppColors.voidGradientLight,
            ),
          ),
        ),
        // Subtle purple atmosphere — radial glow near the top, gentle wash.
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.25),
              radius: 1.3,
              colors: [
                colorScheme.primary.withValues(alpha: isDark ? 0.14 : 0.10),
                colorScheme.primary.withValues(alpha: isDark ? 0.05 : 0.04),
                Colors.transparent,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
        // Vignette for depth
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                isDark
                    ? AppColors.voidBlack.withValues(alpha: 0.55)
                    : AppColors.paperLight.withValues(alpha: 0.55),
              ],
              stops: const [0.45, 1.0],
            ),
          ),
        ),
        // Subtle animated ring pulse when playing
        if (isPlaying && _BackgroundPulse.enabled)
          Center(
            child: _BackgroundPulse(
              size: MediaQuery.sizeOf(context).width * 1.2,
              color: colorScheme.primary,
            ),
          ),
      ],
    );
  }
}

class _BackgroundPulse extends StatefulWidget {
  const _BackgroundPulse({required this.size, required this.color});

  final double size;
  final Color color;

  /// Can be disabled in tests to prevent infinite animation.
  static bool enabled = true;

  @override
  State<_BackgroundPulse> createState() => _BackgroundPulseState();
}

/// Public function to disable background pulse for testing.
void disableBackgroundPulseForTesting() {
  _BackgroundPulse.enabled = false;
}

class _BackgroundPulseState extends State<_BackgroundPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 0.85 + (_controller.value * 0.15);
        final opacity = 0.02 + (_controller.value * 0.03);

        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: widget.color, width: 1),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onQueueTap,
    required this.onPlaylistTap,
    required this.onLyricsTap,
    required this.showLyricsActive,
    required this.isDark,
  });

  final VoidCallback onQueueTap;
  final VoidCallback onPlaylistTap;
  final VoidCallback onLyricsTap;
  final bool showLyricsActive;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s3,
        vertical: AppTokens.s2,
      ),
      child: Row(
        children: [
          // Close button with premium styling
          PressableScale(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: AppTokens.borderHairline,
                ),
              ),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 28,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Spacer(),
          // Lyrics button
          PressableScale(
            onTap: onLyricsTap,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: showLyricsActive
                    ? colorScheme.primary.withValues(alpha: 0.16)
                    : colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
                shape: BoxShape.circle,
                border: Border.all(
                  color: showLyricsActive
                      ? colorScheme.primary.withValues(alpha: 0.3)
                      : colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: AppTokens.borderHairline,
                ),
              ),
              child: Icon(
                Icons.lyrics_rounded,
                size: 22,
                color: showLyricsActive
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s2),
          // Playlist button
          PressableScale(
            onTap: onPlaylistTap,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: AppTokens.borderHairline,
                ),
              ),
              child: Icon(
                Icons.playlist_add_rounded,
                size: 22,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s2),
          // Queue button
          PressableScale(
            onTap: onQueueTap,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: AppTokens.borderHairline,
                ),
              ),
              child: Icon(
                Icons.queue_music_rounded,
                size: 22,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
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
    this.album,
    required this.identityKey,
  });

  final String title;
  final String? artist;
  final String? album;
  final String identityKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        // Title with premium typography
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.2,
          ),
        ),
        if (artist != null) ...[
          const SizedBox(height: AppTokens.s1),
          Text(
            artist!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.2,
            ),
          ),
        ],
        if (album != null) ...[
          const SizedBox(height: AppTokens.s1),
          Text(
            album!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
        const SizedBox(height: AppTokens.s4),
        // Favorite button
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
    final colorScheme = Theme.of(context).colorScheme;

    return PressableScale(
      onTap: () {
        final rowIdAsync = ref.read(songRowIdProvider(identityKey));
        rowIdAsync.whenOrNull(
          data: (rowId) {
            if (rowId != null) {
              ref.read(favoriteIdsProvider.notifier).toggle(rowId);
            }
          },
        );
      },
      child: AnimatedContainer(
        duration: AppTokens.fast,
        curve: AppTokens.press,
        padding: const EdgeInsets.all(AppTokens.s2),
        decoration: BoxDecoration(
          color: isFavorite
              ? colorScheme.primary.withValues(alpha: 0.12)
              : colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
          shape: BoxShape.circle,
          border: Border.all(
            color: isFavorite
                ? colorScheme.primary.withValues(alpha: 0.3)
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: AppTokens.borderHairline,
          ),
        ),
        child: AnimatedSwitcher(
          duration: AppTokens.fast,
          transitionBuilder: (child, animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          child: Icon(
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            key: ValueKey(isFavorite),
            size: 22,
            color: isFavorite
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class _PositionConsumer extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(playbackStateProvider);

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
    final snapshot = ref.watch(playbackStateProvider);

    return PlayerControls(
      snapshot: snapshot,
      onTogglePlay: () => ref.read(playerProvider).togglePlay(),
      onPrevious: () => ref.read(playerProvider).previous(),
      onNext: () => ref.read(playerProvider).next(),
      onRewind10: () =>
          ref.read(playerProvider).seekBy(const Duration(seconds: -10)),
      onForward10: () =>
          ref.read(playerProvider).seekBy(const Duration(seconds: 10)),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: isDark
            ? AppColors.voidBlack
            : AppColors.paperLight,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s3,
                  vertical: AppTokens.s2,
                ),
                child: Row(
                  children: [
                    PressableScale(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh.withValues(
                            alpha: 0.8,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.3,
                            ),
                            width: AppTokens.borderHairline,
                          ),
                        ),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 28,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
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
                        size: 64,
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

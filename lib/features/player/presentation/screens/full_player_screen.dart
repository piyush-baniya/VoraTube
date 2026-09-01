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
import '../providers/sleep_timer_provider.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_progress.dart';
import '../widgets/queue_sheet.dart';
import '../widgets/sleep_timer_sheet.dart';

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

class _FullPlayerScreenState extends ConsumerState<FullPlayerScreen>
    with SingleTickerProviderStateMixin {
  bool _showLyrics = false;

  /// Controls-region height: drags that start inside the playback controls
  /// (bottom strip) are treated as button taps, not dismiss attempts.
  static const double _controlsRegionHeight = 140;
  static const double _dismissThreshold = 100;
  static const double _maxDrag = 260;

  late final AnimationController _dismissAnim;
  double _dragOffset = 0;
  bool _dragActive = false;

  @override
  void initState() {
    super.initState();
    _dismissAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (_dismissAnim.value > 0) {
          setState(() {
            _dragOffset *= 1.0 - Curves.linear.transform(_dismissAnim.value);
          });
        }
      });
  }

  @override
  void dispose() {
    _dismissAnim.dispose();
    super.dispose();
  }

  bool _startsOnControls(DragStartDetails details) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return details.globalPosition.dy >= screenHeight - _controlsRegionHeight;
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _dragActive = !_startsOnControls(details);
    if (!_dragActive) {
      return;
    }
    _dismissAnim.stop();
    _dragOffset = 0;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_dragActive || _dismissAnim.isAnimating) {
      return;
    }
    _dragOffset = (_dragOffset + details.delta.dy).clamp(0.0, _maxDrag);
    setState(() {});
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (!_dragActive) {
      return;
    }
    _dragActive = false;
    final fling = details.primaryVelocity ?? 0;
    if (_dragOffset >= _dismissThreshold || fling > 1100) {
      Navigator.of(context).pop();
      return;
    }
    _dismissAnim.forward(from: 0);
  }

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
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: _onVerticalDragStart,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          child: Transform.translate(
            offset: Offset(0, _dragOffset * 0.65),
            child: Transform.scale(
              scale: 1.0 - _dragOffset / _maxDrag * 0.06,
              child: Opacity(
                opacity:
                    (1.0 - _dragOffset / _maxDrag * 0.55).clamp(0.35, 1.0),
                child: Stack(
          children: [
            // Immersive purple-atmosphere background. No Hero here: the
            // artwork Hero tag belongs to exactly one widget per route.
            const _ImmersiveBackground(),
            // Main content
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // Top bar
                  _TopBar(
                    identityKey: current.identityKey,
                    onQueueTap: () => QueueSheet.show(context),
                    onPlaylistTap: () =>
                        _openPlaylistPicker(current.identityKey),
                    onLyricsTap: () =>
                        setState(() => _showLyrics = !_showLyrics),
                    onSleepTimerTap: () => showSleepTimerSheet(context),
                    showLyricsActive: _showLyrics,
                    isDark: isDark,
                  ),
                  // Player content (middle region swaps; the playback
                  // controls below it stay in a fixed visual position).
                  Expanded(
                    child: _showLyrics
                        ? _buildLyricsMode(context, current, snapshot)
                        : _buildPlayerMode(context, current, snapshot),
                  ),
                  // Fixed playback control region — present identically in
                  // both modes so toggling lyrics never moves the controls.
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.s6,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Normal-height screens: repeat/shuffle sit above the
                        // wave (repeat left, shuffle right). Compact-height
                        // screens (landscape phones) fold them back into the
                        // control row so nothing overflows.
                        if (MediaQuery.sizeOf(context).height >= 480)
                          Consumer(builder: (context, ref, _) {
                            final snapshot = ref.watch(playbackStateProvider);
                            return PlayerModeRow(
                              snapshot: snapshot,
                              onToggleShuffle: () => ref
                                  .read(playerProvider)
                                  .setShuffle(!snapshot.shuffleEnabled),
                              onToggleRepeat: () {
                                final next = switch (snapshot.repeatMode) {
                                  RepeatMode.off => RepeatMode.all,
                                  RepeatMode.all => RepeatMode.one,
                                  RepeatMode.one => RepeatMode.off,
                                };
                                ref.read(playerProvider).setRepeat(next);
                              },
                            );
                          }),
                        _PositionConsumer(),
                        const SizedBox(height: AppTokens.s3),
                        _ControlsConsumer(
                          showModeToggles:
                              MediaQuery.sizeOf(context).height < 480,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: bottomPadding + AppTokens.s5),
                ],
              ),
            ),
          ],
        ),
              ),
            ),
          ),
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
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxArtSize = constraints.maxWidth * 0.75;
        final artSize = maxArtSize.clamp(220.0, AppTokens.artworkHeroMax);

        // Progress and controls live in the fixed bottom region of the parent
        // Column; this scrollable area only contains the artwork and metadata.
        // When it fits on screen, scrolling is disabled so the body-level
        // swipe-down dismiss can reach the artwork area; on short viewports the
        // area stays scrollable with a bouncing feel.
        final fitsOnScreen = constraints.maxHeight > 400.0;
        return SingleChildScrollView(
          physics: fitsOnScreen
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
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
              ),
              const SizedBox(height: AppTokens.s2),
              // Volume booster
              _BoostButton(),
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
  ) {
    // Lyrics may grow/scroll freely here; the playback controls sit below in
    // the fixed region of the parent Column and are never pushed around.
    //
    // Landscape safety: the panel must FILL the space the Expanded region
    // actually provides instead of rendering at a fixed 280 dp. Centering a
    // fixed-height panel inside a shorter landscape region clips the lyrics
    // (silently — RenderPositionedBox paints out of bounds without throwing).
    // CompactLyricsPanel already adapts its layout to the real constraints
    // (viewportHeight = constraints.maxHeight), so filling is correct on both
    // orientations.
    //
    // Very short landscape viewports (e.g. 320 dp tall phones) cannot fit the
    // fixed spacers plus the full three-line metadata block below the panel —
    // the non-flexible siblings alone overflow the Column. In that compact
    // case shrink to the title only and tighten the spacers so everything
    // stays on-screen; on normal heights the full metadata is shown.
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 200;
        return Column(
          children: [
            if (!compact) const SizedBox(height: AppTokens.s3),
            // Compact lyrics panel — fills whatever height the region has.
            // Flexible (not Expanded) keeps constraints loose so the panel can
            // shrink to its collapsed preview height instead of staying at
            // full height when the user taps the collapse control.
            const Flexible(child: CompactLyricsPanel(height: 280)),
            SizedBox(height: compact ? AppTokens.s1 : AppTokens.s4),
            _SongMetadata(
              title: current.title,
              artist: compact ? null : current.artist,
              album: compact ? null : current.album,
            ),
            if (!compact) const SizedBox(height: AppTokens.s4),
          ],
        );
      },
    );
  }
}

/// Immersive dark atmospheric background behind the rotating artwork.
///
/// Uses a violet-tinted radial glow over a near-black base instead of a blurred
/// copy of the album art, keeping the artwork the visual hero while avoiding
/// expensive full-screen blur / decode. This widget holds no [Hero] (the
/// artwork Hero tag belongs to exactly one widget per route).
///
/// Stateful so the subtle ring-pulse animation controller is created once and
/// survives play/pause toggles. A stateless implementation would add/remove the
/// pulse widget from the tree on every toggle, disposing and recreating its
/// controller each time — which caused a visible flicker on each play/pause.
class _ImmersiveBackground extends ConsumerStatefulWidget {
  const _ImmersiveBackground();

  @override
  ConsumerState<_ImmersiveBackground> createState() =>
      _ImmersiveBackgroundState();
}

class _ImmersiveBackgroundState extends ConsumerState<_ImmersiveBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  bool _wasPlaying = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _syncPulse(bool isPlaying) {
    if (!_BackgroundPulse.enabled) return;
    if (isPlaying && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!isPlaying && _pulseController.isAnimating) {
      _pulseController.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen only to isPlaying so the background rebuilds minimally and the
    // pulse animation is toggled without rebuilding the whole stack.
    final isPlaying = ref.watch(playbackIsPlayingProvider);
    if (isPlaying != _wasPlaying) {
      _wasPlaying = isPlaying;
      // Schedule the sync for after the frame so we don't setState during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncPulse(isPlaying);
      });
    }

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
        // Subtle animated ring pulse when playing — kept in the tree always and
        // only started/stopped, so play/pause never recreates the controller.
        if (_BackgroundPulse.enabled)
          Center(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final scale = 0.85 + (_pulseController.value * 0.15);
                final opacity = 0.02 + (_pulseController.value * 0.03);

                return Visibility(
                  visible: isPlaying,
                  maintainAnimation: true,
                  maintainState: true,
                  maintainSize: true,
                  child: Transform.scale(
                    scale: scale,
                    child: Opacity(
                      opacity: opacity,
                      child: Container(
                        width: MediaQuery.sizeOf(context).width * 1.2,
                        height: MediaQuery.sizeOf(context).width * 1.2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorScheme.primary,
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
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

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.identityKey,
    required this.onQueueTap,
    required this.onPlaylistTap,
    required this.onLyricsTap,
    required this.onSleepTimerTap,
    required this.showLyricsActive,
    required this.isDark,
  });

  final String identityKey;
  final VoidCallback onQueueTap;
  final VoidCallback onPlaylistTap;
  final VoidCallback onLyricsTap;
  final VoidCallback onSleepTimerTap;
  final bool showLyricsActive;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final timerActive = ref.watch(sleepTimerIsActiveProvider);
    final timerRemaining = ref.watch(sleepTimerRemainingProvider);

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
              width: 48,
              height: 48,
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
          // Favorite button (kept beside Lyrics per design)
          _FavoriteButton(identityKey: identityKey),
          const SizedBox(width: AppTokens.s2),
          // Sleep Timer button — a compact pill that reveals the live
          // countdown while a timer is running.
          PressableScale(
            onTap: onSleepTimerTap,
            child: Container(
              height: 48,
              padding: EdgeInsets.symmetric(
                horizontal: timerActive ? AppTokens.s4 : 0,
              ),
              decoration: BoxDecoration(
                color: timerActive
                    ? colorScheme.primary.withValues(alpha: 0.16)
                    : colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
                shape: timerActive ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: timerActive
                    ? const BorderRadius.all(Radius.circular(AppTokens.rFull))
                    : null,
                border: Border.all(
                  color: timerActive
                      ? colorScheme.primary.withValues(alpha: 0.3)
                      : colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: AppTokens.borderHairline,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // When inactive the pill is a plain 48px circular button
                  // centred on the icon; when active it becomes a pill showing
                  // the icon and the live countdown side by side with explicit
                  // spacing so neither ever overlaps the other.
                  SizedBox(
                    width: timerActive ? null : 48,
                    child: timerActive
                        ? Icon(
                            Icons.bedtime_rounded,
                            size: 22,
                            color: colorScheme.primary,
                          )
                        : Center(
                            child: Icon(
                              Icons.bedtime_rounded,
                              size: 22,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                  if (timerActive) ...[
                    const SizedBox(width: AppTokens.s2),
                    Text(
                      formatSleepTimer(timerRemaining),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: AppTokens.s1),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s2),
          // Lyrics button
          PressableScale(
            onTap: onLyricsTap,
            child: Container(
              width: 48,
              height: 48,
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
              width: 48,
              height: 48,
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
              width: 48,
              height: 48,
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
  const _SongMetadata({required this.title, required this.artist, this.album});

  final String title;
  final String? artist;
  final String? album;

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

/// Compact booster button docked between the song metadata and the progress
/// bar. Tapping opens the [VolumeBoostSheet]. Shows the live percentage so the
/// user always sees the current boost without opening the sheet.
class _BoostButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boost = ref.watch(volumeBoostProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final percent = ((boost - 1.0) * 100).round();
    final boosted = percent > 0;

    return Center(
      child: PressableScale(
        onTap: () => VolumeBoostSheet.show(context),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s3,
            vertical: AppTokens.s1,
          ),
          decoration: BoxDecoration(
            color: boosted
                ? colorScheme.primary.withValues(alpha: 0.10)
                : colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppTokens.rFull),
            border: Border.all(
              color: boosted
                  ? colorScheme.primary.withValues(alpha: 0.25)
                  : colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: AppTokens.borderHairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.hearing_rounded,
                size: 16,
                color: boosted
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              const SizedBox(width: AppTokens.s1),
              Text(
                'Volume boost: ${boost == 1.0 ? 'off' : '$percent%'}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: boosted
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Clean modal sheet hosting the 100%–200% volume-boost slider.
class VolumeBoostSheet extends ConsumerStatefulWidget {
  const VolumeBoostSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const VolumeBoostSheet(),
    );
  }

  @override
  ConsumerState<VolumeBoostSheet> createState() => _VolumeBoostSheetState();
}

class _VolumeBoostSheetState extends ConsumerState<VolumeBoostSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final boost = ref.watch(volumeBoostProvider);
    final percent = ((boost - 1.0) * 100).round();

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.rXl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.s6,
            AppTokens.s4,
            AppTokens.s6,
            AppTokens.s6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.s5),
              Row(
                children: [
                  Icon(Icons.hearing_rounded, color: colorScheme.primary),
                  const SizedBox(width: AppTokens.s3),
                  Text(
                    'Volume boost',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$percent%',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.s3),
              Text(
                'Boost playback volume up to 200%. Higher levels may clip or '
                'distort on some tracks.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTokens.s5),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: colorScheme.primary,
                  inactiveTrackColor: colorScheme.primary.withValues(
                    alpha: 0.15,
                  ),
                  thumbColor: colorScheme.primary,
                  overlayColor: colorScheme.primary.withValues(alpha: 0.12),
                  trackHeight: 4,
                  valueIndicatorColor: colorScheme.primary,
                  valueIndicatorTextStyle: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimary,
                  ),
                ),
                child: Slider(
                  min: 100,
                  max: 200,
                  divisions: 20,
                  value: boost * 100,
                  label: '$percent%',
                  onChanged: (value) => ref
                      .read(volumeBoostProvider.notifier)
                      .setBoost(value / 100),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _BoostPreset(
                    label: '100%',
                    onTap: () =>
                        ref.read(volumeBoostProvider.notifier).setBoost(1.0),
                  ),
                  _BoostPreset(
                    label: '150%',
                    onTap: () =>
                        ref.read(volumeBoostProvider.notifier).setBoost(1.5),
                  ),
                  _BoostPreset(
                    label: '200%',
                    onTap: () =>
                        ref.read(volumeBoostProvider.notifier).setBoost(2.0),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoostPreset extends StatelessWidget {
  const _BoostPreset({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s2,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(AppTokens.rMd),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: AppTokens.borderHairline,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ControlsConsumer extends ConsumerWidget {
  const _ControlsConsumer({this.showModeToggles = false});

  final bool showModeToggles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(playbackStateProvider);

    return PlayerControls(
      snapshot: snapshot,
      showModeToggles: showModeToggles,
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
      onTogglePlay: () => ref.read(playerProvider).togglePlay(),
      onPrevious: () => ref.read(playerProvider).previous(),
      onNext: () => ref.read(playerProvider).next(),
      onRewind10: () =>
          ref.read(playerProvider).seekBy(const Duration(seconds: -10)),
      onForward10: () =>
          ref.read(playerProvider).seekBy(const Duration(seconds: 10)),
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

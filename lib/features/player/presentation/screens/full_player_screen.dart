import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/player/player_controller.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/widgets/vora_snackbar.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../library/presentation/providers/library_view_providers.dart';
import '../../../lyrics/presentation/providers/lyrics_providers.dart';
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
  bool _lyricsExpanded = true;

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
      VoraSnackbar.success(
        context,
        'Playlist updated',
        title: 'Success',
      );
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // LANDSCAPE: dedicated full-bleed lyrics layout. The lyrics card
        // occupies the ENTIRE player content region — no artwork beside or
        // beneath it, no lyric text outside the card. The playback controls
        // below this region stay in their fixed position.
        if (constraints.maxWidth > constraints.maxHeight) {
          return CompactLyricsPanel(
            height: constraints.maxHeight,
            fillRegion: true,
            onExpandedChanged: (expanded) {
              setState(() => _lyricsExpanded = expanded);
            },
          );
        }
        // PORTRAIT: existing layout — lyrics card with the collapsible
        // artwork reveal beneath it when the card is collapsed.
        final compact = constraints.maxHeight < 200;
        // Desired card height follows the available region instead of a fixed
        // constant: most of the region in portrait, tightened on short
        // (landscape) viewports. The panel itself clamps to its incoming
        // constraints as a second line of defence, so this can never overflow
        // the flex even if the estimate is generous.
        final panelHeight = (constraints.maxHeight * 0.62).clamp(
          180.0,
          300.0,
        );
        return Column(
          children: [
            if (!compact) const SizedBox(height: AppTokens.s3),
            Flexible(
              child: CompactLyricsPanel(
                height: panelHeight,
                onExpandedChanged: (expanded) {
                  setState(() => _lyricsExpanded = expanded);
                },
              ),
            ),
            SizedBox(height: compact ? AppTokens.s1 : AppTokens.s4),
            if (!_lyricsExpanded)
              // The revealed artwork (plus, on landscape, the live lyric line)
              // lives in a scrollable so the collapsed reveal can never
              // overflow the tight region — it scrolls if the space is too
              // small for the full artwork.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // On tight (landscape) viewports a single live synced
                      // lyric line sits above the revealed artwork, so the
                      // current lyric stays visible while the card is
                      // collapsed. Falls back to nothing when there are no
                      // synced lyrics.
                      if (compact) const _CurrentLyricLine(),
                      if (compact) const SizedBox(height: AppTokens.s2),
                      // Bottom padding reserves room for the artwork's paint
                      // overflow (drop shadow + playing glow extend ~20px
                      // beyond the box) so the reveal is never clipped.
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: RotatingArtwork(
                          path: current.artPath,
                          heroTag: null,
                          size: _collapsedArtworkSize(constraints, compact),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!_lyricsExpanded) const SizedBox(height: AppTokens.s3),
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

  /// Size of the artwork revealed when the lyrics card is collapsed.
  ///
  /// Grows to fill the space the lyrics list vacated (capped at the hero-size
  /// ceiling) so the album art becomes the visual focus again, instead of a
  /// small thumb. On very short (landscape) viewports it stays small so the
  /// collapsed card, current lyric line, artwork and metadata never overflow
  /// the region.
  double _collapsedArtworkSize(BoxConstraints constraints, bool compact) {
    if (compact) {
      return 120.0;
    }
    final byHeight = constraints.maxHeight * 0.62;
    final byWidth = constraints.maxWidth * 0.62;
    final target = byWidth < byHeight ? byWidth : byHeight;
    return target.clamp(240.0, AppTokens.artworkHeroMax);
  }
}

/// A single, currently-playing synced lyric line.
///
/// Shown above the artwork when the full player's lyrics card is collapsed on a
/// tight (landscape) viewport, so the live lyric stays on screen without the
/// full list. Renders nothing when there are no synced lyrics available.
class _CurrentLyricLine extends ConsumerWidget {
  const _CurrentLyricLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final lyrics = ref.watch(activeLyricsProvider);
    if (lyrics == null || !lyrics.hasSyncedLines) {
      return const SizedBox.shrink();
    }
    final index = ref.watch(currentLyricLineIndexProvider).valueOrNull ?? -1;
    final current =
        (index >= 0 && index < lyrics.lines.length)
            ? lyrics.lines[index].text
            : null;
    final text =
        current ??
        (lyrics.lines.isNotEmpty ? lyrics.lines.first.text : null);
    if (text == null) {
      return const SizedBox.shrink();
    }
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: theme.textTheme.titleMedium?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
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

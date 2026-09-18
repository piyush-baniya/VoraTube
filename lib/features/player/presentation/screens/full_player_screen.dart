import 'dart:math' as math;

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/player/player_controller.dart';
import '../../../../core/ui_customization/ui_component_registry.dart';
import '../../../../core/ui_customization/ui_layout.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/widgets/top_toast.dart';
import '../../../../app/widgets/vora_snackbar.dart';
import '../../../../services/analytics_service.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../features/customization/presentation/providers/layout_providers.dart';
import '../../../../features/customization/presentation/widgets/editable_layout_frame.dart';
import '../../../../features/customization/presentation/widgets/layout_edit_scope.dart';
import '../../../library/presentation/providers/library_view_providers.dart';
import '../../../lyrics/presentation/providers/lyrics_providers.dart';
import '../../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../providers/player_providers.dart';
import '../providers/sleep_timer_provider.dart';
import '../widgets/compact_lyrics_panel.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_palette_surface.dart';
import '../widgets/player_progress.dart';
import '../widgets/player_quick_actions.dart';
import '../widgets/player_track_info.dart';
import '../widgets/player_transport_row.dart';
import '../widgets/queue_sheet.dart';
import '../widgets/rotating_artwork.dart';
import '../widgets/sleep_timer_sheet.dart';
import '../widgets/speed_sheet.dart';
import '../widgets/volume_booster_sheet.dart';
import 'equalizer_screen.dart';

/// Full-screen immersive music player.
///
/// The player is driven by the [playerScreenLayoutProvider] customization
/// profile: the artwork + song info form a dismissable top zone while the
/// progress bar and control rows form a fixed bottom zone. The whole surface
/// is wrapped in [PlayerPaletteSurface] so colors and the backdrop derive
/// from the current artwork's palette.
class FullPlayerScreen extends ConsumerStatefulWidget {
  const FullPlayerScreen({super.key});

  static const _heroTag = 'player_artwork_hero';

  @override
  ConsumerState<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends ConsumerState<FullPlayerScreen>
    with TickerProviderStateMixin {
  bool _showLyrics = false;
  bool _lyricsExpanded = true;

  static const double _dismissThreshold = 100;
  static const double _maxDrag = 260;

  late final AnimationController _dismissAnim;
  double _dragOffset = 0;
  bool _dragActive = false;

  /// The fixed bottom zone (progress + control rows). Swipe-down dismisses
  /// only begin above its top edge so the controls themselves act as buttons.
  final GlobalKey _bottomZoneKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _dismissAnim =
        AnimationController(
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

  bool _isInBottomZone(DragStartDetails details) {
    final box = _bottomZoneKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return false;
    }
    final top = box.localToGlobal(Offset.zero).dy;
    return details.globalPosition.dy >= top;
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _dragActive = !_isInBottomZone(details);
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
    final editing = LayoutEditScope.isEditing(context);
    final screen = MediaQuery.sizeOf(context);
    final isLandscape = screen.width > screen.height;
    final variant = layoutVariantForSize(screen);
    final layout = ref.watch(playerScreenLayoutProvider(variant));
    final artworkComp = layout.component('player.artwork');
    final immersive = artworkComp?.styleId == 'immersive';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: colorScheme.surface,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: PlayerPaletteSurface(
        intensity: immersive ? 1.0 : 0.0,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: editing ? null : _onVerticalDragStart,
            onVerticalDragUpdate: editing ? null : _onVerticalDragUpdate,
            onVerticalDragEnd: editing ? null : _onVerticalDragEnd,
            child: Transform.translate(
              offset: Offset(0, _dragOffset * 0.65),
              child: Transform.scale(
                scale: 1.0 - _dragOffset / _maxDrag * 0.06,
                child: Opacity(
                  opacity: (1.0 - _dragOffset / _maxDrag * 0.55).clamp(
                    0.35,
                    1.0,
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        IgnorePointer(
                          ignoring: editing,
                          child: _TopBar(
                            identityKey: current.identityKey,
                            onPlaylistTap: () =>
                                _openPlaylistPicker(current.identityKey),
                            onLyricsTap: () {
                              setState(() => _showLyrics = !_showLyrics);
                              if (_showLyrics) {
                                AnalyticsService.instance.lyricsOpened();
                              }
                            },
                            onSleepTimerTap: () => showSleepTimerSheet(context),
                            showLyricsActive: _showLyrics,
                          ),
                        ),
                        Expanded(
                          child: _showLyrics
                              ? _buildLyricsMode(context, current)
                              : _buildPlayerMode(
                                  context,
                                  current,
                                  snapshot,
                                  isLandscape,
                                  layout,
                                ),
                        ),
                        _buildBottomZone(context, snapshot, layout),
                        SizedBox(height: bottomPadding + AppTokens.s5),
                      ],
                    ),
                  ),
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
      VoraSnackbar.success(context, 'Playlist updated', title: 'Success');
    }
  }

  // ── Player mode ──────────────────────────────────────────────────────────

  Widget _buildPlayerMode(
    BuildContext context,
    SongRef current,
    PlayerSnapshot snapshot,
    bool isLandscape,
    ScreenLayout layout,
  ) {
    return isLandscape
        ? _buildLandscapeMode(context, current, layout)
        : _buildPortraitMode(context, current, layout);
  }

  Widget _buildPortraitMode(
    BuildContext context,
    SongRef current,
    ScreenLayout layout,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final topGap = (constraints.maxHeight * 0.05).clamp(8.0, 32.0);
        final bottomGap = (constraints.maxHeight * 0.04).clamp(8.0, 28.0);
        final art = layout.component('player.artwork');
        final artSize = art == null
            ? 140.0
            : _responsiveArtwork(
                maxW: constraints.maxWidth,
                maxH: constraints.maxHeight,
                size: art.size,
              );
        // The content never overflows: the artwork is sized to fit the region
        // so the dismiss swipe always starts on a reachable surface.
        final estimatedContent = topGap + artSize + bottomGap + 112;
        final physics = estimatedContent <= constraints.maxHeight + 1
            ? const NeverScrollableScrollPhysics()
            : const BouncingScrollPhysics();

        final blocks = <Widget>[];
        for (var i = 0; i < layout.components.length; i++) {
          final c = layout.components[i];
          if (!c.visible) continue;
          final definition = playerComponentRegistry.definitionFor(c.id);
          if (definition == null) continue;
          final Widget? child = switch (c.id) {
            'player.artwork' => RotatingArtwork(
              path: current.artPath,
              heroTag: FullPlayerScreen._heroTag,
              size: artSize,
            ),
            'player.trackInfo' => PlayerTrackInfo(
              title: current.title,
              artist: current.artist,
              album: current.album,
              size: c.size,
              compact: constraints.maxWidth < 380,
            ),
            _ => null,
          };
          if (child == null) continue;
          blocks.add(
            EditableLayoutFrame(
              componentId: c.id,
              index: i,
              itemCount: layout.components.length,
              definition: definition,
              child: child,
            ),
          );
        }

        return SingleChildScrollView(
          physics: physics,
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: topGap),
              ...blocks,
              SizedBox(height: bottomGap),
              const SizedBox(height: AppTokens.s2),
            ],
          ),
        );
      },
    );
  }

  /// Landscape two-pane layout: artwork pane on the left (another dismissable
  /// surface), song info and the fixed controls on the right.
  Widget _buildLandscapeMode(
    BuildContext context,
    SongRef current,
    ScreenLayout layout,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rightBlocks = <Widget>[];
        for (var i = 0; i < layout.components.length; i++) {
          final c = layout.components[i];
          if (!c.visible || !kPlayerTopZoneIds.contains(c.id)) continue;
          final definition = playerComponentRegistry.definitionFor(c.id);
          if (definition == null) continue;
          final Widget? child = switch (c.id) {
            'player.trackInfo' => PlayerTrackInfo(
              title: current.title,
              artist: current.artist,
              album: current.album,
              size: c.size,
            ),
            _ => null,
          };
          if (child == null) continue;
          rightBlocks.add(
            EditableLayoutFrame(
              componentId: c.id,
              index: i,
              itemCount: layout.components.length,
              definition: definition,
              child: child,
            ),
          );
        }
        return Row(
          children: [
            Expanded(
              flex: 1,
              child: Center(
                child: LayoutBuilder(
                  builder: (context, pane) {
                    final art = layout.component('player.artwork');
                    final artSize = art == null
                        ? 180.0
                        : _responsiveArtwork(
                            maxW: pane.maxWidth,
                            maxH: pane.maxHeight,
                            size: art.size,
                          );
                    final artIndex = layout.components.indexWhere(
                      (c) => c.id == 'player.artwork',
                    );
                    return EditableLayoutFrame(
                      componentId: 'player.artwork',
                      index: artIndex < 0 ? 0 : artIndex,
                      itemCount: layout.components.length,
                      definition: playerComponentRegistry.definitionFor(
                        'player.artwork',
                      )!,
                      child: RotatingArtwork(
                        path: current.artPath,
                        heroTag: FullPlayerScreen._heroTag,
                        size: artSize,
                      ),
                    );
                  },
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.s6,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...rightBlocks,
                          const SizedBox(height: AppTokens.s3),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Lyrics mode ──────────────────────────────────────────────────────────

  Widget _buildLyricsMode(BuildContext context, SongRef current) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > constraints.maxHeight) {
          return CompactLyricsPanel(
            height: constraints.maxHeight,
            fillRegion: true,
            onExpandedChanged: (expanded) {
              setState(() => _lyricsExpanded = expanded);
            },
          );
        }
        final compact = constraints.maxHeight < 200;
        final panelHeight = (constraints.maxHeight * 0.62).clamp(180.0, 300.0);
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
              Flexible(
                child: LayoutBuilder(
                  builder: (context, artConstraints) {
                    if (compact) {
                      return SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _CurrentLyricLine(),
                            const SizedBox(height: AppTokens.s2),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: RotatingArtwork(
                                path: current.artPath,
                                heroTag: null,
                                size: _collapsedArtworkSize(
                                  artConstraints,
                                  true,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.s4),
                      child: Center(
                        child: RotatingArtwork(
                          path: current.artPath,
                          heroTag: null,
                          size: _fitArtworkSize(artConstraints),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (!_lyricsExpanded) const SizedBox(height: AppTokens.s4),
            PlayerTrackInfo(
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

  double _collapsedArtworkSize(BoxConstraints constraints, bool compact) {
    if (compact) {
      return 120.0;
    }
    final byHeight = constraints.maxHeight * 0.62;
    final byWidth = constraints.maxWidth * 0.62;
    final target = byWidth < byHeight ? byWidth : byHeight;
    return target.clamp(240.0, AppTokens.artworkHeroMax);
  }

  double _fitArtworkSize(BoxConstraints c) {
    final byWidth = c.maxWidth * 0.62;
    final availableHeight = c.maxHeight - AppTokens.s6;
    final byHeight = availableHeight < 0 ? 0.0 : availableHeight;
    final target = byWidth < byHeight ? byWidth : byHeight;
    return target.clamp(120.0, AppTokens.artworkHeroMax);
  }

  // ── Fixed bottom zone ────────────────────────────────────────────────────

  Widget _buildBottomZone(
    BuildContext context,
    PlayerSnapshot snapshot,
    ScreenLayout layout,
  ) {
    // On short (landscape) viewports the transport is tightened so the fixed
    // zone never crowds the artwork pane: tighter gaps and a small play button.
    final compact = MediaQuery.sizeOf(context).height < 480;
    final progress = layout.component('player.progress');
    final primary = layout.component('player.primaryControls');
    final primarySize =
        compact &&
            (primary?.size ?? ComponentSize.medium) == ComponentSize.medium
        ? ComponentSize.small
        : primary?.size ?? ComponentSize.medium;

    final rows = <Widget>[];
    for (var i = 0; i < layout.components.length; i++) {
      final c = layout.components[i];
      if (!c.visible) continue;
      final definition = playerComponentRegistry.definitionFor(c.id);
      if (definition == null) continue;
      final Widget? child = switch (c.id) {
        'player.secondaryControls' => _SecondaryHost(snapshot: snapshot),
        'player.progress' => _ProgressHost(progress: progress),
        'player.primaryControls' => _ControlsHost(
          snapshot: snapshot,
          size: primarySize,
        ),
        _ => null,
      };
      if (child == null) continue;
      if (rows.isNotEmpty) {
        rows.add(const SizedBox(height: AppTokens.s1));
      }
      rows.add(
        EditableLayoutFrame(
          componentId: c.id,
          index: i,
          itemCount: layout.components.length,
          definition: definition,
          child: child,
        ),
      );
    }

    return Padding(
      key: _bottomZoneKey,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s6),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }

  /// Size of the artwork inside the top zone, sized to FIT the available
  /// region (never overflowing it) while honoring the component's [size].
  double _responsiveArtwork({
    required double maxW,
    required double maxH,
    required ComponentSize size,
  }) {
    final topGap = (maxH * 0.05).clamp(8.0, 32.0);
    final bottomGap = (maxH * 0.04).clamp(8.0, 28.0);
    final reserve = size == ComponentSize.small ? 92.0 : 112.0;
    final heightFit = math.max(0.0, maxH - topGap - bottomGap - reserve);
    final widthCap = math.min(maxW * 0.78, AppTokens.artworkHeroMax);
    final base = math.min(heightFit, widthCap);
    return switch (size) {
      ComponentSize.small => base.clamp(120.0, 200.0),
      ComponentSize.medium => base.clamp(140.0, AppTokens.artworkHeroMax),
      ComponentSize.large => base.clamp(180.0, AppTokens.artworkHeroMax),
    };
  }
}

/// A single, currently-playing synced lyric line shown above the artwork when
/// the lyrics card is collapsed on a tight viewport.
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
    final current = (index >= 0 && index < lyrics.lines.length)
        ? lyrics.lines[index].text
        : null;
    final text =
        current ?? (lyrics.lines.isNotEmpty ? lyrics.lines.first.text : null);
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

/// The fixed transport zone's shuffle/repeat/effects row.
class _SecondaryHost extends ConsumerWidget {
  const _SecondaryHost({required this.snapshot});

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
class _ProgressHost extends ConsumerWidget {
  const _ProgressHost({required this.progress});

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
class _ControlsHost extends ConsumerWidget {
  const _ControlsHost({required this.snapshot, required this.size});

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

/// Slim top bar: close, then a responsive set of quick actions (favorite,
/// queue, lyrics, sleep timer) and the overflow menu (effects, playlist and
/// any quick action that does not fit the current width).
///
/// Favorite and Queue always take priority: as the bar narrows the sleep timer
/// and lyrics move into the overflow menu first, and the direct actions never
/// overflow or crowd the overlay.
class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.identityKey,
    required this.onPlaylistTap,
    required this.onLyricsTap,
    required this.onSleepTimerTap,
    required this.showLyricsActive,
  });

  final String identityKey;
  final VoidCallback onPlaylistTap;
  final VoidCallback onLyricsTap;
  final VoidCallback onSleepTimerTap;
  final bool showLyricsActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final timerActive = ref.watch(sleepTimerIsActiveProvider);
    final timerRemaining = ref.watch(sleepTimerRemainingProvider);
    final showCountdown =
        timerActive && timerRemaining <= const Duration(minutes: 5);
    final timerPillHighlighted = timerActive;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s3,
        vertical: AppTokens.s2,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Reserve the back button and overflow menu (96) plus one 8px gap
          // per direct action: each direct action takes 48 (+8) = 56.
          final slots = ((constraints.maxWidth - 96) / 56).floor().clamp(0, 4);
          final showSleep = slots >= 4;
          final showLyrics = slots >= 3;
          final showQueue = slots >= 2;
          final showFavorite = slots >= 1;

          void toggleFavorite() {
            ref
                .read(songRowIdProvider(identityKey))
                .whenOrNull(
                  data: (rowId) {
                    if (rowId != null) {
                      ref.read(favoriteIdsProvider.notifier).toggle(rowId);
                    }
                  },
                );
          }

          final menuItems = <PopupMenuEntry<VoidCallback>>[
            PopupMenuItem<VoidCallback>(
              value: () => showEqualizer(context),
              child: const _MenuItem(
                icon: Icons.equalizer_rounded,
                label: 'Equalizer',
              ),
            ),
            PopupMenuItem<VoidCallback>(
              value: () => showSpeedSheet(context),
              child: const _MenuItem(
                icon: Icons.speed_rounded,
                label: 'Playback speed',
              ),
            ),
            PopupMenuItem<VoidCallback>(
              value: () => showVolumeBoosterSheet(context),
              child: const _MenuItem(
                icon: Icons.volume_up_rounded,
                label: 'Volume boost',
              ),
            ),
            PopupMenuItem<VoidCallback>(
              value: onPlaylistTap,
              child: const _MenuItem(
                icon: Icons.playlist_add_rounded,
                label: 'Add to playlist',
              ),
            ),
          ];
          final fallbacks = <PopupMenuEntry<VoidCallback>>[
            if (!showSleep)
              PopupMenuItem<VoidCallback>(
                value: onSleepTimerTap,
                child: const _MenuItem(
                  icon: Icons.bedtime_rounded,
                  label: 'Sleep timer',
                ),
              ),
            if (!showLyrics)
              PopupMenuItem<VoidCallback>(
                value: onLyricsTap,
                child: const _MenuItem(
                  icon: Icons.lyrics_rounded,
                  label: 'Lyrics',
                ),
              ),
            if (!showQueue)
              PopupMenuItem<VoidCallback>(
                value: () => QueueSheet.show(context),
                child: const _MenuItem(
                  icon: Icons.queue_music_rounded,
                  label: 'Queue',
                ),
              ),
            if (!showFavorite)
              PopupMenuItem<VoidCallback>(
                value: toggleFavorite,
                child: const _MenuItem(
                  icon: Icons.favorite_border_rounded,
                  label: 'Favorite',
                ),
              ),
          ];
          if (fallbacks.isNotEmpty) {
            menuItems.add(const PopupMenuDivider());
            menuItems.addAll(fallbacks);
          }

          return Row(
            children: [
              _TopBarButton(
                icon: Icons.keyboard_arrow_down_rounded,
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
              if (showSleep) ...[
                PressableScale(
                  onTap: onSleepTimerTap,
                  child: Container(
                    height: 48,
                    padding: EdgeInsets.symmetric(
                      horizontal: timerPillHighlighted ? AppTokens.s4 : 0,
                    ),
                    decoration: BoxDecoration(
                      color: timerPillHighlighted
                          ? colorScheme.primary.withValues(alpha: 0.16)
                          : colorScheme.surfaceContainerHigh.withValues(
                              alpha: 0.8,
                            ),
                      shape: timerPillHighlighted
                          ? BoxShape.rectangle
                          : BoxShape.circle,
                      borderRadius: timerPillHighlighted
                          ? const BorderRadius.all(
                              Radius.circular(AppTokens.rFull),
                            )
                          : null,
                      border: Border.all(
                        color: timerPillHighlighted
                            ? colorScheme.primary.withValues(alpha: 0.3)
                            : colorScheme.outlineVariant.withValues(alpha: 0.3),
                        width: AppTokens.borderHairline,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: timerPillHighlighted ? null : 48,
                          child: timerPillHighlighted
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
                        if (showCountdown) ...[
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
              ],
              if (showLyrics) ...[
                _TopBarButton(
                  icon: Icons.lyrics_rounded,
                  active: showLyricsActive,
                  onTap: onLyricsTap,
                ),
                const SizedBox(width: AppTokens.s2),
              ],
              if (showQueue) ...[
                _TopBarButton(
                  icon: Icons.queue_music_rounded,
                  onTap: () => QueueSheet.show(context),
                ),
                const SizedBox(width: AppTokens.s2),
              ],
              if (showFavorite) ...[
                PlayerFavoriteButton(identityKey: identityKey, compact: true),
                const SizedBox(width: AppTokens.s2),
              ],
              PopupMenuButton<VoidCallback>(
                tooltip: 'More',
                position: PopupMenuPosition.under,
                onSelected: (action) => action(),
                itemBuilder: (BuildContext context) => menuItems,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh.withValues(
                      alpha: 0.8,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                      width: AppTokens.borderHairline,
                    ),
                  ),
                  child: Icon(
                    Icons.more_vert_rounded,
                    size: 22,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TopBarButton extends StatelessWidget {
  const _TopBarButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: active
              ? colorScheme.primary.withValues(alpha: 0.16)
              : colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
          shape: BoxShape.circle,
          border: Border.all(
            color: active
                ? colorScheme.primary.withValues(alpha: 0.3)
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: AppTokens.borderHairline,
          ),
        ),
        child: Icon(
          icon,
          size: 22,
          color: active ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: AppTokens.s3),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
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
        systemNavigationBarColor: colorScheme.surface,
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
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.music_note_rounded,
                        size: 64,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.25,
                        ),
                      ),
                      const SizedBox(height: AppTokens.s4),
                      Text(
                        'No song playing',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
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

/// Public function to disable the background pulse animation for testing.
void disableBackgroundPulseForTesting() {
  PlayerPaletteSurface.setPulseEnabled(false);
}

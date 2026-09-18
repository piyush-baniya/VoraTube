import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/artwork_palette/artwork_contrast.dart';
import '../../../../core/artwork_palette/artwork_palette.dart';
import '../../../../core/artwork_palette/artwork_palette_factory.dart';
import '../../../../core/artwork_palette/artwork_palette_tween.dart';
import '../providers/artwork_palette_provider.dart';
import '../providers/player_providers.dart';

/// Wraps player content in the current artwork's dynamic palette.
///
/// The artwork palette is animated into place (700 ms ease-out, skipped for
/// users who disable animations) and re-derived on every theme / brightness /
/// track change by `ArtworkPaletteController`, which keeps the previously
/// shown palette during extraction so a quick skip never flashes colors.
///
/// The whole subtree sits inside a `Theme` whose [ColorScheme] is derived from
/// the animated palette, so every Material widget (text, buttons, sliders)
/// automatically reads artwork-matched colors. The backdrop behind the content
/// is painted as palette gradients — no expensive blur or backdrop filter.
class PlayerPaletteSurface extends ConsumerStatefulWidget {
  const PlayerPaletteSurface({
    super.key,
    required this.child,
    this.intensity = 0.0,
  });

  final Widget child;

  /// 0..1 strength of the artwork's accent glow bleed. 0 renders the calm
  /// surface gradient; the immersive artwork style passes 1.
  final double intensity;

  /// Can be disabled in tests to prevent the infinite ring-pulse animation.
  static bool pulseEnabled = true;

  /// Called by `disableBackgroundPulseForTesting()`.
  static void setPulseEnabled(bool enabled) => pulseEnabled = enabled;

  @override
  ConsumerState<PlayerPaletteSurface> createState() =>
      _PlayerPaletteSurfaceState();
}

class _PlayerPaletteSurfaceState extends ConsumerState<PlayerPaletteSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _wasPlaying = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _syncPulse(bool isPlaying) {
    if (!PlayerPaletteSurface.pulseEnabled) return;
    if (isPlaying && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!isPlaying && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paletteState = ref.watch(currentArtworkPaletteProvider);
    final isDark = theme.brightness == Brightness.dark;
    // Always populates after the controller's first synchronous update; the
    // theme fallback is a safety net for the first frame only.
    final palette =
        paletteState.palette ??
        ArtworkPaletteTheme.buildThemeFallback(context.palette, isDark: isDark);

    // Listen only to isPlaying so the background rebuilds minimally and the
    // ring pulse is toggled without rebuilding the whole stack.
    final isPlaying = ref.watch(playbackIsPlayingProvider);
    if (isPlaying != _wasPlaying) {
      _wasPlaying = isPlaying;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncPulse(isPlaying);
      });
    }

    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 700);

    return TweenAnimationBuilder<ArtworkPalette>(
      tween: ArtworkPaletteTween(end: palette),
      duration: duration,
      curve: Curves.easeOutCubic,
      child: widget.child,
      builder: (context, animated, child) {
        final derived = _schemeFor(theme, animated);
        final textTheme = theme.textTheme.apply(
          bodyColor: animated.onSurface,
          displayColor: animated.onSurface,
        );
        return Theme(
          data: theme.copyWith(colorScheme: derived, textTheme: textTheme),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _PaletteBackdrop(
                palette: animated,
                intensity: widget.intensity,
                pulse: _pulse,
                pulseEnabled: PlayerPaletteSurface.pulseEnabled,
                isPlaying: isPlaying,
              ),
              child!,
            ],
          ),
        );
      },
    );
  }

  ColorScheme _schemeFor(ThemeData base, ArtworkPalette p) {
    final s = base.colorScheme;
    final onVariant = Color.alphaBlend(
      p.onSurface.withValues(alpha: 0.64),
      p.surface,
    );
    final outline = Color.alphaBlend(
      p.onSurface.withValues(alpha: 0.22),
      p.surface,
    );
    return s.copyWith(
      primary: p.accent,
      onPrimary: p.onAccent,
      secondary: p.secondaryAccent,
      onSecondary: ArtworkContrast.foregroundFor(p.secondaryAccent),
      surface: p.surface,
      onSurface: p.onSurface,
      onSurfaceVariant: onVariant,
      surfaceContainerLowest: p.surface,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surfaceVariant,
      surfaceContainerHigh: p.surfaceVariant,
      surfaceContainerHighest: p.surfaceVariant,
      outline: outline,
      outlineVariant: outline,
    );
  }
}

/// The static layers behind the player content: base gradient, accent glow,
/// bottom vignette and the playing ring pulse.
class _PaletteBackdrop extends StatelessWidget {
  const _PaletteBackdrop({
    required this.palette,
    required this.intensity,
    required this.pulse,
    required this.pulseEnabled,
    required this.isPlaying,
  });

  final ArtworkPalette palette;
  final double intensity;
  final AnimationController pulse;
  final bool pulseEnabled;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final glow = (0.12 + intensity * 0.12).clamp(0.0, 0.3);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base gradient from the artwork's background.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                palette.backgroundStart,
                palette.surface,
                palette.backgroundEnd,
              ],
            ),
          ),
        ),
        // Accent glow — radial wash near the top, scaled by artwork style.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.25),
              radius: 1.3,
              colors: [
                palette.accent.withValues(alpha: glow),
                palette.secondaryAccent.withValues(alpha: glow * 0.45),
                Colors.transparent,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
        // Vignette for depth.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                palette.surface.withValues(alpha: 0.55),
              ],
              stops: const [0.45, 1.0],
            ),
          ),
        ),
        // Ring pulse while playing.
        if (pulseEnabled)
          Center(
            child: AnimatedBuilder(
              animation: pulse,
              builder: (context, child) {
                final scale = 0.85 + (pulse.value * 0.15);
                final opacity = 0.02 + (pulse.value * 0.03);
                final side = MediaQuery.sizeOf(context).width * 1.2;
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
                        width: side,
                        height: side,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.accent, width: 1),
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

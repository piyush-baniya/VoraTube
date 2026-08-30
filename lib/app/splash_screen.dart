import 'dart:async';

import 'package:flutter/material.dart';

import 'theme/app_colors.dart';
import 'theme/app_tokens.dart';

/// Premium launch splash.
///
/// Shows the VoraTube logo as the hero on a near-black backdrop with a subtle
/// purple atmospheric glow, then crossfades into [child]. Deliberately kept
/// short (~800ms) so it feels premium without delaying launch.
///
/// This widget is meant to wrap the root application (see `main.dart`). It is
/// intentionally separate from [app.dart]'s [VoraTubeApp] so widget tests that
/// pump the app directly are unaffected.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child, this.duration});

  final Widget child;

  /// How long the splash stays on screen. Defaults to 950ms — the full
  /// choreography (~800ms) plus a short hold of the final branded frame
  /// before the crossfade into the app begins.
  final Duration? duration;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _showSplash = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration ?? const Duration(milliseconds: 950), () {
      if (mounted) {
        setState(() => _showSplash = false);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppTokens.slow,
      switchInCurve: AppTokens.easeOut,
      switchOutCurve: AppTokens.easeIn,
      child: _showSplash ? const _SplashScreen() : widget.child,
    );
  }
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  /// Total choreography length (~800ms): logo entrance → settle → branding.
  static const _animationDuration = Duration(milliseconds: 800);

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<double> _glow;

  /// Branding ("VoraTube") fades in slightly after the logo settles, so the
  /// entrance reads as logo-first → wordmark, not one flat crossfade.
  late final Animation<double> _brandFade;
  late final Animation<Offset> _brandSlide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _animationDuration);
    // Logo entrance: from fully transparent and slightly smaller (0.85) up to
    // full opacity + natural size, using a premium exponential ease for a
    // weighty settle rather than a flat crossfade.
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.55, curve: Curves.easeOutCubic),
    );
    // Scale choreography as a sequence: entrance 0.85 → 0.98 (easeOutExpo),
    // then an extremely subtle 0.98 → 1.0 "settle" so the logo visibly lands
    // into position without bouncing, then holds at 1.0 for the branding.
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.85, end: 0.98).chain(
          CurveTween(curve: Curves.easeOutExpo),
        ),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.98, end: 1.0).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 20,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 25),
    ]).animate(_controller);
    _glow = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    // Wordmark fades + slides up subtly after the logo has mostly settled.
    _brandFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 0.9, curve: Curves.easeOut),
    );
    _brandSlide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.45, 0.9, curve: Curves.easeOut),
          ),
        );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppColors.accent;

    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Soft purple atmospheric glow behind the logo.
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.1),
                radius: 1.2,
                colors: [
                  accent.withValues(alpha: 0.16),
                  accent.withValues(alpha: 0.05),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          // Faint resting ring.
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withValues(
                        alpha: 0.06 + _glow.value * 0.06,
                      ),
                      width: 1,
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The logo is a full-colour brand asset; it must never be
                  // tinted into a monochrome silhouette. Render it as-is so
                  // the brand mark keeps its real colours in both themes.
                  FadeTransition(
                    opacity: _fade,
                    child: ScaleTransition(
                      scale: _scale,
                      child: Image.asset(
                        'assets/voratube_logo.png',
                        height: 96,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTokens.s6),
                  // Branding enters just after the logo settles, so the
                  // sequence reads logo → wordmark rather than one flat
                  // crossfade.
                  FadeTransition(
                    opacity: _brandFade,
                    child: SlideTransition(
                      position: _brandSlide,
                      child: Text(
                        'VoraTube',
                        style: theme.textTheme.titleLarge?.copyWith(
                          letterSpacing: 0.5,
                          color: isDark
                              ? theme.colorScheme.onSurface
                              : _brandTint(accent),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _brandTint(Color accent) => accent.withValues(alpha: 0.85);
}

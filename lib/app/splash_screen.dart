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

  /// How long the splash stays on screen. Defaults to 800ms.
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
    _timer = Timer(widget.duration ?? const Duration(milliseconds: 800), () {
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
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppTokens.xslow);
    _fade = CurvedAnimation(parent: _controller, curve: AppTokens.easeOut);
    _scale = Tween<double>(
      begin: 0.9,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: AppTokens.easeOut));
    _glow = CurvedAnimation(parent: _controller, curve: AppTokens.easeIn);
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
              child: FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The logo is a full-colour brand asset; it must never be
                      // tinted into a monochrome silhouette. Render it as-is so
                      // the brand mark keeps its real colours in both themes.
                      Image.asset('assets/voratube_logo.png', height: 96),
                      const SizedBox(height: AppTokens.s6),
                      Text(
                        'VoraTube',
                        style: theme.textTheme.titleLarge?.copyWith(
                          letterSpacing: 0.5,
                          color: isDark
                              ? theme.colorScheme.onSurface
                              : _brandTint(accent),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _brandTint(Color accent) => accent.withValues(alpha: 0.85);
}

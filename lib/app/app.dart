import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'home_shell.dart';
import 'splash_screen.dart';
import 'theme/app_theme.dart';
import '../core/permissions/permission_gate.dart';
import '../features/ads/interstitial_ads_provider.dart';
import '../features/player/presentation/providers/player_providers.dart';
import '../features/settings/presentation/providers/settings_providers.dart';

class VoraTubeApp extends ConsumerWidget {
  const VoraTubeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    // Keep the player's ReplayGain/preamp in sync with persisted audio settings.
    ref.watch(audioSettingsBridgeProvider);
    // Keep the interstitial ad counter alive for the whole session: it listens
    // to track starts and presents a full-screen ad every ~10-15 songs.
    ref.watch(interstitialAdControllerProvider);

    return MaterialApp(
      title: 'VoraTube',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      // Default MaterialApp applies a 200ms AnimatedTheme color crossfade in
      // which every theme-dependent widget across all visited IndexedStack tabs
      // rebuilds and repaints each frame — visibly laggy on mid-range devices
      // during a light/dark switch. Switching in a single frame feels instant.
      themeAnimationDuration: Duration.zero,
      // The splash and permission gates live inside the MaterialApp so they
      // have Directionality/Theme/MediaQuery ancestors. This is the single,
      // correct application root: ProviderScope → MaterialApp → gates → shell.
      home: const SplashGate(child: PermissionGate(child: HomeShell())),
    );
  }
}

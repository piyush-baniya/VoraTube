import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'home_shell.dart';
import 'splash_screen.dart';
import 'theme/app_theme.dart';
import 'theme/chameleon_theme.dart';
import '../core/permissions/permission_gate.dart';
import '../core/update/play_update_host.dart';
import '../features/ads/interstitial_ads_provider.dart';
import '../features/player/presentation/providers/artwork_palette_provider.dart';
import '../features/player/presentation/providers/player_providers.dart';
import '../features/settings/presentation/providers/settings_providers.dart';

class VoraTubeApp extends ConsumerWidget {
  const VoraTubeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final themePreset = ref.watch(themePresetProvider);
    final chameleon = ref.watch(isChameleonProvider);
    // Keep the player's ReplayGain/preamp in sync with persisted audio settings.
    ref.watch(audioSettingsBridgeProvider);
    // Keep the interstitial ad counter alive for the whole session: it listens
    // to track starts and presents a full-screen ad every ~10-15 songs.
    ref.watch(interstitialAdControllerProvider);

    final ThemeData theme;
    final ThemeData darkTheme;
    final Duration themeAnimationDuration;
    if (chameleon) {
      // The whole app derives its ThemeData from the current artwork. The
      // palette controller already keeps the previous palette while a new
      // extraction is in flight, so rapid A→B→C→D track changes can never
      // flash a fallback and always end on the last artwork.
      final state = ref.watch(currentArtworkPaletteProvider);
      final palette = state.palette;
      // Non-fallback palettes always originate from artwork (current or, while
      // extracting, the previous track's): applying them keeps the theme
      // continuous across quick track changes. Theme-derived/fallback palettes
      // are isFallback == true and resolve to the neutral VoraTube identity.
      final fromArtwork = palette != null && !state.isFallback;
      final platformDark =
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
      theme = darkTheme = fromArtwork
          ? ChameleonTheme.build(palette)
          : ChameleonTheme.neutralFallback(isDark: platformDark);
      themeAnimationDuration = ChameleonTheme.transitionDuration;
    } else {
      final appTheme = AppTheme.of(themePreset);
      theme = appTheme.light;
      darkTheme = appTheme.dark;
      // Default MaterialApp applies a 200ms AnimatedTheme color crossfade in
      // which every theme-dependent widget across all visited IndexedStack tabs
      // rebuilds and repaints each frame — visibly laggy on mid-range devices
      // during a light/dark switch. Switching in a single frame feels instant.
      themeAnimationDuration = Duration.zero;
    }

    return MaterialApp(
      title: 'VoraTube',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      themeAnimationDuration: themeAnimationDuration,
      // Mirror the effective theme into the Android system bars. The full
      // player overrides this region with its own artwork-tuned values while
      // open; everything else follows the root theme so nav/status icons always
      // match the (possibly Chameleon-derived) surface brightness.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              Theme.of(context).brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
          systemNavigationBarColor: Theme.of(context).colorScheme.surface,
          systemNavigationBarIconBrightness:
              Theme.of(context).brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      // The splash and permission gates live inside the MaterialApp so they
      // have Directionality/Theme/MediaQuery ancestors. This is the single,
      // correct application root: ProviderScope → MaterialApp → gates → shell.
      home: const SplashGate(
        child: PermissionGate(child: PlayUpdateHost(child: HomeShell())),
      ),
    );
  }
}

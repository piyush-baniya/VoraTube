import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/library/presentation/providers/library_providers.dart';
import '../../shared/widgets/pressable_scale.dart';
import 'permission_service.dart';

/// First-run permission gate.
///
/// On Android, VoraTube needs `READ_MEDIA_AUDIO` to read the user's music via
/// MediaStore, so the app shows a permission screen before [child] until
/// access is granted. On iOS the V1 experience is user-initiated file import
/// (the system picker needs no special permission), so the gate passes
/// straight through and [child] is shown immediately.
///
/// The gate is hosted as the `home` of [MaterialApp] (see `app.dart`), wrapped
/// in [SplashGate]: `ProviderScope -> MaterialApp -> SplashGate ->
/// PermissionGate -> HomeShell`. Keeping it inside the [MaterialApp] means it
/// always has Directionality/Theme/MediaQuery ancestors, and it sits above the
/// app shell so the user cannot reach the main app until audio access exists.
class PermissionGate extends ConsumerStatefulWidget {
  const PermissionGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PermissionGate> createState() => _PermissionGateState();
}

enum _GateStatus { checking, granted, denied, permanentlyDenied }

class _PermissionGateState extends ConsumerState<PermissionGate>
    with WidgetsBindingObserver {
  _GateStatus _status = _GateStatus.checking;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check the *actual* OS permission whenever the app returns to the
    // foreground. This covers returning from the system Settings after the
    // user toggles audio access, and externally revoked permissions. We
    // deliberately do not cache/go off a stored boolean.
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    // iOS does not need an audio-library permission for V1 file import.
    if (defaultTargetPlatform != TargetPlatform.android) {
      if (mounted) setState(() => _status = _GateStatus.granted);
      return;
    }
    final service = ref.read(permissionServiceProvider);
    final MediaPermissionStatus status;
    try {
      status = await service.audioStatus();
    } catch (_) {
      if (mounted) setState(() => _status = _GateStatus.denied);
      return;
    }
    if (!mounted) return;
    _apply(status);
  }

  Future<void> _request() async {
    final service = ref.read(permissionServiceProvider);
    final MediaPermissionStatus status;
    try {
      status = await service.requestAudio();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    _apply(status);
  }

  void _apply(MediaPermissionStatus status) {
    setState(() {
      _status = switch (status) {
        MediaPermissionStatus.granted => _GateStatus.granted,
        MediaPermissionStatus.permanentlyDenied =>
          _GateStatus.permanentlyDenied,
        MediaPermissionStatus.denied => _GateStatus.denied,
      };
    });
  }

  Future<void> _openSettings() async {
    await ref.read(permissionServiceProvider).openAppSettingsPage();
    // The OS permission is re-checked on resume via didChangeAppLifecycleState.
  }

  @override
  Widget build(BuildContext context) {
    return switch (_status) {
      _GateStatus.checking => const _PermissionSplash(),
      _GateStatus.granted => widget.child,
      _GateStatus.denied => _PermissionRequiredScreen(
        permanentlyDenied: false,
        onAllow: _request,
      ),
      _GateStatus.permanentlyDenied => _PermissionRequiredScreen(
        permanentlyDenied: true,
        onAllow: _request,
        onOpenSettings: _openSettings,
      ),
    };
  }
}

/// Brief branded splash shown while the initial permission status resolves.
class _PermissionSplash extends StatelessWidget {
  const _PermissionSplash();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: CircularProgressIndicator(
          color: theme.colorScheme.primary,
          strokeWidth: 2.4,
        ),
      ),
    );
  }
}

/// Branded screen explaining why media access is needed, with contextually
/// appropriate actions.
class _PermissionRequiredScreen extends StatelessWidget {
  const _PermissionRequiredScreen({
    required this.permanentlyDenied,
    required this.onAllow,
    this.onOpenSettings,
  });

  final bool permanentlyDenied;
  final VoidCallback onAllow;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      child: Icon(
                        Icons.library_music_rounded,
                        size: 44,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Your music, your library',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      permanentlyDenied
                          ? 'Music access was previously blocked. Re-enable it for VoraTube in your device settings so it can read the music on this device. Nothing ever leaves your device.'
                          : 'VoraTube needs access to your music and audio files to build your local library. Your music stays on this device.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    PressableScale(
                      onTap: permanentlyDenied ? onOpenSettings : onAllow,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 240),
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isDark
                                ? [colorScheme.primary, colorScheme.secondary]
                                : [
                                    colorScheme.primary,
                                    colorScheme.primary.withValues(alpha: 0.85),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              permanentlyDenied
                                  ? Icons.settings_rounded
                                  : Icons.lock_open_rounded,
                              size: 20,
                              color: colorScheme.onPrimary,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                permanentlyDenied
                                    ? 'Open settings'
                                    : 'Allow access to music',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: colorScheme.onPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
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
          ),
        ),
      ),
    );
  }
}

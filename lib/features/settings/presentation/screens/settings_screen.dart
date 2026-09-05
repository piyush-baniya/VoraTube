import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../app/widgets/vora_snackbar.dart';
import '../../../../core/ingest/ingest_service.dart';
import '../../../../core/privacy/privacy_config.dart';
import '../../../../features/library/presentation/providers/library_providers.dart';
import '../../../../features/player/presentation/providers/player_providers.dart';
import '../../../../features/player/presentation/providers/sleep_timer_provider.dart';
import '../../../../features/player/presentation/widgets/sleep_timer_sheet.dart';
import '../../../../core/player/player_controller.dart';
import '../../../ads/banner_ad_widget.dart';
import '../../../ads/premium_models.dart';
import '../../../ads/premium_providers.dart';
import '../../../ads/premium_sheets.dart';
import '../../../donation/presentation/screens/donation_screen.dart';
import 'faq_screen.dart';
import 'hidden_songs_screen.dart';
import 'privacy_policy_screen.dart';
import 'terms_screen.dart';
import '../../data/settings_models.dart';
import '../providers/settings_providers.dart';
import '../widgets/settings_section.dart';
import '../widgets/settings_tile.dart';
import '../widgets/storage_info_card.dart';
import '../../../../shared/widgets/empty_state.dart' show ScreenHeader;

/// Snackbar copy for a finished missing-file cleanup, derived from the REAL
/// removed-entry count returned by `reconcileMissingFiles`.
///
/// [removed] is that count; `null` means the cleanup itself threw. Kept as a
/// pure top-level helper (and unit-tested) so the screen can never drift into
/// reporting scanned rows, estimates or hard-coded numbers.
({String title, String message, bool isError}) missingFileCleanupResult(
  int? removed,
) {
  if (removed == null) {
    return (
      title: 'Cleanup failed',
      message: "We couldn't complete missing file cleanup.",
      isError: true,
    );
  }
  if (removed > 0) {
    return (
      title: 'Cleanup complete',
      message:
          'Successfully cleaned $removed missing file${removed == 1 ? '' : 's'}.',
      isError: false,
    );
  }
  return (
    title: 'Cleanup complete',
    message: 'No missing files needed to be cleaned.',
    isError: false,
  );
}

/// Redesigned Settings screen with organized sections.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScreenHeader(title: 'Settings', showLogo: true),
                const SizedBox(height: AppTokens.s2),
              ],
            ),
          ),
          // A single, small, unobtrusive banner. It sits near the top of the
          // Settings list and collapses to nothing when Premium is active or
          // the ad fails to load.
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: AppTokens.s5),
              child: VoraTubeBannerAd(),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s2)),
          const SliverToBoxAdapter(child: _ScanSnackBarListener()),
          SliverToBoxAdapter(child: _AppearanceSection()),
          const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s4)),
          SliverToBoxAdapter(child: _PlaybackSection()),
          const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s4)),
          SliverToBoxAdapter(child: _AudioSection()),
          const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s4)),
          SliverToBoxAdapter(child: _LibrarySection()),
          const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s4)),
          SliverToBoxAdapter(child: _StorageSection()),
          const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s4)),
          const SliverToBoxAdapter(child: _SupportSection()),
          const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s4)),
          const SliverToBoxAdapter(child: _LegalSection()),
          const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s4)),
          SliverToBoxAdapter(child: _AboutSection()),
          const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s4)),
          SliverToBoxAdapter(child: _PremiumSection()),
          const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s8)),
        ],
      ),
    );
  }
}

/// Playback settings section.
class _PlaybackSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsSection(
      title: 'Playback',
      children: [
        _SleepTimerTile(),
        SettingsSwitchTile(
          title: 'Shuffle',
          subtitle: 'Play songs in random order',
          value: ref.watch(playbackStateProvider).shuffleEnabled,
          onChanged: (value) => ref.read(playerProvider).setShuffle(value),
        ),
        SettingsSelectTile<RepeatMode>(
          title: 'Repeat',
          subtitle: 'Repeat playback behavior',
          value: ref.watch(playbackStateProvider).repeatMode,
          onChanged: (mode) => ref.read(playerProvider).setRepeat(mode),
          items: const [RepeatMode.off, RepeatMode.all, RepeatMode.one],
          itemBuilder: (context, mode) => Text(mode.name.capitalize()),
        ),
        SettingsTile(
          title: 'Crossfade',
          subtitle: 'Gapless playback is used instead of crossfade',
          trailing: Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant
                .withValues(alpha: 0.4),
          ),
        ),
        SettingsTile(
          title: 'Gapless Playback',
          subtitle: 'Enabled by default for seamless transitions',
          trailing: Icon(
            Icons.check_circle_rounded,
            color: Theme.of(context).colorScheme.tertiary,
            size: 18,
          ),
          isLastInSection: true,
        ),
      ],
    );
  }
}

/// Sleep Timer tile in the Playback section. Shows a live remaining-time
/// subtitle while a timer runs and opens the shared Sleep Timer sheet.
class _SleepTimerTile extends ConsumerWidget {
  const _SleepTimerTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = ref.watch(sleepTimerIsActiveProvider);
    final remaining = ref.watch(sleepTimerRemainingProvider);
    return SettingsTile(
      title: 'Sleep Timer',
      subtitle: active
          ? (remaining <= const Duration(minutes: 5)
                ? 'Counting down — ${formatSleepTimer(remaining)} remaining'
                : 'Sleep timer is on')
          : 'Pause playback automatically after a set time',
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppTokens.rMd),
        ),
        child: Icon(
          Icons.bedtime_rounded,
          size: 20,
          color: colorScheme.primary,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 18,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
      ),
      onTap: () => showSleepTimerSheet(context),
    );
  }
}

/// Audio settings section.
class _AudioSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioSettings = ref.watch(audioSettingsProvider);

    return SettingsSection(
      title: 'Audio',
      children: [
        SettingsSelectTile<ReplayGainPreference>(
          title: 'ReplayGain',
          subtitle: 'Normalize volume across tracks',
          value: audioSettings.replayGain,
          onChanged: (value) =>
              ref.read(audioSettingsProvider.notifier).setReplayGain(value),
          items: const [
            ReplayGainPreference.off,
            ReplayGainPreference.track,
            ReplayGainPreference.album,
          ],
          itemBuilder: (context, mode) => Text(mode.name.capitalize()),
        ),
        SettingsSliderTile(
          title: 'Preamp',
          subtitle: 'Adjust ReplayGain volume (dB)',
          value: audioSettings.preampDb,
          onChanged: (v) =>
              ref.read(audioSettingsProvider.notifier).setPreampDb(v),
          min: -12.0,
          max: 12.0,
          divisions: 24,
          label: '${audioSettings.preampDb.toStringAsFixed(1)} dB',
        ),
        SettingsTile(
          title: 'Volume Normalization',
          subtitle: 'ReplayGain track/album gain applied at playback start',
          trailing: Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant
                .withValues(alpha: 0.4),
          ),
          isLastInSection: true,
        ),
      ],
    );
  }
}

/// Library settings section.
class _LibrarySection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final librarySettings = ref.watch(librarySettingsProvider);

    return SettingsSection(
      title: 'Library',
      children: [
        SettingsActionTile(
          title: 'Rescan Library',
          subtitle: 'Scan for new or changed music files',
          buttonText: 'Rescan Now',
          onPressed: () => _showRescanDialog(context, ref),
        ),
        SettingsSwitchTile(
          title: 'Clean Missing Files on Start',
          subtitle: 'Remove library entries for deleted files on startup',
          value: librarySettings.cleanMissingFilesOnStart,
          onChanged: (v) => ref
              .read(librarySettingsProvider.notifier)
              .setCleanMissingFilesOnStart(v),
        ),
        SettingsActionTile(
          title: 'Missing File Cleanup',
          subtitle: 'Remove entries for files that no longer exist',
          buttonText: 'Cleanup Now',
          onPressed: () => _runMissingFileCleanup(context, ref),
        ),
        SettingsTile(
          title: 'Show Hidden Songs',
          subtitle: 'View and restore songs you hid',
          trailing: Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant
                .withValues(alpha: 0.4),
          ),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const HiddenSongsScreen())),
          isLastInSection: true,
        ),
      ],
    );
  }

  Future<void> _showRescanDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rescan Library'),
        content: const Text(
          'This will scan your music library for new or changed files. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rescan'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      ref.read(scanControllerProvider.notifier).startScan();
    }
  }

  Future<void> _runMissingFileCleanup(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clean Missing Files'),
        content: const Text(
          'This will remove library entries for files that no longer exist in VoraTube storage. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cleanup'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final controller = ref.read(importControllerProvider.notifier);
      try {
        final removed = await controller.reconcileMissingFiles();
        if (!context.mounted) return;
        final result = missingFileCleanupResult(removed);
        VoraSnackbar.success(
          context,
          result.message,
          title: result.title,
        );
      } catch (_) {
        if (!context.mounted) return;
        final result = missingFileCleanupResult(null);
        VoraSnackbar.error(
          context,
          result.message,
          title: result.title,
        );
      }
    }
  }
}

/// Appearance settings section.
class _AppearanceSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearanceSettings = ref.watch(appearanceSettingsProvider);

    return SettingsSection(
      title: 'Appearance',
      children: [
        SettingsSelectTile<AppThemeMode>(
          title: 'Theme',
          subtitle: 'Choose color theme',
          value: appearanceSettings.themeMode,
          onChanged: (mode) =>
              ref.read(appearanceSettingsProvider.notifier).setThemeMode(mode),
          items: const [
            AppThemeMode.system,
            AppThemeMode.dark,
            AppThemeMode.light,
          ],
          itemBuilder: (context, mode) => Text(mode.name.capitalize()),
          isLastInSection: true,
        ),
      ],
    );
  }
}

/// Storage section.
class _StorageSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storageInfo = ref.watch(storageInfoProvider);

    return SettingsSection(
      title: 'Storage',
      children: [
        storageInfo.when(
          loading: () => SettingsTile(
            title: 'Loading storage info...',
            trailing: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          error: (_, __) => SettingsTile(
            title: 'Storage info unavailable',
            trailing: Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          data: (info) => StorageInfoCard(),
        ),
      ],
    );
  }
}

/// About section.
class _AboutSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SettingsSection(
      title: 'About',
      children: [
        SettingsTile(
          title: 'VoraTube',
          subtitle: 'Local-first music player',
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppTokens.rMd),
            ),
            child: Icon(
              Icons.music_note_rounded,
              size: 22,
              color: colorScheme.primary,
            ),
          ),
        ),
        SettingsTile(
          title: 'Version',
          subtitle: ref.watch(appVersionProvider).value ?? '',
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.secondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppTokens.rMd),
            ),
            child: Icon(
              Icons.info_outline_rounded,
              size: 20,
              color: colorScheme.secondary,
            ),
          ),
        ),
        SettingsTile(
          title: 'Support the Developer',
          subtitle: 'Buy Me a Momo donation',
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppTokens.rMd),
            ),
            child: Icon(
              Icons.favorite_rounded,
              size: 20,
              color: colorScheme.primary,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          onTap: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const DonationScreen()));
          },
          isLastInSection: true,
        ),
      ],
    );
  }
}

/// Support section: help and feedback entries.
class _SupportSection extends StatelessWidget {
  const _SupportSection();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SettingsSection(
      title: 'Support',
      children: [
        SettingsTile(
          title: 'FAQ',
          subtitle: 'Answers to common questions',
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.tertiary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppTokens.rMd),
            ),
            child: Icon(
              Icons.help_outline_rounded,
              size: 20,
              color: colorScheme.tertiary,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const FaqScreen())),
        ),
        SettingsTile(
          title: 'Feedback',
          subtitle: 'Share feedback on Instagram',
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppTokens.rMd),
            ),
            child: Icon(
              Icons.rate_review_outlined,
              size: 20,
              color: colorScheme.primary,
            ),
          ),
          trailing: Icon(
            Icons.open_in_new_rounded,
            size: 18,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          onTap: () => _openFeedback(context),
          isLastInSection: true,
        ),
      ],
    );
  }

  /// Opens VoraTube's feedback page on Instagram in an external app/browser.
  ///
  /// The UI clearly redirects the user to Instagram rather than submitting
  /// feedback in-app. Gracefully degrades to a snackbar when the URL cannot be
  /// opened (no browser/app available, invalid URL, launcher failure) — it
  /// never crashes.
  Future<void> _openFeedback(BuildContext context) async {
    try {
      final launched = await launchUrl(
        Uri.parse(kFeedbackInstagramUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        VoraSnackbar.error(
          context,
          'Could not open Instagram for feedback.',
          title: 'Error',
        );
      }
    } catch (_) {
      if (context.mounted) {
        VoraSnackbar.error(
          context,
          'Could not open Instagram for feedback.',
          title: 'Error',
        );
      }
    }
  }
}

/// Legal section: policy and terms entries, opened in-app.
class _LegalSection extends StatelessWidget {
  const _LegalSection();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SettingsSection(
      title: 'Legal',
      children: [
        SettingsTile(
          title: 'Privacy Policy',
          subtitle: 'How VoraTube handles your data',
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.tertiary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppTokens.rMd),
            ),
            child: Icon(
              Icons.privacy_tip_rounded,
              size: 20,
              color: colorScheme.tertiary,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
          ),
        ),
        SettingsTile(
          title: 'Terms of Use',
          subtitle: 'Agreement for using VoraTube',
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.secondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppTokens.rMd),
            ),
            child: Icon(
              Icons.description_rounded,
              size: 20,
              color: colorScheme.secondary,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const TermsScreen())),
          isLastInSection: true,
        ),
      ],
    );
  }
}

extension _StringCapitalize on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

/// Premium section: activates or disables VoraTube's ad-free entitlement.
class _PremiumSection extends ConsumerWidget {
  const _PremiumSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final premium = ref.watch(premiumProvider);
    final isActive = premium == PremiumEntitlement.active;

    return SettingsSection(
      title: 'Premium',
      children: [
        if (isActive)
          SettingsTile(
            title: 'Premium',
            subtitle: 'Ads disabled',
            leading: _PremiumLeading(color: colorScheme.primary),
            trailing: Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: colorScheme.tertiary,
            ),
          ),
        SettingsTile(
          title: isActive ? 'Disable Premium' : 'Activate Premium',
          subtitle: isActive
              ? 'Turn ads back on and remove the ad-free entitlement'
              : 'Unlock ad-free listening',
          leading: _PremiumLeading(color: colorScheme.primary),
          trailing: Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          onTap: () => _onTap(context, ref, isActive),
          isLastInSection: true,
        ),
      ],
    );
  }

  Future<void> _onTap(
    BuildContext context,
    WidgetRef ref,
    bool isActive,
  ) async {
    if (isActive) {
      final confirmed = await showPremiumDisableDialog(context);
      if (confirmed) {
        await ref.read(premiumProvider.notifier).deactivate();
      }
    } else {
      await showPremiumActivationSheet(context);
    }
  }
}

/// Small premium icon tile used by the Settings premium section.
class _PremiumLeading extends StatelessWidget {
  const _PremiumLeading({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: Icon(Icons.workspace_premium_rounded, size: 20, color: color),
    );
  }
}

/// Listens for scan state changes and shows appropriate snackbars.
///
/// Placed in the Settings screen so that scan progress and completion are
/// communicated via the unified [VoraSnackbar] system. The scan itself
/// continues regardless of navigation — this widget only surfaces feedback.
class _ScanSnackBarListener extends ConsumerStatefulWidget {
  const _ScanSnackBarListener();

  @override
  ConsumerState<_ScanSnackBarListener> createState() =>
      _ScanSnackBarListenerState();
}

class _ScanSnackBarListenerState extends ConsumerState<_ScanSnackBarListener> {
  @override
  Widget build(BuildContext context) {
    ref.listenManual<ScanUiState>(scanControllerProvider, (previous, next) {
      _handleStateChange(previous, next);
    });
    return const SizedBox.shrink();
  }

  void _handleStateChange(ScanUiState? previous, ScanUiState next) {
    if (next is ScanRunning && previous is! ScanRunning) {
      VoraSnackbar.showProgress(
        context,
        'Looking for music on your device…',
        title: 'Scanning music',
      );
    }

    if (next is ScanComplete && previous is! ScanComplete) {
      _showScanComplete(next.summary);
    }

    if (next is ScanFailure && previous is! ScanFailure) {
      VoraSnackbar.error(context, next.message, title: 'Scan failed');
    }
  }

  void _showScanComplete(ScanSummary summary) {
    final total = summary.totalSongs;
    final added = summary.addedSongs;
    final updated = summary.updatedSongs;
    final removed = summary.removedSongs;

    String message;
    if (total == 0) {
      message = 'No music files were found.';
    } else if (added == 0 && updated == 0 && removed == 0) {
      message = 'Successfully rescanned $total songs.';
    } else {
      final parts = <String>[];
      if (added > 0) parts.add('$added added');
      if (updated > 0) parts.add('$updated updated');
      if (removed > 0) parts.add('$removed removed');
      message = '${parts.join(' • ')} • $total total songs';
    }

    VoraSnackbar.success(context, message, title: 'Music scan complete');
  }
}

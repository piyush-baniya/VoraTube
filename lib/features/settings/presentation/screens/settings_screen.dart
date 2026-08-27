import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../features/library/presentation/providers/library_providers.dart';
import '../../../../features/player/presentation/providers/player_providers.dart';
import '../../../../core/player/player_controller.dart';
import '../../../donation/presentation/screens/donation_screen.dart';
import '../../data/settings_models.dart';
import '../providers/settings_providers.dart';
import '../widgets/settings_section.dart';
import '../widgets/settings_tile.dart';
import '../widgets/storage_info_card.dart';
import '../../../../shared/widgets/empty_state.dart' show ScreenHeader;

/// Redesigned Settings screen with organized sections.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScreenHeader(title: 'Settings'),
                const SizedBox(height: AppTokens.s2),
              ],
            ),
          ),
          SliverToBoxAdapter(child: _PlaybackSection()),
          const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s4)),
          SliverToBoxAdapter(child: _AudioSection()),
          const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s4)),
          SliverToBoxAdapter(child: _LibrarySection()),
          const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s4)),
          SliverToBoxAdapter(child: _AppearanceSection()),
          const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s4)),
          SliverToBoxAdapter(child: _StorageSection()),
          const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s4)),
          SliverToBoxAdapter(child: _AboutSection()),
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
        ),
      ],
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
          title: 'Gapless Playback',
          subtitle: 'Seamless track transitions (always on)',
          trailing: Icon(
            Icons.check_circle_rounded,
            color: Theme.of(context).colorScheme.tertiary,
            size: 18,
          ),
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
          title: 'Auto Rescan on Start',
          subtitle: 'Automatically scan for changes on app launch',
          value: librarySettings.autoRescanOnStart,
          onChanged: (v) => ref
              .read(librarySettingsProvider.notifier)
              .setAutoRescanOnStart(v),
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
      await controller.reconcileMissingFiles();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing file cleanup complete')),
      );
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
          subtitle: _getVersion(),
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
          title: 'Privacy',
          subtitle: 'All data stays on your device',
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
        ),
        SettingsTile(
          title: 'Open Source Licenses',
          subtitle: 'View third-party licenses',
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.15,
              ),
              borderRadius: BorderRadius.circular(AppTokens.rMd),
            ),
            child: Icon(
              Icons.article_rounded,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          onTap: () => showLicensePage(context: context),
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
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const DonationScreen(),
              ),
            );
          },
        ),
      ],
    );
  }

  String _getVersion() {
    return '1.0.0';
  }
}

extension _StringCapitalize on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

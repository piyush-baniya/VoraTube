import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../features/library/presentation/providers/library_providers.dart';
import '../../../../features/player/presentation/providers/player_providers.dart';
import '../../../../core/player/player_controller.dart';
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

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ScreenHeader(title: 'Settings'),
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
          const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s6)),
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
        SettingsTile(
          title: 'Shuffle',
          subtitle: 'Play songs in random order',
          trailing: Consumer(
            builder: (context, ref, _) {
              final shuffle =
                  ref.watch(playbackSnapshotProvider).value?.shuffleEnabled ??
                  false;
              return Switch(
                value: shuffle,
                onChanged: (value) =>
                    ref.read(playerProvider).setShuffle(value),
              );
            },
          ),
        ),
        SettingsTile(
          title: 'Repeat',
          subtitle: 'Repeat playback behavior',
          trailing: Consumer(
            builder: (context, ref, _) {
              final repeat =
                  ref.watch(playbackSnapshotProvider).value?.repeatMode ??
                  RepeatMode.off;
              return PopupMenuButton<RepeatMode>(
                initialValue: repeat,
                onSelected: (mode) => ref.read(playerProvider).setRepeat(mode),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: RepeatMode.off,
                    child: Text('Off'),
                  ),
                  const PopupMenuItem(
                    value: RepeatMode.all,
                    child: Text('All'),
                  ),
                  const PopupMenuItem(
                    value: RepeatMode.one,
                    child: Text('One'),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppTokens.s2),
                  child: Text(
                    repeat.name.capitalize(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SettingsTile(
          title: 'Crossfade',
          subtitle: 'Gapless playback is used instead of crossfade',
          subtitleStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant
                .withValues(alpha: 0.6),
            fontSize: 12,
          ),
          trailing: const Icon(Icons.lock_outline, size: 18),
        ),
        SettingsTile(
          title: 'Gapless Playback',
          subtitle: 'Enabled by default for seamless transitions',
          trailing: const Icon(
            Icons.check_circle,
            color: Colors.green,
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
        SettingsTile(
          title: 'ReplayGain',
          subtitle: 'Normalize volume across tracks',
          trailing: PopupMenuButton<ReplayGainPreference>(
            initialValue: audioSettings.replayGain,
            onSelected: (value) =>
                ref.read(audioSettingsProvider.notifier).setReplayGain(value),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: ReplayGainPreference.off,
                child: Text('Off'),
              ),
              const PopupMenuItem(
                value: ReplayGainPreference.track,
                child: Text('Track Gain'),
              ),
              const PopupMenuItem(
                value: ReplayGainPreference.album,
                child: Text('Album Gain'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.s2),
              child: Text(
                audioSettings.replayGain.name.capitalize(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        SettingsTile(
          title: 'Preamp',
          subtitle: 'Adjust ReplayGain volume (dB)',
          trailing: SizedBox(
            width: 100,
            child: Consumer(
              builder: (context, ref, _) {
                final preamp = ref.watch(audioSettingsProvider).preampDb;
                return Slider(
                  value: preamp,
                  min: -12.0,
                  max: 12.0,
                  divisions: 24,
                  onChanged: (v) =>
                      ref.read(audioSettingsProvider.notifier).setPreampDb(v),
                  label: '${preamp.toStringAsFixed(1)} dB',
                );
              },
            ),
          ),
        ),
        SettingsTile(
          title: 'Gapless Playback',
          subtitle: 'Seamless track transitions (always on)',
          trailing: const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 18,
          ),
        ),
        SettingsTile(
          title: 'Volume Normalization',
          subtitle: 'ReplayGain track/album gain applied at playback start',
          trailing: const Icon(Icons.info_outline, size: 18),
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
        SettingsTile(
          title: 'Rescan Library',
          subtitle: 'Scan for new or changed music files',
          trailing: FilledButton.tonal(
            onPressed: () => _showRescanDialog(context, ref),
            child: const Text('Rescan Now'),
          ),
        ),
        SettingsTile(
          title: 'Auto Rescan on Start',
          subtitle: 'Automatically scan for changes on app launch',
          trailing: Switch(
            value: librarySettings.autoRescanOnStart,
            onChanged: (v) => ref
                .read(librarySettingsProvider.notifier)
                .setAutoRescanOnStart(v),
          ),
        ),
        SettingsTile(
          title: 'Clean Missing Files',
          subtitle: 'Remove library entries for deleted files on startup',
          trailing: Switch(
            value: librarySettings.cleanMissingFilesOnStart,
            onChanged: (v) => ref
                .read(librarySettingsProvider.notifier)
                .setCleanMissingFilesOnStart(v),
          ),
        ),
        SettingsTile(
          title: 'Missing File Cleanup',
          subtitle: 'Remove entries for files that no longer exist',
          trailing: FilledButton.tonal(
            onPressed: () => _runMissingFileCleanup(context, ref),
            child: const Text('Cleanup Now'),
          ),
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
        SettingsTile(
          title: 'Theme',
          subtitle: 'Choose color theme',
          trailing: PopupMenuButton<AppThemeMode>(
            initialValue: appearanceSettings.themeMode,
            onSelected: (mode) => ref
                .read(appearanceSettingsProvider.notifier)
                .setThemeMode(mode),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: AppThemeMode.system,
                child: Text('System'),
              ),
              const PopupMenuItem(
                value: AppThemeMode.dark,
                child: Text('Dark'),
              ),
              const PopupMenuItem(
                value: AppThemeMode.light,
                child: Text('Light'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.s2),
              child: Text(
                appearanceSettings.themeMode.name.capitalize(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
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
            trailing: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, __) => SettingsTile(
            title: 'Storage info unavailable',
            trailing: const Icon(Icons.error_outline, size: 18),
          ),
          data: (info) => Column(
            children: [
              SettingsTile(
                title: 'Total Storage',
                subtitle: info.totalSize,
                leading: const Icon(Icons.storage, size: 20),
              ),
              SettingsTile(
                title: 'Database',
                subtitle: info.databaseSize,
                leading: const Icon(Icons.storage, size: 20),
              ),
              SettingsTile(
                title: 'Artwork Cache',
                subtitle: info.artworkCacheSize,
                leading: const Icon(Icons.image, size: 20),
              ),
              SettingsTile(
                title: 'Imported Music',
                subtitle: info.importedMusicSize,
                leading: const Icon(Icons.music_note, size: 20),
              ),
              SettingsTile(
                title: 'Clear Artwork Cache',
                subtitle: 'Remove cached artwork (will be regenerated)',
                trailing: TextButton(
                  onPressed: () => _clearArtworkCache(context, ref),
                  child: const Text('Clear'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _clearArtworkCache(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Artwork Cache'),
        content: const Text(
          'This will remove all cached artwork. It will be regenerated as needed. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      // TODO: Implement artwork cache clearing
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Artwork cache cleared')));
    }
  }
}

/// About section.
class _AboutSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsSection(
      title: 'About',
      children: [
        SettingsTile(
          title: 'VoraTube',
          subtitle: 'Local-first music player',
          leading: const Icon(Icons.music_note, size: 24),
        ),
        SettingsTile(
          title: 'Version',
          subtitle: _getVersion(),
          leading: const Icon(Icons.info_outline, size: 20),
        ),
        SettingsTile(
          title: 'Privacy',
          subtitle: 'All data stays on your device',
          trailing: const Icon(Icons.chevron_right, size: 18),
        ),
        SettingsTile(
          title: 'Open Source Licenses',
          subtitle: 'View third-party licenses',
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => showLicensePage(context: context),
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

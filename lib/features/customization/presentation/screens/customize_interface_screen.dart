import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../app/widgets/vora_snackbar.dart';
import '../../../../core/ui_customization/ui_layout.dart';
import '../../../settings/presentation/widgets/settings_section.dart';
import '../../../settings/presentation/widgets/settings_tile.dart';
import '../providers/layout_providers.dart';
import 'customize_home_screen.dart';
import 'customize_mini_player_screen.dart';
import 'customize_player_screen.dart';

/// Hub for interface customization: curated presets, per-screen editors and a
/// global reset. Future screens (Equalizer, Lyrics, Statistics) are listed so
/// the model is visibly ready for them, but stay disabled until their
/// registries ship.
class CustomizeInterfaceScreen extends ConsumerWidget {
  const CustomizeInterfaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(layoutProfileProvider).valueOrNull;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Customize Interface')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppTokens.s8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.s5,
              AppTokens.s4,
              AppTokens.s5,
              AppTokens.s2,
            ),
            child: Text(
              'Choose a preset or fine-tune each screen. Your layout is stored '
              'on this device and applies per orientation.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          SettingsSection(
            title: 'Preset',
            children: [
              SettingsSelectTile<LayoutPreset>(
                title: 'Interface preset',
                subtitle: 'A curated arrangement for every screen',
                value: profile?.preset ?? LayoutPreset.standard,
                onChanged: (preset) => ref
                    .read(layoutProfileProvider.notifier)
                    .applyPreset(preset),
                items: LayoutPreset.values,
                itemBuilder: (context, preset) => Text(preset.label),
                valueBuilder: (context, preset) => Text(
                  preset.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                isLastInSection: true,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s4),
          SettingsSection(
            title: 'Screens',
            children: [
              SettingsTile(
                title: 'Home',
                subtitle: 'Reorder, hide and resize Home sections',
                leading: _leading(context, Icons.home_rounded),
                trailing: _chevron(context),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CustomizeHomeScreen(),
                  ),
                ),
              ),
              SettingsTile(
                title: 'Player',
                subtitle: 'Tune the full-screen Now Playing layout',
                leading: _leading(context, Icons.disc_full_rounded),
                trailing: _chevron(context),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CustomizePlayerScreen(),
                  ),
                ),
              ),
              SettingsTile(
                title: 'Mini Player',
                subtitle: 'Tune the compact Now Playing bar',
                leading: _leading(context, Icons.minimize_rounded),
                trailing: _chevron(context),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CustomizeMiniPlayerScreen(),
                  ),
                ),
                isLastInSection: true,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s4),
          SettingsSection(
            title: 'Reset',
            children: [
              SettingsActionTile(
                title: 'Reset customization',
                subtitle: 'Restore every screen to its default layout',
                buttonText: 'Reset',
                isDestructive: true,
                onPressed: () => _confirmReset(context, ref),
                isLastInSection: true,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.s4),
          SettingsSection(
            title: 'Coming soon',
            children: [
              _comingSoon(context, 'Equalizer'),
              _comingSoon(context, 'Lyrics'),
              _comingSoon(context, 'Statistics', isLast: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _leading(BuildContext context, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: Icon(icon, size: 20, color: colorScheme.primary),
    );
  }

  Widget _chevron(BuildContext context) => Icon(
    Icons.chevron_right_rounded,
    size: 18,
    color: Theme.of(context).colorScheme.onSurfaceVariant
        .withValues(alpha: 0.4),
  );

  Widget _comingSoon(
    BuildContext context,
    String title, {
    bool isLast = false,
  }) {
    return SettingsTile(
      title: title,
      subtitle: 'Coming soon',
      leading: _leading(context, Icons.lock_outline_rounded),
      isLastInSection: isLast,
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset customization'),
        content: const Text(
          'This restores the default layout for every screen. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(layoutProfileProvider.notifier).reset();
    if (!context.mounted) return;
    VoraSnackbar.success(context, 'Interface reset to default.');
  }
}

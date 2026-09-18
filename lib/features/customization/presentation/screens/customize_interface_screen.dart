import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../app/widgets/vora_snackbar.dart';
import '../../../../core/ui_customization/ui_component_registry.dart';
import '../../../../core/ui_customization/ui_layout.dart';
import '../../../settings/presentation/widgets/settings_section.dart';
import '../../../settings/presentation/widgets/settings_tile.dart';
import '../providers/layout_providers.dart';
import 'live_layout_editor.dart';

/// Hub for interface customization. Each screen opens the live editor where the
/// real screen is rendered and its sections can be reordered, resized, hidden,
/// restored and restyled directly, with undo/redo and a Cancel-vs-Done flow.
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
              'Pick an interface preset, or open a screen and rearrange its '
              'sections directly. Layouts are stored on this device and apply '
              'per orientation.',
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
                onTap: () => _open(context, kHomeScreenId, 'Home'),
              ),
              SettingsTile(
                title: 'Player',
                subtitle: 'Tune the full-screen Now Playing layout',
                leading: _leading(context, Icons.disc_full_rounded),
                trailing: _chevron(context),
                onTap: () => _open(context, kPlayerScreenId, 'Player'),
              ),
              SettingsTile(
                title: 'Mini Player',
                subtitle: 'Tune the compact Now Playing bar',
                leading: _leading(context, Icons.minimize_rounded),
                trailing: _chevron(context),
                onTap: () => _open(context, kMiniScreenId, 'Mini Player'),
              ),
              SettingsTile(
                title: 'Equalizer',
                subtitle: 'Reorder the curve, presets and controls',
                leading: _leading(context, Icons.graphic_eq_rounded),
                trailing: _chevron(context),
                onTap: () => _open(context, kEqualizerScreenId, 'Equalizer'),
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
        ],
      ),
    );
  }

  void _open(BuildContext context, String screenId, String title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LiveLayoutEditor(screenId: screenId, title: title),
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

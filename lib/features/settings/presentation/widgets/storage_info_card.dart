import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../providers/settings_providers.dart';

/// Storage info card widget.
class StorageInfoCard extends ConsumerWidget {
  const StorageInfoCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storageInfo = ref.watch(storageInfoProvider);

    return storageInfo.when(
      loading: () => _buildLoading(context),
      error: (_, __) => _buildError(context),
      data: (info) => _buildData(context, info),
    );
  }

  Widget _buildLoading(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s4),
        child: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppTokens.s3),
            Text('Loading storage info...', style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s4),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
            const SizedBox(width: AppTokens.s3),
            Text('Storage info unavailable', style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  Widget _buildData(BuildContext context, StorageInfo info) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.storage,
            label: 'Total Storage',
            value: info.totalSize,
            iconColor: colorScheme.primary,
          ),
          const _Divider(),
          _InfoRow(
            icon: Icons.storage,
            label: 'Database',
            value: info.databaseSize,
            iconColor: Colors.blue,
          ),
          _InfoRow(
            icon: Icons.image,
            label: 'Artwork Cache',
            value: info.artworkCacheSize,
            iconColor: Colors.purple,
          ),
          _InfoRow(
            icon: Icons.music_note,
            label: 'Imported Music',
            value: info.importedMusicSize,
            iconColor: Colors.green,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s4,
        vertical: AppTokens.s2,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppTokens.rSm),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: AppTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
      ),
    );
  }
}

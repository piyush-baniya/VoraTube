import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../providers/settings_providers.dart';

/// Premium storage info card widget.
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
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
      padding: const EdgeInsets.all(AppTokens.s5),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppTokens.rLg),
        border: Border.all(
          color: isDark
              ? AppColors.borderSubtleDark
              : AppColors.borderSubtleLight,
          width: AppTokens.borderHairline,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: AppTokens.s4),
          Text(
            'Loading storage info...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
      padding: const EdgeInsets.all(AppTokens.s5),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppTokens.rLg),
        border: Border.all(
          color: isDark
              ? AppColors.borderSubtleDark
              : AppColors.borderSubtleLight,
          width: AppTokens.borderHairline,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
          const SizedBox(width: AppTokens.s3),
          Text(
            'Storage info unavailable',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildData(BuildContext context, StorageInfo info) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppTokens.rLg),
        border: Border.all(
          color: isDark
              ? AppColors.borderSubtleDark
              : AppColors.borderSubtleLight,
          width: AppTokens.borderHairline,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.storage_rounded,
            label: 'Total Storage',
            value: info.totalSize,
            iconColor: colorScheme.primary,
          ),
          _PremiumDivider(),
          _InfoRow(
            icon: Icons.data_object_rounded,
            label: 'Database',
            value: info.databaseSize,
            iconColor: colorScheme.primary.withValues(alpha: 0.8),
          ),
          _PremiumDivider(),
          _InfoRow(
            icon: Icons.image_rounded,
            label: 'Artwork Cache',
            value: info.artworkCacheSize,
            iconColor: colorScheme.secondary,
          ),
          _PremiumDivider(),
          _InfoRow(
            icon: Icons.music_note_rounded,
            label: 'Imported Music',
            value: info.importedMusicSize,
            iconColor: colorScheme.tertiary,
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
        horizontal: AppTokens.s5,
        vertical: AppTokens.s3,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppTokens.rMd),
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: AppTokens.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
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

class _PremiumDivider extends StatelessWidget {
  const _PremiumDivider();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s5 + 44 + AppTokens.s4,
      ),
      child: Divider(
        height: AppTokens.borderHairline,
        thickness: AppTokens.borderHairline,
        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        indent: 0,
        endIndent: 0,
      ),
    );
  }
}

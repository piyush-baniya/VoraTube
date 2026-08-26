import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_tokens.dart';
import '../../../../../core/player/player_controller.dart';
import '../../../../../features/library/data/song_ref_mapper.dart';
import '../../../../../features/player/presentation/providers/player_providers.dart';
import '../../../../../shared/widgets/pressable_scale.dart';
import '../../data/smart_mix_service.dart';
import '../screens/smart_mix_detail_screen.dart';

class MixCard extends ConsumerWidget {
  const MixCard({
    super.key,
    required this.mix,
    this.onTap,
    this.onPlay,
    this.onShuffle,
  });

  final SmartMix mix;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (icon, gradientColors) = _getMixStyle(mix.kind);

    return PressableScale(
      onTap: onTap ?? () => _navigateToMix(context),
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(AppTokens.s3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.rMd),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 22, color: colorScheme.onSurfaceVariant),
                const Spacer(),
                if (mix.songs.isNotEmpty)
                  Text(
                    '${mix.songs.length} songs',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            if (mix.artworkPaths.isNotEmpty) ...[
              SizedBox(
                height: 64,
                child: Stack(
                  children: mix.artworkPaths.take(4).map((path) {
                    final index = mix.artworkPaths.indexOf(path);
                    return Positioned(
                      left: (index * 16).toDouble(),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppTokens.rSm),
                        child: Image.asset(
                          path,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) =>
                              _buildArtworkFallback(colorScheme),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: AppTokens.s2),
            ] else ...[
              _buildArtworkFallback(colorScheme),
              const SizedBox(height: AppTokens.s2),
            ],
            Text(
              mix.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              mix.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTokens.s2),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        onPlay ?? () => _playMix(context, ref, shuffle: false),
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: const Text('Play'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                ),
                const SizedBox(width: AppTokens.s1),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        onShuffle ??
                        () => _playMix(context, ref, shuffle: true),
                    icon: const Icon(Icons.shuffle_rounded, size: 16),
                    label: const Text('Shuffle'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtworkFallback(ColorScheme colorScheme) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.rSm),
        gradient: LinearGradient(
          colors: [
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 28,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  (IconData, List<Color>) _getMixStyle(SmartMixKind kind) {
    switch (kind) {
      case SmartMixKind.dailyMix:
        return (
          Icons.auto_awesome_mosaic,
          [
            const Color(0xFF6366F1).withValues(alpha: 0.25),
            const Color(0xFF8B5CF6).withValues(alpha: 0.1),
          ],
        );
      case SmartMixKind.favoritesMix:
        return (
          Icons.favorite_rounded,
          [
            const Color(0xFFEC4899).withValues(alpha: 0.25),
            const Color(0xFFF43F5E).withValues(alpha: 0.1),
          ],
        );
      case SmartMixKind.chillMix:
        return (
          Icons.spa_rounded,
          [
            const Color(0xFF14B8A6).withValues(alpha: 0.25),
            const Color(0xFF0D9488).withValues(alpha: 0.1),
          ],
        );
      case SmartMixKind.energyMix:
        return (
          Icons.flash_on_rounded,
          [
            const Color(0xFFF59E0B).withValues(alpha: 0.25),
            const Color(0xFFF97316).withValues(alpha: 0.1),
          ],
        );
      case SmartMixKind.focusMix:
        return (
          Icons.center_focus_strong_rounded,
          [
            const Color(0xFF3B82F6).withValues(alpha: 0.25),
            const Color(0xFF2563EB).withValues(alpha: 0.1),
          ],
        );
      case SmartMixKind.throwbackMix:
        return (
          Icons.history_rounded,
          [
            const Color(0xFF8B5CF6).withValues(alpha: 0.25),
            const Color(0xFF7C3AED).withValues(alpha: 0.1),
          ],
        );
      case SmartMixKind.discoverMix:
        return (
          Icons.explore_rounded,
          [
            const Color(0xFF06B6D4).withValues(alpha: 0.25),
            const Color(0xFF0891B2).withValues(alpha: 0.1),
          ],
        );
    }
  }

  void _navigateToMix(BuildContext context) {
    Navigator.of(context).push(_SmartMixRoute(mix: mix));
  }

  void _playMix(BuildContext context, WidgetRef ref, {required bool shuffle}) {
    final player = ref.read(playerProvider);
    final songs = mix.songs.map((t) => songTileToRef(t)).toList();

    if (songs.isEmpty) return;

    if (shuffle) {
      final shuffled = List<SongRef>.from(songs)..shuffle();
      player.playQueue(shuffled);
    } else {
      player.playQueue(songs);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          shuffle ? 'Playing ${mix.title} (shuffled)' : 'Playing ${mix.title}',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _SmartMixRoute extends PageRouteBuilder {
  final SmartMix mix;

  _SmartMixRoute({required this.mix})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            SmartMixDetailScreen(mix: mix),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 280),
      );
}

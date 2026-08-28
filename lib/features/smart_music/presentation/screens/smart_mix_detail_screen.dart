import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_tokens.dart';
import '../../../../../core/ingest/artwork/artwork_file_cache.dart';
import '../../../../../core/player/player_controller.dart';
import '../../../../../features/library/data/library_models.dart';
import '../../../../../features/library/data/song_ref_mapper.dart';
import '../../../../../features/library/presentation/widgets/song_actions.dart';
import '../../../../../features/player/presentation/providers/player_providers.dart';
import '../../data/smart_mix_service.dart';

class SmartMixDetailScreen extends ConsumerStatefulWidget {
  const SmartMixDetailScreen({super.key, required this.mix});

  final SmartMix mix;

  @override
  ConsumerState<SmartMixDetailScreen> createState() =>
      _SmartMixDetailScreenState();
}

class _SmartMixDetailScreenState extends ConsumerState<SmartMixDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (icon, gradientColors) = _getMixStyle(widget.mix.kind);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.mix.artworkPaths.isNotEmpty &&
                      ArtworkFileCache.resolve(widget.mix.artworkPaths.first) !=
                          null)
                    Image.file(
                      ArtworkFileCache.resolve(widget.mix.artworkPaths.first)!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      cacheWidth: ArtworkFileCache.decodeWidth(
                        320,
                        MediaQuery.devicePixelRatioOf(context),
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: gradientColors,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          icon,
                          size: 80,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          colorScheme.surface.withValues(alpha: 0.8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              titlePadding: const EdgeInsets.only(
                left: AppTokens.s4,
                right: AppTokens.s4,
                bottom: AppTokens.s4,
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: AppTokens.s1),
                      Text(
                        widget.mix.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    widget.mix.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.s4),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.mix.songs.isEmpty
                          ? null
                          : () => _playMix(shuffle: false),
                      icon: const Icon(Icons.play_arrow_rounded, size: 22),
                      label: const Text('Play'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTokens.s3),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.mix.songs.isEmpty
                          ? null
                          : () => _playMix(shuffle: true),
                      icon: const Icon(Icons.shuffle_rounded, size: 22),
                      label: const Text('Shuffle'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.s4,
                AppTokens.s2,
                AppTokens.s4,
                0,
              ),
              child: Row(
                children: [
                  Text(
                    '${widget.mix.songs.length} songs',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Generated ${_formatDate(widget.mix.generatedAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList.separated(
            itemCount: widget.mix.songs.length,
            separatorBuilder: (_, __) => Divider(
              height: 0.5,
              indent: 80,
              endIndent: AppTokens.s4,
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
            itemBuilder: (context, index) {
              final tile = widget.mix.songs[index];
              return _MixSongTile(
                tile: tile,
                index: index,
                onTap: () => _playFromIndex(index),
              );
            },
          ),
        ],
      ),
    );
  }

  (IconData, List<Color>) _getMixStyle(SmartMixKind kind) {
    switch (kind) {
      case SmartMixKind.dailyMix:
        return (
          Icons.auto_awesome_mosaic,
          [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
        );
      case SmartMixKind.favoritesMix:
        return (
          Icons.favorite_rounded,
          [const Color(0xFFEC4899), const Color(0xFFF43F5E)],
        );
      case SmartMixKind.chillMix:
        return (
          Icons.spa_rounded,
          [const Color(0xFF14B8A6), const Color(0xFF0D9488)],
        );
      case SmartMixKind.energyMix:
        return (
          Icons.flash_on_rounded,
          [const Color(0xFFF59E0B), const Color(0xFFF97316)],
        );
      case SmartMixKind.focusMix:
        return (
          Icons.center_focus_strong_rounded,
          [const Color(0xFF3B82F6), const Color(0xFF2563EB)],
        );
      case SmartMixKind.happyMix:
        return (
          Icons.celebration_rounded,
          [const Color(0xFF8B5CF6), const Color(0xFF6D28D9)],
        );
      case SmartMixKind.sadMix:
        return (
          Icons.mood_bad_rounded,
          [const Color(0xFF6366F1), const Color(0xFF4338CA)],
        );
      case SmartMixKind.romanticMix:
        return (
          Icons.favorite_border_rounded,
          [const Color(0xFFEC4899), const Color(0xFFDB2777)],
        );
      case SmartMixKind.throwbackMix:
        return (
          Icons.history_rounded,
          [const Color(0xFF8B5CF6), const Color(0xFF7C3AED)],
        );
      case SmartMixKind.discoverMix:
        return (
          Icons.explore_rounded,
          [const Color(0xFF06B6D4), const Color(0xFF0891B2)],
        );
    }
  }

  void _playMix({required bool shuffle}) {
    final player = ref.read(playerProvider);
    final songs = widget.mix.songs.map((t) => songTileToRef(t)).toList();

    if (songs.isEmpty) return;

    if (shuffle) {
      final shuffled = List<SongRef>.from(songs)..shuffle();
      player.playQueue(shuffled);
    } else {
      player.playQueue(songs);
    }
  }

  void _playFromIndex(int index) {
    final player = ref.read(playerProvider);
    final songs = widget.mix.songs.map((t) => songTileToRef(t)).toList();
    player.playQueue(songs, startIndex: index);
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

class _MixSongTile extends ConsumerWidget {
  const _MixSongTile({
    required this.tile,
    required this.index,
    required this.onTap,
  });

  final SongTileData tile;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s2,
        ),
        child: Row(
          children: [
            Text(
              '${index + 1}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: AppTokens.s3),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTokens.rSm),
              child: (() {
                final file = ArtworkFileCache.resolve(tile.artPath);
                if (file != null) {
                  return Image.file(
                    file,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    cacheWidth: ArtworkFileCache.decodeWidth(
                      48,
                      MediaQuery.devicePixelRatioOf(context),
                    ),
                    errorBuilder: (_, __, ___) => Container(
                      width: 48,
                      height: 48,
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.music_note_rounded,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                  );
                }
                return Container(
                  width: 48,
                  height: 48,
                  color: colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.music_note_rounded,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  ),
                );
              })(),
            ),
            const SizedBox(width: AppTokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tile.song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (tile.song.artist != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      tile.song.artist!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Consistent three-dot song menu with the rest of the app.
            IconButton(
              tooltip: 'More options',
              onPressed: () => SongActions.show(context, ref, tile: tile),
              icon: Icon(
                Icons.more_vert_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: AppTokens.s1),
            Icon(
              Icons.play_circle_outline_rounded,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

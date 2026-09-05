import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../shared/widgets/transitions.dart';
import '../../../library/presentation/providers/library_view_providers.dart';
import '../../data/playlist_models.dart';
import '../providers/playlist_providers.dart';
import '../screens/playlist_detail_screen.dart';
import 'playlist_collage.dart';
import 'playlist_context_menu.dart';

/// Home dashboard section showing the user's playlists with a Create action.
///
/// Consumes the exact same [playlistsOverviewProvider] as the Playlists tab —
/// no second playlist system. Tapping a card opens the existing
/// [PlaylistDetailScreen]; the Create action uses the shared
/// [promptCreatePlaylist] flow.
class HomePlaylistStrip extends ConsumerWidget {
  const HomePlaylistStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // With no music on the device there is nothing a playlist could hold, so
    // the strip (including its Create CTA) is hidden and the "No Music" empty
    // state leads instead. "Loading" defaults to visible to avoid a flash.
    final hasSongs = ref.watch(libraryHasSongsProvider).valueOrNull ?? true;
    if (!hasSongs) {
      return const SizedBox.shrink();
    }
    final async = ref.watch(playlistsOverviewProvider);

    return async.when(
      skipLoadingOnRefresh: true,
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (playlists) {
        if (playlists.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionLabel(
                title: 'Playlists',
                trailing: _buildCreateButton(context, ref),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
                child: PressableScale(
                  onTap: () => promptCreatePlaylist(context, ref),
                  child: Container(
                    padding: const EdgeInsets.all(AppTokens.s4),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppTokens.rLg),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.3,
                        ),
                        width: AppTokens.borderHairline,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppTokens.rMd),
                          ),
                          child: Icon(
                            Icons.queue_music_rounded,
                            size: 28,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: AppTokens.s4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'No playlists yet',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Create your first playlist to organize '
                                'your music.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(
              title: 'Playlists',
              trailing: _buildCreateButton(context, ref),
            ),
            SizedBox(
              height: 176,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
                itemCount: playlists.length,
                separatorBuilder: (_, _) => const SizedBox(width: AppTokens.s3),
                itemBuilder: (context, index) =>
                    _HomePlaylistCard(playlist: playlists[index]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCreateButton(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return PressableScale(
      onTap: () => promptCreatePlaylist(context, ref),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_rounded, size: 18, color: colorScheme.primary),
          const SizedBox(width: 2),
          Text(
            'Create',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomePlaylistCard extends ConsumerWidget {
  const _HomePlaylistCard({required this.playlist});

  final PlaylistSummary playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return PressableScale(
      onTap: () => Navigator.of(context).push(
        pushSharedAxis<void>(
          context,
          PlaylistDetailScreen(playlistId: playlist.id, name: playlist.name),
        ),
      ),
      // Long-press shows the same context menu as the Playlists tab cards.
      onLongPress: () => showPlaylistContextMenu(context, ref, playlist),
      child: Container(
        width: 148,
        padding: const EdgeInsets.all(AppTokens.s3),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppTokens.rLg),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: AppTokens.borderHairline,
          ),
          // A soft shadow lifts the card off the surface. Light mode needs a
          // little extra depth here (near-white surface vs. warm paper), so we
          // strengthen the shadow only outside dark mode.
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.08 : 0.16),
              blurRadius: 14,
              offset: const Offset(0, 3),
              spreadRadius: -1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlaylistCollage(
              summary: playlist,
              size: 104,
              radius: AppTokens.rMd,
            ),
            const SizedBox(height: AppTokens.s2),
            Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            // The count flexes so fixed strip heights never overflow while
            // still fitting at large text scales.
            Flexible(
              child: Text(
                '${playlist.songCount} ${playlist.songCount == 1 ? 'song' : 'songs'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

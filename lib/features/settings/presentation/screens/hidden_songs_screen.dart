import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../shared/widgets/artwork_view.dart';
import '../../../../shared/widgets/empty_state.dart' show EmptyState;
import '../../../library/data/library_models.dart';
import '../../../library/data/library_repository.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../../../library/presentation/providers/library_view_providers.dart';

/// Settings → "Show Hidden Songs".
///
/// Lists every song the user hid via the song overflow menu ("Hide song") so
/// they can be restored. The normal browsing queries exclude these rows, so
/// this screen is the only place they surface.
///
/// Unhiding a song bumps [libraryRefreshTickProvider] and invalidates the
/// paged song list, so the song reappears immediately in the Library and Home
/// without a restart.
class HiddenSongsScreen extends ConsumerWidget {
  const HiddenSongsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hiddenSongsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Hidden Songs',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: async.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load hidden songs',
          message: 'Go back and try again.',
        ),
        data: (tiles) {
          if (tiles.isEmpty) {
            return const EmptyState(
              icon: Icons.visibility_off_rounded,
              title: 'No hidden songs',
              message:
                  'Songs you hide from the three-dot menu will appear here so '
                  'you can show them again.',
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.s4,
                  AppTokens.s3,
                  AppTokens.s4,
                  AppTokens.s1,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${tiles.length} hidden '
                        '${tiles.length == 1 ? 'song' : 'songs'}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _showAll(context, ref),
                      icon: const Icon(Icons.visibility_rounded, size: 18),
                      label: const Text('Show all'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: tiles.length,
                  separatorBuilder: (_, _) => Divider(
                    height: AppTokens.borderHairline,
                    thickness: AppTokens.borderHairline,
                    indent: AppTokens.artworkLg + AppTokens.s3 + AppTokens.s4,
                    endIndent: AppTokens.s4,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  itemBuilder: (context, index) {
                    final tile = tiles[index];
                    return _HiddenSongTile(
                      tile: tile,
                      onShow: () =>
                          _unhide(context, ref, tile.song.id, tile.song.title),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _unhide(
    BuildContext context,
    WidgetRef ref,
    int songId,
    String title,
  ) async {
    final repo = ref.read(libraryRepositoryProvider);
    try {
      await repo.setHidden(songId, false);
      ref.invalidate(pagedSongsProvider);
      ref.read(libraryRefreshTickProvider.notifier).state++;
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('"$title" is visible again')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not show this song')),
        );
      }
    }
  }

  Future<void> _showAll(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(libraryRepositoryProvider);
    try {
      await repo.clearHidden();
      ref.invalidate(pagedSongsProvider);
      ref.read(libraryRefreshTickProvider.notifier).state++;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All hidden songs are visible again')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not show songs')));
      }
    }
  }
}

class _HiddenSongTile extends StatelessWidget {
  const _HiddenSongTile({required this.tile, required this.onShow});

  final SongTileData tile;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final song = tile.song;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s4,
        vertical: AppTokens.s1,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Row(
          children: [
            ArtworkView(
              path: tile.artPath,
              size: AppTokens.artworkLg,
              radius: AppTokens.rSm,
            ),
            const SizedBox(width: AppTokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist ?? song.albumName ?? '\u2014',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTokens.s2),
            TextButton.icon(
              onPressed: onShow,
              icon: const Icon(Icons.visibility_rounded, size: 18),
              label: const Text('Show'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

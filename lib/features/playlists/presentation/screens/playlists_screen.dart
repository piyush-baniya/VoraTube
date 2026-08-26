import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/screen_header.dart';
import '../../../../shared/widgets/transitions.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../data/playlist_models.dart';
import '../providers/playlist_providers.dart';
import '../widgets/playlist_collage.dart';
import 'playlist_detail_screen.dart';

class PlaylistsScreen extends ConsumerStatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  ConsumerState<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends ConsumerState<PlaylistsScreen> {
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(playlistsOverviewProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: 'Playlists',
            trailing: IconButton(
              tooltip: 'New playlist',
              onPressed: () => _showCreateDialog(context, ref),
              icon: const Icon(Icons.add_rounded, size: 26),
            ),
          ),
          Expanded(
            child: async.when(
              skipLoadingOnRefresh: true,
              loading: () => const _LoadingSkeleton(),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Could not load playlists',
                message: 'Try again in a moment.',
                actionLabel: 'Retry',
                onAction: () => ref.invalidate(playlistsOverviewProvider),
              ),
              data: (playlists) {
                if (playlists.isEmpty) {
                  return EmptyState(
                    icon: Icons.queue_music_rounded,
                    title: 'No playlists yet',
                    message:
                        'Create your first playlist to organize your music.',
                    actionLabel: 'Create playlist',
                    onAction: () => _showCreateDialog(context, ref),
                  );
                }
                return _PlaylistList(playlists: playlists);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'Playlist name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && context.mounted) {
      try {
        final repository = ref.read(playlistRepositoryProvider);
        final id = await repository.createPlaylist(result);
        ref.read(playlistRefreshTickProvider.notifier).state++;
        if (context.mounted) {
          Navigator.of(context).push(
            pushSharedAxis<void>(
              context,
              PlaylistDetailScreen(playlistId: id, name: result),
            ),
          );
        }
      } on DuplicatePlaylistNameException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }
  }
}

class _PlaylistList extends StatelessWidget {
  const _PlaylistList({required this.playlists});

  final List<PlaylistSummary> playlists;

  @override
  Widget build(BuildContext context) {
    final pinned = playlists.where((p) => p.pinned).toList();
    final unpinned = playlists.where((p) => !p.pinned).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (pinned.isNotEmpty) ...[
          const SectionLabel(title: 'Pinned'),
          for (final p in pinned) _PlaylistTile(playlist: p),
        ],
        if (pinned.isNotEmpty && unpinned.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.s5,
              AppTokens.s3,
              AppTokens.s5,
              AppTokens.s1,
            ),
            child: Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        if (unpinned.isNotEmpty) ...[
          if (pinned.isEmpty) const SectionLabel(title: 'All'),
          for (final p in unpinned) _PlaylistTile(playlist: p),
        ],
      ],
    );
  }
}

class _PlaylistTile extends ConsumerWidget {
  const _PlaylistTile({required this.playlist});

  final PlaylistSummary playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dismissible(
      key: ValueKey('playlist-${playlist.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: colorScheme.error,
        child: Icon(Icons.delete_rounded, color: colorScheme.onError),
      ),
      confirmDismiss: (_) async {
        return showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete playlist?'),
            content: Text('"${playlist.name}" will be permanently deleted.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) async {
        final repository = ref.read(playlistRepositoryProvider);
        await repository.deletePlaylist(playlist.id);
        ref.read(playlistRefreshTickProvider.notifier).state++;
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('"${playlist.name}" deleted')));
        }
      },
      child: PressableScale(
        onTap: () => Navigator.of(context).push(
          pushSharedAxis<void>(
            context,
            PlaylistDetailScreen(playlistId: playlist.id, name: playlist.name),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s5,
            vertical: AppTokens.s1,
          ),
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                PlaylistCollage(
                  summary: playlist,
                  size: 52,
                  radius: AppTokens.rSm,
                ),
                const SizedBox(width: AppTokens.s3),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${playlist.songCount} ${playlist.songCount == 1 ? 'song' : 'songs'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (playlist.pinned)
                  Icon(
                    Icons.push_pin_rounded,
                    size: 14,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                const SizedBox(width: AppTokens.s1),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHigh;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s5,
        vertical: AppTokens.s2,
      ),
      itemCount: 6,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.s1),
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppTokens.rSm),
                ),
              ),
              const SizedBox(width: AppTokens.s3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 13,
                      width: 100 + (i * 20).toDouble(),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 10,
                      width: 60,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

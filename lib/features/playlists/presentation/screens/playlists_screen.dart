import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/empty_state.dart'
    show EmptyState, ScreenHeader;
import '../../../../shared/widgets/transitions.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../data/playlist_models.dart';
import '../providers/playlist_providers.dart';
import '../widgets/playlist_collage.dart';
import 'playlist_detail_screen.dart';
import '../../../../features/library/data/song_ref_mapper.dart';
import '../../../smart_music/presentation/widgets/mood_strip.dart';
import '../../../smart_music/presentation/widgets/smart_mix_strip.dart';

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
            trailing: PressableScale(
              onTap: () => _showCreateDialog(context, ref),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add_rounded,
                  size: 24,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
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
              data: (playlists) => _PlaylistList(
                playlists: playlists,
                onCreate: () => _showCreateDialog(context, ref),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final created = await promptCreatePlaylist(context, ref);
    if (created != null && context.mounted) {
      Navigator.of(context).push(
        pushSharedAxis<void>(
          context,
          PlaylistDetailScreen(playlistId: created.id, name: created.name),
        ),
      );
    }
  }
}

class _PlaylistList extends StatelessWidget {
  const _PlaylistList({required this.playlists, required this.onCreate});

  final List<PlaylistSummary> playlists;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final pinned = playlists.where((p) => p.pinned).toList();
    final unpinned = playlists.where((p) => !p.pinned).toList();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return CustomScrollView(
      slivers: [
        // Smart Mood + recommended mixes, clearly distinct from the
        // user-created playlists listed below.
        const SliverToBoxAdapter(child: MoodStrip()),
        const SliverToBoxAdapter(child: SmartMixStrip()),
        if (playlists.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.queue_music_rounded,
              title: 'No playlists yet',
              message: 'Create your first playlist to organize your music.',
              actionLabel: 'Create playlist',
              onAction: onCreate,
            ),
          )
        else ...[
          if (pinned.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.s5,
                  AppTokens.s4,
                  AppTokens.s5,
                  AppTokens.s2,
                ),
                child: Text(
                  'Pinned',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            SliverList.separated(
              itemCount: pinned.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppTokens.s2),
              itemBuilder: (context, index) =>
                  _PlaylistCard(playlist: pinned[index]),
            ),
          ],
          if (unpinned.isNotEmpty) ...[
            if (pinned.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.s5,
                    AppTokens.s4,
                    AppTokens.s5,
                    AppTokens.s2,
                  ),
                  child: Divider(
                    height: AppTokens.borderHairline,
                    thickness: AppTokens.borderHairline,
                    color: colorScheme.outlineVariant,
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.s5,
                  AppTokens.s4,
                  AppTokens.s5,
                  AppTokens.s2,
                ),
                child: Text(
                  'All Playlists',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            SliverList.separated(
              itemCount: unpinned.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppTokens.s2),
              itemBuilder: (context, index) =>
                  _PlaylistCard(playlist: unpinned[index]),
            ),
          ],
        ],
        // Bottom padding for MiniPlayer
        SliverToBoxAdapter(child: SizedBox(height: AppTokens.s10)),
      ],
    );
  }
}

class _PlaylistCard extends ConsumerWidget {
  const _PlaylistCard({required this.playlist});

  final PlaylistSummary playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Dismissible(
      key: ValueKey('playlist-${playlist.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s1,
        ),
        decoration: BoxDecoration(
          color: colorScheme.error,
          borderRadius: BorderRadius.circular(AppTokens.rMd),
        ),
        child: Icon(Icons.delete_rounded, color: colorScheme.onError, size: 28),
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
        onLongPress: () => _showContextMenu(context, ref),
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppTokens.s4,
            vertical: AppTokens.s1,
          ),
          padding: const EdgeInsets.all(AppTokens.s3),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTokens.rLg),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: AppTokens.borderHairline,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
                spreadRadius: -4,
              ),
            ],
          ),
          child: Row(
            children: [
              // Playlist collage artwork
              PlaylistCollage(
                summary: playlist,
                size: 64,
                radius: AppTokens.rMd,
              ),
              const SizedBox(width: AppTokens.s4),
              // Playlist info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (playlist.pinned)
                          Container(
                            margin: const EdgeInsets.only(left: AppTokens.s2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTokens.s2,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppTokens.rFull,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.push_pin_rounded,
                                  size: 12,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Pinned',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.s1),
                    Text(
                      '${playlist.songCount} ${playlist.songCount == 1 ? 'song' : 'songs'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.s2),
              // Play button
              PressableScale(
                onTap: () => _playPlaylist(context, ref),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 20,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.s2),
              // More menu
              PressableScale(
                onTap: () => _showContextMenu(context, ref),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.more_vert_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _playPlaylist(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerProvider);
    final repository = ref.read(playlistRepositoryProvider);
    final songsFuture = repository.songsOf(playlist.id);
    songsFuture.then((songs) {
      if (songs.isNotEmpty && context.mounted) {
        player.playQueue([
          for (final s in songs) songTileToRef(s),
        ], startIndex: 0);
      }
    });
  }

  void _showContextMenu(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTokens.rXxl),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: AppTokens.s3),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppTokens.s5),
                  child: Row(
                    children: [
                      PlaylistCollage(
                        summary: playlist,
                        size: 56,
                        radius: AppTokens.rMd,
                      ),
                      const SizedBox(width: AppTokens.s4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              playlist.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${playlist.songCount} ${playlist.songCount == 1 ? 'song' : 'songs'}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: colorScheme.outlineVariant,
                  indent: AppTokens.s5,
                  endIndent: AppTokens.s5,
                ),
                _ContextMenuTile(
                  icon: Icons.play_arrow_rounded,
                  label: 'Play',
                  onTap: () {
                    Navigator.pop(context);
                    _playPlaylist(context, ref);
                  },
                ),
                _ContextMenuTile(
                  icon: Icons.shuffle_rounded,
                  label: 'Shuffle play',
                  onTap: () {
                    Navigator.pop(context);
                    _playPlaylist(context, ref);
                  },
                ),
                _ContextMenuTile(
                  icon: playlist.pinned
                      ? Icons.push_pin_outlined
                      : Icons.push_pin_rounded,
                  label: playlist.pinned ? 'Unpin' : 'Pin to top',
                  iconColor: playlist.pinned
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.primary,
                  onTap: () {
                    Navigator.pop(context);
                    ref
                        .read(playlistRepositoryProvider)
                        .setPinned(playlist.id, !playlist.pinned);
                    ref.read(playlistRefreshTickProvider.notifier).state++;
                  },
                ),
                _ContextMenuTile(
                  icon: Icons.edit_rounded,
                  label: 'Rename',
                  onTap: () {
                    Navigator.pop(context);
                    _showRenameDialog(context, ref);
                  },
                ),
                _ContextMenuTile(
                  icon: Icons.content_copy_rounded,
                  label: 'Duplicate',
                  onTap: () {
                    Navigator.pop(context);
                    _duplicatePlaylist(context, ref);
                  },
                ),
                _ContextMenuTile(
                  icon: Icons.delete_rounded,
                  label: 'Delete',
                  iconColor: colorScheme.error,
                  labelColor: colorScheme.error,
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDelete(context, ref);
                  },
                ),
                SizedBox(
                  height: MediaQuery.paddingOf(context).bottom + AppTokens.s4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDialog(
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
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true && context.mounted) {
        _deletePlaylist(context, ref);
      }
    });
  }

  void _deletePlaylist(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(playlistRepositoryProvider);
    await repository.deletePlaylist(playlist.id);
    ref.read(playlistRefreshTickProvider.notifier).state++;
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('"${playlist.name}" deleted')));
    }
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename playlist'),
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
            child: const Text('Rename'),
          ),
        ],
      ),
    ).then((newName) {
      if (newName != null &&
          newName.isNotEmpty &&
          newName != playlist.name &&
          context.mounted) {
        ref
            .read(playlistRepositoryProvider)
            .renamePlaylist(playlist.id, newName)
            .then((_) {
              // Refresh on the next frame so the overview provider is already
              // updated before the UI rebuilds.
            })
            .catchError((_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('A playlist with that name already exists.'),
                  ),
                );
              }
            });
        ref.read(playlistRefreshTickProvider.notifier).state++;
      }
    });
  }

  void _duplicatePlaylist(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(playlistRepositoryProvider);
    final newName = '${playlist.name} (Copy)';
    try {
      final newId = await repository.createPlaylist(newName);
      await repository.addSongs(
        newId,
        (await repository.songsOf(playlist.id)).map((s) => s.song.id).toList(),
      );
      ref.read(playlistRefreshTickProvider.notifier).state++;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playlist duplicated as "$newName"')),
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

class _ContextMenuTile extends StatelessWidget {
  const _ContextMenuTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.labelColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PressableScale(
      onTap: onTap,
      child: ListTile(
        leading: Icon(
          icon,
          size: 22,
          color: iconColor ?? colorScheme.onSurfaceVariant,
        ),
        title: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: labelColor ?? colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s5,
          vertical: 0,
        ),
        dense: true,
        onTap: onTap,
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
        horizontal: AppTokens.s4,
        vertical: AppTokens.s2,
      ),
      itemCount: 6,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4,
          vertical: AppTokens.s1,
        ),
        child: Container(
          padding: const EdgeInsets.all(AppTokens.s3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppTokens.rLg),
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppTokens.rMd),
                ),
              ),
              const SizedBox(width: AppTokens.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 15,
                      width: 100 + (i * 20).toDouble(),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 11,
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

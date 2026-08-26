import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../data/playlist_models.dart';
import '../../data/playlist_repository.dart';
import '../providers/playlist_providers.dart';

/// Shows a bottom sheet listing all playlists, with checkmarks for
/// membership. Returns true if any playlist was modified.
Future<bool> showAddToPlaylistSheet(BuildContext context, int songRowId) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AddToPlaylistBody(songRowId: songRowId),
  );
  return result ?? false;
}

class _AddToPlaylistBody extends ConsumerStatefulWidget {
  const _AddToPlaylistBody({required this.songRowId});

  final int songRowId;

  @override
  ConsumerState<_AddToPlaylistBody> createState() => _AddToPlaylistBodyState();
}

class _AddToPlaylistBodyState extends ConsumerState<_AddToPlaylistBody> {
  bool _modified = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final playlistsAsync = ref.watch(playlistsOverviewProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar.
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: AppTokens.s3),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.s5,
                AppTokens.s4,
                AppTokens.s5,
                AppTokens.s2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Add to playlist',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'New playlist',
                    onPressed: () => _showCreateDialog(context),
                    icon: const Icon(Icons.add_rounded, size: 24),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            Expanded(
              child: playlistsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                error: (e, _) =>
                    const Center(child: Text('Could not load playlists.')),
                data: (playlists) {
                  if (playlists.isEmpty) {
                    return Center(
                      child: Text(
                        'No playlists yet.\nCreate one using the + button.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  return _MembershipList(
                    playlists: playlists,
                    songRowId: widget.songRowId,
                    scrollController: scrollController,
                    onChanged: () => _modified = true,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
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
        await repository.createPlaylist(result);
        ref.read(playlistRefreshTickProvider.notifier).state++;
      } on DuplicatePlaylistNameException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }
  }
}

class _MembershipList extends ConsumerStatefulWidget {
  const _MembershipList({
    required this.playlists,
    required this.songRowId,
    required this.scrollController,
    required this.onChanged,
  });

  final List<PlaylistSummary> playlists;
  final int songRowId;
  final ScrollController scrollController;
  final VoidCallback onChanged;

  @override
  ConsumerState<_MembershipList> createState() => _MembershipListState();
}

class _MembershipListState extends ConsumerState<_MembershipList> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView.builder(
      controller: widget.scrollController,
      itemCount: widget.playlists.length,
      itemBuilder: (context, index) {
        final playlist = widget.playlists[index];
        final membershipAsync = ref.watch(
          playlistMembershipProvider(playlist.id),
        );

        return membershipAsync.when(
          loading: () => ListTile(
            leading: _PlaylistIcon(colorScheme: colorScheme),
            title: Text(playlist.name),
            trailing: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, __) => ListTile(
            leading: _PlaylistIcon(colorScheme: colorScheme),
            title: Text(playlist.name),
          ),
          data: (memberIds) {
            final isMember = memberIds.contains(widget.songRowId);
            return ListTile(
              leading: _PlaylistIcon(colorScheme: colorScheme),
              title: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${playlist.songCount} ${playlist.songCount == 1 ? 'song' : 'songs'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Icon(
                isMember
                    ? Icons.check_circle_rounded
                    : Icons.add_circle_outline_rounded,
                color: isMember
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                size: 24,
              ),
              onTap: () => _toggle(playlist, isMember),
            );
          },
        );
      },
    );
  }

  Future<void> _toggle(PlaylistSummary playlist, bool isMember) async {
    final repository = ref.read(playlistRepositoryProvider);
    try {
      if (isMember) {
        await _removeSong(repository, playlist);
      } else {
        await _addSong(repository, playlist);
      }
      widget.onChanged();
      ref.read(playlistRefreshTickProvider.notifier).state++;
      ref.invalidate(playlistMembershipProvider(playlist.id));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isMember
                  ? 'Could not remove from ${playlist.name}'
                  : 'Could not add to ${playlist.name}',
            ),
          ),
        );
      }
    }
  }

  Future<void> _addSong(
    PlaylistRepository repository,
    PlaylistSummary playlist,
  ) async {
    await repository.addSongs(playlist.id, [widget.songRowId]);
  }

  Future<void> _removeSong(
    PlaylistRepository repository,
    PlaylistSummary playlist,
  ) async {
    final songs = await repository.songsOf(playlist.id, limit: 1000);
    final index = songs.indexWhere((s) => s.song.id == widget.songRowId);
    if (index >= 0) {
      await repository.removeSongAt(playlist.id, index);
    }
  }
}

class _PlaylistIcon extends StatelessWidget {
  const _PlaylistIcon({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTokens.rSm),
      ),
      child: Icon(
        Icons.queue_music_rounded,
        size: 20,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
    );
  }
}

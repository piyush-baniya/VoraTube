import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../app/widgets/vora_snackbar.dart';
import '../../../library/data/song_ref_mapper.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../data/playlist_models.dart';
import '../providers/playlist_providers.dart';
import 'playlist_collage.dart';

/// Queues every song of [playlist] into the player, optionally shuffled.
/// Shared by the Playlists tab cards and the Home strip cards so both entry
/// points behave identically.
Future<void> queuePlaylistSongs(
  BuildContext context,
  WidgetRef ref,
  PlaylistSummary playlist, {
  required bool shuffle,
}) async {
  final repository = ref.read(playlistRepositoryProvider);
  final songs = await repository.songsOf(playlist.id);
  if (songs.isEmpty || !context.mounted) return;
  // With shuffle the whole queue is randomised in full (starting song
  // included) so Shuffle never starts at the list head like Play. The
  // player's shuffled mode is toggled to match, keeping Next/Previous
  // semantics consistent with every other shuffle entry point.
  final playSongs = shuffle ? (List.of(songs)..shuffle()) : songs;
  await ref.read(playerProvider).setShuffle(shuffle);
  if (!context.mounted) return;
  ref
      .read(playerProvider)
      .playQueue([for (final s in playSongs) songTileToRef(s)], startIndex: 0);
}

/// Deletes [playlist] after an explicit confirmation dialog.
Future<void> confirmAndDeletePlaylist(
  BuildContext context,
  WidgetRef ref,
  PlaylistSummary playlist,
) async {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  final confirmed = await showDialog<bool>(
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
  );
  if (confirmed != true || !context.mounted) return;
  await ref.read(playlistRepositoryProvider).deletePlaylist(playlist.id);
  ref.read(playlistRefreshTickProvider.notifier).state++;
  if (context.mounted) {
    VoraSnackbar.success(
      context,
      '"${playlist.name}" was removed.',
      title: 'Playlist deleted',
    );
  }
}

/// Shows the shared "Rename playlist" dialog for [playlist].
Future<void> showPlaylistRenameDialog(
  BuildContext context,
  WidgetRef ref,
  PlaylistSummary playlist,
) async {
  final controller = TextEditingController(text: playlist.name);
  final newName = await showDialog<String>(
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
  );
  if (newName == null || newName.isEmpty || newName == playlist.name) return;
  if (!context.mounted) return;
  try {
    await ref
        .read(playlistRepositoryProvider)
        .renamePlaylist(playlist.id, newName);
    ref.read(playlistRefreshTickProvider.notifier).state++;
  } on DuplicatePlaylistNameException {
    if (context.mounted) {
      VoraSnackbar.error(
        context,
        'A playlist with that name already exists.',
        title: 'Couldn\'t rename playlist',
      );
    }
  }
}

/// Duplicates [playlist] (songs included) as `<name> (Copy)`.
Future<void> duplicatePlaylist(
  BuildContext context,
  WidgetRef ref,
  PlaylistSummary playlist,
) async {
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
      VoraSnackbar.success(
        context,
        'Playlist duplicated as "$newName"',
        title: 'Playlist duplicated',
      );
    }
  } on DuplicatePlaylistNameException {
    if (context.mounted) {
      VoraSnackbar.error(
        context,
        'A playlist with that name already exists.',
        title: 'Couldn\'t duplicate playlist',
      );
    }
  }
}

/// The full playlist context menu as a bottom sheet: Play, Shuffle play,
/// Pin/Unpin, Rename, Duplicate and Delete. Used by long-press (and the
/// ⋮ button) on playlist cards everywhere.
void showPlaylistContextMenu(
  BuildContext context,
  WidgetRef ref,
  PlaylistSummary playlist,
) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
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
                  Navigator.pop(sheetContext);
                  queuePlaylistSongs(context, ref, playlist, shuffle: false);
                },
              ),
              _ContextMenuTile(
                icon: Icons.shuffle_rounded,
                label: 'Shuffle play',
                onTap: () {
                  Navigator.pop(sheetContext);
                  queuePlaylistSongs(context, ref, playlist, shuffle: true);
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
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await ref
                      .read(playlistRepositoryProvider)
                      .setPinned(playlist.id, !playlist.pinned);
                  ref.read(playlistRefreshTickProvider.notifier).state++;
                },
              ),
              _ContextMenuTile(
                icon: Icons.edit_rounded,
                label: 'Rename',
                onTap: () {
                  Navigator.pop(sheetContext);
                  showPlaylistRenameDialog(context, ref, playlist);
                },
              ),
              _ContextMenuTile(
                icon: Icons.content_copy_rounded,
                label: 'Duplicate',
                onTap: () {
                  Navigator.pop(sheetContext);
                  duplicatePlaylist(context, ref, playlist);
                },
              ),
              _ContextMenuTile(
                icon: Icons.delete_rounded,
                label: 'Delete',
                iconColor: colorScheme.error,
                labelColor: colorScheme.error,
                onTap: () {
                  Navigator.pop(sheetContext);
                  confirmAndDeletePlaylist(context, ref, playlist);
                },
              ),
              SizedBox(
                height:
                    MediaQuery.paddingOf(sheetContext).bottom + AppTokens.s4,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ContextMenuTile extends StatelessWidget {
  const _ContextMenuTile({
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

    return ListTile(
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
    );
  }
}

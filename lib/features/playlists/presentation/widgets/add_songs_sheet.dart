import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../app/widgets/vora_snackbar.dart';
import '../../../../shared/widgets/artwork_view.dart';
import '../../../library/data/library_models.dart';
import '../../../library/presentation/providers/library_view_providers.dart';
import '../providers/playlist_providers.dart';

/// Opens a full-screen picker that edits which songs belong to a playlist.
///
/// Every row shows a contextual +/− action and the single `Select All` action
/// (in the app bar) ONLY change the LOCAL pending selection — nothing touches
/// the database while the user is picking. The one "Done" button at the bottom
/// commits the whole pending diff at once: songs selected but absent are
/// added, songs deselected but previously members are removed. Tapping the
/// app bar's back / pressing Back discards the pending changes entirely.
///
/// [playlistRefreshTickProvider] is bumped after a successful commit so the
/// playlist surfaces behind the sheet (detail screen, overviews) refresh
/// reactively; this screen closes back to the playlist.
Future<void> showAddSongsSheet(
  BuildContext context, {
  required int playlistId,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => AddSongsPickerScreen(playlistId: playlistId),
      fullscreenDialog: true,
    ),
  );
}

class AddSongsPickerScreen extends ConsumerStatefulWidget {
  const AddSongsPickerScreen({super.key, required this.playlistId});

  final int playlistId;

  @override
  ConsumerState<AddSongsPickerScreen> createState() =>
      _AddSongsPickerScreenState();
}

class _AddSongsPickerScreenState extends ConsumerState<AddSongsPickerScreen> {
  final ScrollController _controller = ScrollController();

  /// The playlist's membership (song row ids) captured when the screen opened.
  /// This is the diff baseline for the "Done" commit.
  Set<int> _originalIds = const <int>{};

  /// The membership the user wants by the time they finish picking. The UI
  /// renders purely from this (a song shows `-` when it is in this set, `+`
  /// when it is not), and "Done" diffs it against [_originalIds]. It mutates
  /// on every +/− or Select All tap WITHOUT touching the database.
  Set<int> _pendingIds = const <int>{};
  bool _membersLoaded = false;

  /// True while `Select All` is streaming the remaining pages of the picker
  /// dataset (an async, read-only operation).
  bool _applyingSelectAll = false;

  /// True while the "Done" commit is in flight; blocks re-entry and disables
  /// every picker action until the write resolves.
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _hydrateMembers();
  }

  Future<void> _hydrateMembers() async {
    try {
      final members = await ref.read(
        playlistMembershipProvider(widget.playlistId).future,
      );
      if (mounted) {
        setState(() {
          _originalIds = members;
          _pendingIds = members;
          _membersLoaded = true;
        });
      }
    } catch (_) {
      // A failed read still unlocks the screen; every action surfaces its own
      // failure, so an empty pending state is never presented as truth.
      if (mounted) {
        setState(() => _membersLoaded = true);
      }
    }
  }

  void _onScroll() {
    if (_controller.position.extentAfter < 600) {
      ref.read(pagedSongsProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Flips [tile]'s pending membership: selected becomes deselected and vice
  /// versa. Purely local state — no database write happens here.
  void _toggle(SongTileData tile) {
    final id = tile.song.id;
    setState(() {
      final next = {..._pendingIds};
      if (!next.remove(id)) next.add(id);
      _pendingIds = next;
    });
  }

  /// Marks every song in the picker dataset as selected for the playlist —
  /// pending-only, never a database write. Streams every page (Select All
  /// always means the WHOLE picker dataset, which matches the paginated
  /// library source: only the currently visible window when the list is
  /// short, every page streamed otherwise).
  Future<void> _selectAll() async {
    if (_applyingSelectAll || _committing) return;
    setState(() => _applyingSelectAll = true);
    try {
      final notifier = ref.read(pagedSongsProvider.notifier);
      while (notifier.hasMore) {
        await notifier.loadMore();
      }
      final tiles = ref.read(pagedSongsProvider).value;
      if (tiles == null || tiles.isEmpty) return;
      if (mounted) {
        setState(() {
          _pendingIds = {for (final t in tiles) t.song.id};
        });
      }
    } finally {
      if (mounted) {
        setState(() => _applyingSelectAll = false);
      }
    }
  }

  /// The single commit point: computes pending − original (adds) and original
  /// − pending (removes), applies them efficiently to the database, refreshes
  /// the playlist surfaces and closes the screen. Any error keeps the screen
  /// open with the pending selection intact so the user can retry or back out.
  Future<void> _done() async {
    if (!_membersLoaded || _committing) return;
    setState(() => _committing = true);
    try {
      final tiles =
          ref.read(pagedSongsProvider).value ?? const <SongTileData>[];
      final toAdd = <int>[
        for (final t in tiles)
          if (_pendingIds.contains(t.song.id) &&
              !_originalIds.contains(t.song.id))
            t.song.id,
      ];
      final toRemove = _originalIds.difference(_pendingIds);

      if (toAdd.isEmpty && toRemove.isEmpty) {
        if (mounted) Navigator.of(context).pop();
        return;
      }

      final repository = ref.read(playlistRepositoryProvider);
      await repository.addSongs(widget.playlistId, toAdd);
      if (toRemove.isNotEmpty) {
        await repository.removeSongs(widget.playlistId, toRemove);
      }

      _publishChange();
      if (mounted) {
        _showCommitResult(toAdd.length, toRemove.length);
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        VoraSnackbar.error(
          context,
          'Could not update the playlist. Please try again.',
          title: 'Playlist error',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _committing = false);
      }
    }
  }

  void _showCommitResult(int added, int removed) {
    if (added > 0 && removed > 0) {
      VoraSnackbar.success(
        context,
        'Added $added song${added == 1 ? '' : 's'}, '
        'removed $removed song${removed == 1 ? '' : 's'}.',
        title: 'Playlist updated',
      );
    } else if (added > 0) {
      VoraSnackbar.success(
        context,
        'Added $added song${added == 1 ? '' : 's'} to playlist',
        title: 'Added to playlist',
      );
    } else {
      VoraSnackbar.success(
        context,
        'Removed $removed song${removed == 1 ? '' : 's'} from playlist',
        title: 'Removed from playlist',
      );
    }
  }

  /// Refreshes every playlist surface after a committed write: the
  /// authoritative membership provider and the playlist detail behind the
  /// sheet.
  void _publishChange() {
    ref.read(playlistRefreshTickProvider.notifier).state++;
    ref.invalidate(playlistMembershipProvider(widget.playlistId));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final asyncValue = ref.watch(pagedSongsProvider);

    final hasSongs = asyncValue.value?.isNotEmpty ?? false;
    final selectAllEnabled =
        _membersLoaded && hasSongs && !_applyingSelectAll && !_committing;
    final count = _pendingIds.length;
    final summary = count == 0
        ? 'No songs will be in the playlist'
        : count == 1
        ? '1 song will be in the playlist'
        : '$count songs will be in the playlist';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Add songs',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppTokens.s2),
            child: TextButton(
              onPressed: selectAllEnabled ? _selectAll : null,
              style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
              child: _applyingSelectAll
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Text(
                      'Select All',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
      body: asyncValue.when(
        skipLoadingOnRefresh: true,
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
        error: (e, _) => Center(
          child: Text(
            'Could not load songs.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        data: (tiles) {
          if (tiles.isEmpty) {
            return Center(
              child: Text(
                'Your library is empty.\nScan or import music first.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }
          if (!_membersLoaded) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2.4),
            );
          }
          return ListView.separated(
            controller: _controller,
            itemCount:
                tiles.length +
                (ref.read(pagedSongsProvider.notifier).hasMore ? 1 : 0),
            separatorBuilder: (_, i) => i == tiles.length - 1
                ? const SizedBox.shrink()
                : Divider(
                    height: AppTokens.borderHairline,
                    thickness: AppTokens.borderHairline,
                    indent: AppTokens.artworkLg + AppTokens.s3 + AppTokens.s4,
                    endIndent: AppTokens.s4,
                    color: colorScheme.outlineVariant,
                  ),
            itemBuilder: (context, index) {
              if (index >= tiles.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  ),
                );
              }
              final tile = tiles[index];
              return _PickerTile(
                tile: tile,
                isMember: _pendingIds.contains(tile.song.id),
                onAction: () => _toggle(tile),
              );
            },
          );
        },
      ),
      bottomNavigationBar: Material(
        color: colorScheme.surface,
        elevation: 8,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.s4,
              AppTokens.s2,
              AppTokens.s4,
              AppTokens.s3,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  summary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppTokens.s2),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('done-button'),
                    onPressed: _membersLoaded && !_committing ? _done : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppTokens.s3,
                      ),
                    ),
                    child: _committing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : const Text(
                            'Done',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.tile,
    required this.isMember,
    required this.onAction,
  });

  final SongTileData tile;

  /// Whether the song is in the PENDING membership. Drives the contextual
  /// icon: `+` (ADD) when false, `-` (REMOVE) when true. It only reflects the
  /// user's in-progress selection — nothing is written until "Done".
  final bool isMember;

  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final song = tile.song;

    final icon = isMember
        ? Icons.remove_circle_outline_rounded
        : Icons.add_circle_outline_rounded;
    final color = isMember ? colorScheme.error : colorScheme.primary;
    final tooltip = isMember ? 'Remove from playlist' : 'Add to playlist';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s4,
        vertical: AppTokens.s1,
      ),
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTokens.rSm),
                child: ArtworkView(path: tile.artPath, size: 56),
              ),
            ),
            const SizedBox(width: AppTokens.s3),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (song.artist != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      song.artist!,
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
            const SizedBox(width: AppTokens.s2),
            IconButton(
              tooltip: tooltip,
              key: ValueKey('${isMember ? 'remove' : 'add'}-song-${song.id}'),
              onPressed: onAction,
              icon: Icon(icon, size: 24, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

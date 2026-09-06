import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../app/widgets/vora_snackbar.dart';
import '../../../../shared/widgets/artwork_view.dart';
import '../../../library/data/library_models.dart';
import '../../../library/presentation/providers/library_view_providers.dart';
import '../providers/playlist_providers.dart';

/// Opens a full-screen picker that ADDs songs to, or REMOVEs them from, a
/// playlist with one smart, contextual action at a time.
///
/// Membership is the reactor plumbing's single source of truth
/// ([playlistMembershipProvider]): every song already in the playlist shows a
/// REMOVE (`-`) action, every song outside it shows an ADD (`+`) action, and
/// tapping the `+`/`-` applies that action immediately. A single `Select All`
/// action adds whatever is missing, or removes everything when nothing is
/// missing — it is never two separate add/remove modes.
///
/// All database writes happen here and refresh the playlist surfaces
/// reactively (via [playlistRefreshTickProvider]), so the picker returns
/// nothing: the playlist behind it is always in sync before the sheet closes.
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

  /// Current membership (song row ids) of the playlist. Hydrated from the
  /// reactive [playlistMembershipProvider] and updated optimistically after
  /// every committed DB write, so the `+`/`-` buttons never render a stale
  /// window between a successful write and the provider's refetch.
  Set<int> _members = const <int>{};
  bool _membersLoaded = false;

  /// Song ids with an operation currently in flight (rapid-tap guard).
  final Set<int> _busy = <int>{};

  /// True while a bulk `Select All` operation is running, so per-song actions
  /// can't race it into duplicates.
  bool _applyingSelectAll = false;

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
          _members = members;
          _membersLoaded = true;
        });
      }
    } catch (_) {
      // A failed read keeps the last known membership; rows never render a
      // correct-looking but invented state. Actions still surface failures.
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

  /// One immediate, contextual add/remove for [tile], decided purely by the
  /// song's CURRENT membership: `+` for songs not in the playlist, `-` for
  /// songs already in it. There is no global add/remove mode.
  ///
  /// The button state only advances after the database write commits; on
  /// failure neither the membership nor the icon moves. A song whose operation
  /// is still in flight can't be tapped again, so rapid `+` taps can never
  /// create a duplicate entry.
  Future<void> _toggle(SongTileData tile) async {
    final id = tile.song.id;
    if (_busy.contains(id) || _applyingSelectAll) return;
    final add = !_members.contains(id);
    setState(() => _busy.add(id));
    final repository = ref.read(playlistRepositoryProvider);
    try {
      if (add) {
        await repository.addSongs(widget.playlistId, [id]);
      } else {
        await repository.removeSongById(widget.playlistId, id);
      }
      if (mounted) {
        setState(() {
          _members = add ? {..._members, id} : {..._members}..remove(id);
        });
      }
      _publishChange();
      if (mounted) {
        if (add) {
          VoraSnackbar.success(
            context,
            'Added "${tile.song.title}" to playlist',
            title: 'Added to playlist',
          );
        } else {
          VoraSnackbar.success(
            context,
            'Removed "${tile.song.title}" from playlist',
            title: 'Removed from playlist',
          );
        }
      }
    } catch (_) {
      if (mounted) {
        VoraSnackbar.error(
          context,
          add
              ? 'Could not add "${tile.song.title}" to the playlist.'
              : 'Could not remove "${tile.song.title}" from the playlist.',
          title: 'Playlist error',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy.remove(id));
      }
    }
  }

  /// Single, smart `Select All`. Operates on the whole picker dataset (the
  /// paginated library, streamed to completion exactly like the previous bulk
  /// actions — not the currently visible window):
  ///
  /// - when songs are missing from the playlist, exactly those are ADDED
  ///   (existing members are left untouched, in their existing order);
  /// - when every song is already a member, all of them are REMOVED.
  ///
  /// The reported count is the number of rows actually written. Songs with an
  /// operation in flight are skipped so a bulk write can never duplicate them.
  Future<void> _selectAll() async {
    if (_applyingSelectAll) return;
    setState(() => _applyingSelectAll = true);
    try {
      final notifier = ref.read(pagedSongsProvider.notifier);
      while (notifier.hasMore) {
        await notifier.loadMore();
      }
      final tiles = ref.read(pagedSongsProvider).value;
      if (tiles == null || tiles.isEmpty) return;
      final members = await ref.read(
        playlistMembershipProvider(widget.playlistId).future,
      );
      final missing = <int>[];
      final present = <int>[];
      for (final t in tiles) {
        if (_busy.contains(t.song.id)) continue; // in flux: leave alone.
        if (members.contains(t.song.id)) {
          present.add(t.song.id);
        } else {
          missing.add(t.song.id);
        }
      }
      if (missing.isEmpty && present.isEmpty) return;
      final repository = ref.read(playlistRepositoryProvider);
      if (missing.isEmpty) {
        await repository.removeSongs(widget.playlistId, present);
      } else {
        await repository.addSongs(widget.playlistId, missing);
      }
      if (mounted) {
        setState(() {
          if (missing.isEmpty) {
            _members = _members.difference(present.toSet());
          } else {
            _members = {..._members, ...missing};
          }
        });
      }
      _publishChange();
      if (mounted) {
        final count = missing.isEmpty ? present.length : missing.length;
        if (missing.isEmpty) {
          VoraSnackbar.success(
            context,
            'Removed $count song${count == 1 ? '' : 's'} from playlist',
            title: 'Removed from playlist',
          );
        } else {
          VoraSnackbar.success(
            context,
            'Added $count song${count == 1 ? '' : 's'} to playlist',
            title: 'Added to playlist',
          );
        }
      }
    } catch (_) {
      if (mounted) {
        VoraSnackbar.error(
          context,
          'Could not update the playlist.',
          title: 'Playlist error',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _applyingSelectAll = false);
      }
    }
  }

  /// Refreshes every playlist surface after a committed write: the
  /// authoritative membership provider (this sheet re-renders its icons once
  /// it refetches) and the playlist detail behind the sheet.
  void _publishChange() {
    ref.read(playlistRefreshTickProvider.notifier).state++;
    ref.invalidate(playlistMembershipProvider(widget.playlistId));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final asyncValue = ref.watch(pagedSongsProvider);
    final membershipAsync = ref.watch(
      playlistMembershipProvider(widget.playlistId),
    );

    // Reconcile the authoritative database membership into the local rendering
    // set whenever the reactive provider delivers a fresh answer (it watches
    // the refresh tick, so committed writes from this or any other surface
    // converge here instead of leaving stale icons behind).
    final authoritative = membershipAsync.value;
    if (authoritative != null && !_sameMembers(authoritative)) {
      Future.microtask(() {
        if (mounted && !_sameMembers(authoritative)) {
          setState(() => _members = authoritative);
        }
      });
    }

    final hasSongs = asyncValue.value?.isNotEmpty ?? false;
    final selectAllEnabled =
        _membersLoaded && hasSongs && !_applyingSelectAll;

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
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.primary,
              ),
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
                isMember: _members.contains(tile.song.id),
                busy: _busy.contains(tile.song.id),
                onAction: () => _toggle(tile),
              );
            },
          );
        },
      ),
    );
  }

  bool _sameMembers(Set<int> other) {
    if (_members.length != other.length) return false;
    return _members.containsAll(other);
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.tile,
    required this.isMember,
    required this.busy,
    required this.onAction,
  });

  final SongTileData tile;

  /// Whether the song is currently in the playlist. Drives the contextual
  /// icon: `+` (ADD) when false, `-` (REMOVE) when true.
  final bool isMember;

  /// True while this song's operation is in flight; swaps the icon for a
  /// spinner so a rapid second tap cannot double-apply.
  final bool busy;

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
            if (busy)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            else
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
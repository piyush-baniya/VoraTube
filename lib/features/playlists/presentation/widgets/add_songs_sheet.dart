import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../shared/widgets/artwork_view.dart';
import '../../../library/data/library_models.dart';
import '../../../library/presentation/providers/library_view_providers.dart';
import '../providers/playlist_providers.dart';

/// Result of the add/remove songs picker.
class PickerResult {
  const PickerResult({this.toAdd = const [], this.toRemove = const []});

  final List<SongTileData> toAdd;
  final List<int> toRemove;
}

/// Bulk-selection actions offered by the picker's app-bar menu.
enum _BulkSelection { allToAdd, allToRemove, clear }

/// Opens a full-screen multi-select picker that adds/removes songs in a
/// playlist.
///
/// Reuses the paginated [pagedSongsProvider] so it streams the whole library a
/// page at a time. Songs already in the playlist can be tapped to mark them for
/// removal. Returns a [PickerResult] with songs to add and song IDs to remove,
/// or null if cancelled.
Future<PickerResult?> showAddSongsSheet(
  BuildContext context, {
  required int playlistId,
}) {
  return Navigator.of(context).push<PickerResult>(
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
  final Set<int> _selected = <int>{};
  final Set<int> _toRemove = <int>{};
  Set<int> _members = const <int>{};

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final members = await ref.read(
      playlistMembershipProvider(widget.playlistId).future,
    );
    if (mounted) {
      setState(() => _members = members);
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

  void _toggle(SongTileData tile) {
    setState(() {
      if (_members.contains(tile.song.id)) {
        // Toggle removal of an existing member
        if (!_toRemove.remove(tile.song.id)) {
          _toRemove.add(tile.song.id);
        }
      } else {
        // Toggle selection of a new song to add
        if (!_selected.remove(tile.song.id)) {
          _selected.add(tile.song.id);
        }
      }
    });
  }

  bool get _hasChanges => _selected.isNotEmpty || _toRemove.isNotEmpty;

  void _apply() {
    if (!_hasChanges) return;
    final byId = <int, SongTileData>{};
    final tiles = ref.read(pagedSongsProvider).value;
    if (tiles != null) {
      for (final t in tiles) {
        byId[t.song.id] = t;
      }
    }
    Navigator.of(context).pop(PickerResult(
      toAdd: _selected.map((id) => byId[id]).whereType<SongTileData>().toList(),
      toRemove: _toRemove.toList(),
    ));
  }

  String get _buttonLabel {
    final add = _selected.length;
    final rem = _toRemove.length;
    if (add == 0 && rem == 0) return 'Select songs';
    if (add == 0) {
      return 'Remove $rem ${rem == 1 ? 'song' : 'songs'}';
    }
    if (rem == 0) {
      return 'Add $add ${add == 1 ? 'song' : 'songs'}';
    }
    return 'Add $add, remove $rem';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final asyncValue = ref.watch(pagedSongsProvider);

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
          PopupMenuButton<_BulkSelection>(
            tooltip: 'Bulk selection',
            icon: const Icon(Icons.checklist_rounded),
            onSelected: (action) async {
              // Make "select all" genuinely select all: stream in the
              // remaining pages before snapshotting the tile list.
              if (action != _BulkSelection.clear) {
                final notifier = ref.read(pagedSongsProvider.notifier);
                while (notifier.hasMore) {
                  await notifier.loadMore();
                }
              }
              final tiles = ref.read(pagedSongsProvider).value;
              if (tiles == null) return;
              setState(() {
                switch (action) {
                  case _BulkSelection.allToAdd:
                    _selected.addAll(
                      tiles
                          .where((t) => !_members.contains(t.song.id))
                          .map((t) => t.song.id),
                    );
                  case _BulkSelection.allToRemove:
                    _toRemove.addAll(
                      tiles
                          .where((t) => _members.contains(t.song.id))
                          .map((t) => t.song.id),
                    );
                    // Songs just selected for adding cannot also be removed.
                    _selected.removeAll(_toRemove);
                  case _BulkSelection.clear:
                    _selected.clear();
                    _toRemove.clear();
                }
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _BulkSelection.allToAdd,
                child: Text('Select all (add)'),
              ),
              if (_members.isNotEmpty)
                const PopupMenuItem(
                  value: _BulkSelection.allToRemove,
                  child: Text('Select all (remove)'),
                ),
              const PopupMenuItem(
                value: _BulkSelection.clear,
                child: Text('Clear selection'),
              ),
            ],
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
              final isMember = _members.contains(tile.song.id);
              return _PickerTile(
                tile: tile,
                isMember: isMember,
                selected: _selected.contains(tile.song.id),
                markedForRemoval: _toRemove.contains(tile.song.id),
                onTap: () => _toggle(tile),
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s4),
          child: FilledButton.icon(
            onPressed: _hasChanges ? _apply : null,
            icon: Icon(
              _toRemove.isEmpty
                  ? Icons.add_rounded
                  : _selected.isEmpty
                      ? Icons.remove_circle_outline_rounded
                      : Icons.check_rounded,
              size: 20,
            ),
            label: Text(_buttonLabel),
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
    required this.selected,
    required this.markedForRemoval,
    required this.onTap,
  });

  final SongTileData tile;
  final bool isMember;
  final bool selected;
  final bool markedForRemoval;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final song = tile.song;

    // When marked for removal, show a dimmed/strikethrough style.
    final dimmed = markedForRemoval;
    final titleColor = dimmed
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
        : isMember
            ? colorScheme.onSurfaceVariant
            : colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      child: Padding(
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
                        color: titleColor,
                        decoration:
                            dimmed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (song.artist != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        song.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: dimmed ? 0.5 : 1.0,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.s2),
              Icon(
                markedForRemoval
                    ? Icons.remove_circle_outline_rounded
                    : isMember
                        ? Icons.check_circle_rounded
                        : selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: markedForRemoval
                    ? colorScheme.error
                    : isMember
                        ? Colors.grey
                        : selected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.5,
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

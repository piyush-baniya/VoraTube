import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../shared/widgets/artwork_view.dart';
import '../../../library/data/library_models.dart';
import '../../../library/presentation/providers/library_view_providers.dart';
import '../providers/playlist_providers.dart';

/// Opens a full-screen multi-select picker that adds songs to a playlist.
///
/// Reuses the paginated [pagedSongsProvider] so it streams the whole library a
/// page at a time. Songs already in the playlist are disabled. Returns the list
/// of newly selected [SongTileData] to append, or null if cancelled.
Future<List<SongTileData>?> showAddSongsSheet(
  BuildContext context, {
  required int playlistId,
}) {
  return Navigator.of(context).push<List<SongTileData>>(
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
    if (_members.contains(tile.song.id)) {
      return;
    }
    setState(() {
      if (!_selected.remove(tile.song.id)) {
        _selected.add(tile.song.id);
      }
    });
  }

  void _add() {
    final byId = <int, SongTileData>{};
    final tiles = ref.read(pagedSongsProvider).value;
    if (tiles != null) {
      for (final t in tiles) {
        byId[t.song.id] = t;
      }
    }
    Navigator.of(
      context,
    ).pop(_selected.map((id) => byId[id]).whereType<SongTileData>().toList());
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
            onPressed: _selected.isEmpty ? null : _add,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: Text(
              _selected.isEmpty
                  ? 'Select songs'
                  : 'Add ${_selected.length} '
                        '${_selected.length == 1 ? 'song' : 'songs'}',
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
    required this.selected,
    required this.onTap,
  });

  final SongTileData tile;
  final bool isMember;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final song = tile.song;

    return InkWell(
      onTap: isMember ? null : onTap,
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
                        color: isMember
                            ? colorScheme.onSurfaceVariant
                            : colorScheme.onSurface,
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
              Icon(
                isMember
                    ? Icons.check_circle_rounded
                    : selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: isMember
                    ? Colors.grey
                    : selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

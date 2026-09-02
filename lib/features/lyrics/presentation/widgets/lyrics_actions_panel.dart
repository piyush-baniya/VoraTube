import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/models/lyrics.dart';
import '../../../../core/player/player_controller.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../data/lrclib_client.dart';
import '../providers/lyrics_providers.dart';

/// The action panel offered at the start of a lyrics session.
///
/// Provides the three primary ways to obtain lyrics for the current song —
/// fetch online (with an inline options list), search the web, and upload a
/// `.lrc` file (which then swaps to a "Remove .LRC File" action). When the
/// user has already uploaded an LRC for this song, a "Show uploaded" action
/// is added so those lyrics stay reachable.
///
/// Shared between the standalone [LyricsView] and the full player's compact
/// lyrics panel so the actions are reachable in both places.
class LyricsActionsPanel extends ConsumerStatefulWidget {
  const LyricsActionsPanel({
    super.key,
    this.compact = false,
    this.row = false,
    this.grid = false,
  });

  /// When true the buttons are sized for a tighter panel (used by the compact
  /// full-player lyrics panel) and render without the fixed 260 dp column.
  final bool compact;

  /// When true the actions render as a single horizontally-scrolling row of
  /// small chips instead of a stacked/grid column. Used where vertical space is
  /// tight but the actions must stay reachable — the collapsed lyrics preview
  /// and the bottom of a loaded-lyrics surface.
  final bool row;

  /// When true the primary actions render as a centred two-per-row grid (the
  /// buttons-first entry the lyrics surface opens with) and the online options
  /// list is shown inline rather than in a modal sheet.
  final bool grid;

  @override
  ConsumerState<LyricsActionsPanel> createState() => _LyricsActionsPanelState();
}

class _LyricsActionsPanelState extends ConsumerState<LyricsActionsPanel> {
  bool _searchingOnline = false;

  /// Term of the online-options phase: null until "Show online lyrics" is
  /// tapped, then a status (loading / error / offline / done / notFound) plus
  /// the fetched results once available. Only meaningful in [grid] mode, where
  /// the options list renders inline.
  _OnlinePick? _onlinePick;

  void _useLyrics(LyricsData data) {
    ref.read(manualLyricsProvider.notifier).state = data;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Opens the online lyric picker. In [grid] mode the options appear inline so
  /// the user sees a real, selectable list; otherwise a modal sheet is used.
  Future<void> _showOnlineLyrics() async {
    if (_searchingOnline) return;
    final song = ref.read(currentTrackProvider);
    if (song == null) return;
    if (widget.grid) {
      await _showOnlineLyricsInline(song);
      return;
    }
    await _showOnlineLyricsSheet(song);
  }

  Future<void> _showOnlineLyricsInline(SongRef song) async {
    if (_searchingOnline) return;
    setState(() => _onlinePick = const _OnlinePick.searching());
    List<LrclibResult> results;
    try {
      results = await ref.read(lyricsServiceProvider).searchOnlineResults(song);
    } on LyricsNetworkException {
      if (!mounted) return;
      setState(() => _onlinePick = const _OnlinePick.offline());
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _onlinePick = const _OnlinePick.error());
      return;
    }
    if (!mounted) return;
    setState(() {
      _onlinePick = _OnlinePick.done(results);
    });
  }

  Future<void> _showOnlineLyricsSheet(SongRef song) async {
    if (_searchingOnline) return;
    setState(() => _searchingOnline = true);
    List<LrclibResult> results;
    try {
      results = await ref.read(lyricsServiceProvider).searchOnlineResults(song);
    } on LyricsNetworkException {
      if (!mounted) return;
      setState(() => _searchingOnline = false);
      _snack('You are offline — connect to search online lyrics.');
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _searchingOnline = false);
      _snack('Searching online lyrics failed. Try again.');
      return;
    }
    if (!mounted) return;
    setState(() => _searchingOnline = false);

    if (!mounted) return;
    if (results.isEmpty) {
      _snack('No online lyrics found for this song.');
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: results.length,
          itemBuilder: (context, index) {
            final result = results[index];
            return ListTile(
              leading: Icon(
                result.syncedLyrics?.isNotEmpty == true
                    ? Icons.sync_rounded
                    : Icons.notes_rounded,
                color: Theme.of(sheetContext).colorScheme.primary,
              ),
              title: Text(
                result.trackName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                result.artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: result.syncedLyrics?.isNotEmpty == true
                  ? const Text('Synced')
                  : null,
              onTap: () {
                final data = ref
                    .read(lyricsServiceProvider)
                    .lyricsFromResult(result);
                if (data.isEmpty) {
                  _snack('This result has no usable lyrics.');
                  return;
                }
                Navigator.of(sheetContext).pop();
                _useLyrics(data);
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _searchLyricsOnWeb() async {
    final song = ref.read(currentTrackProvider);
    if (song == null) return;
    final uri = ref.read(lyricsServiceProvider).webSearchUri(song);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) _snack('Could not open the browser.');
    } catch (_) {
      _snack('Could not open the browser.');
    }
  }

  Future<void> _uploadLrc() async {
    final song = ref.read(currentTrackProvider);
    if (song == null) return;

    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['lrc'],
    );
    if (picked.isEmpty) return;
    final file = picked.first;
    String text;
    try {
      text = await File(file.path!).readAsString();
    } catch (_) {
      _snack('Could not read the selected file.');
      return;
    }

    final service = ref.read(lyricsServiceProvider);
    final data = service.importUserLrc(song, text);
    if (data == null) {
      _snack('That file is not a valid lyrics file.');
      return;
    }

    const sentinel = Object();
    var saved = sentinel;
    try {
      saved = await service.userLrc.save(
        identityKey: song.identityKey,
        lrc: text,
        fileName: file.name,
      );
    } catch (_) {
      saved = sentinel;
    }
    if (identical(saved, sentinel) || saved == false) {
      _snack('Could not save the lyrics file.');
      return;
    }

    ref.invalidate(uploadedLrcProvider);
    _useLyrics(data);
    _snack('Lyrics from "${file.name}" saved for this song.');
  }

  /// Removes the persisted LRC for the current song, clears any displayed
  /// lyrics and returns to the buttons-first entry.
  Future<void> _removeUploadedLrc() async {
    final song = ref.read(currentTrackProvider);
    if (song == null) return;
    final service = ref.read(lyricsServiceProvider);
    try {
      await service.userLrc.delete(song.identityKey);
    } catch (_) {
      _snack('Could not remove the lyrics file.');
      return;
    }
    if (!mounted) return;
    ref
      ..invalidate(uploadedLrcProvider)
      ..read(manualLyricsProvider.notifier).state = null;
    setState(() => _onlinePick = null);
    _snack('Removed the uploaded lyrics file.');
  }

  Widget _button(
    String label,
    IconData icon,
    Future<void> Function() onTap, {
    bool enabled = true,
    bool? destructive,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDestructive = destructive == true;
    return FilledButton.tonalIcon(
      onPressed: enabled ? () => onTap() : null,
      icon: Icon(
        icon,
        size: widget.grid ? 20 : 18,
        color: isDestructive ? colorScheme.error : colorScheme.primary,
      ),
      label: Text(
        label,
        style: isDestructive ? TextStyle(color: colorScheme.error) : null,
      ),
      style: FilledButton.styleFrom(
        foregroundColor: isDestructive ? colorScheme.error : null,
        backgroundColor: isDestructive
            ? colorScheme.errorContainer.withValues(alpha: 0.5)
            : null,
        padding: EdgeInsets.symmetric(
          vertical: widget.compact ? AppTokens.s2 : AppTokens.s3,
        ),
        visualDensity: widget.compact ? VisualDensity.compact : null,
      ),
    );
  }

  Widget _chip(
    String label,
    IconData icon,
    Future<void> Function() onTap, {
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Fixed width so the three action chips form a balanced row, and the label
    // is centered inside each one instead of hugging the avatar.
    return SizedBox(
      width: 132,
      child: ActionChip(
        onPressed: enabled ? () => onTap() : null,
        avatar: Icon(icon, size: 16, color: colorScheme.primary),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium,
        ),
        labelStyle: theme.textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.s1),
      ),
    );
  }

  /// The primary actions: "Show online lyrics", "Search lyrics online", plus
  /// the third slot that swaps between "Upload .lrc file" and (once a file is
  /// saved) "Remove .lrc file".
  List<Widget> _actionTiles() {
    final uploaded = ref.watch(uploadedLrcProvider).valueOrNull;
    final uploadAction = uploaded != null
        ? _button(
            'Remove .lrc file',
            Icons.delete_outline_rounded,
            _removeUploadedLrc,
            destructive: true,
          )
        : _button('Upload .lrc file', Icons.upload_file_rounded, _uploadLrc);

    return [
      _button(
        'Show online lyrics',
        Icons.cloud_download_outlined,
        _showOnlineLyrics,
        enabled: !_searchingOnline,
      ),
      _button(
        'Search lyrics online',
        Icons.travel_explore_rounded,
        _searchLyricsOnWeb,
      ),
      uploadAction,
    ];
  }

  /// Lays buttons out exactly two per row with equal widths and spacing.
  List<Widget> _pairedRows(List<Widget> buttons) {
    final rows = <Widget>[];
    for (var i = 0; i < buttons.length; i += 2) {
      final second = i + 1 < buttons.length ? buttons[i + 1] : null;
      rows.add(
        Row(
          children: [
            Expanded(child: buttons[i]),
            const SizedBox(width: AppTokens.s2),
            if (second != null) Expanded(child: second) else const Spacer(),
          ],
        ),
      );
      if (i + 2 < buttons.length) {
        rows.add(const SizedBox(height: AppTokens.s2));
      }
    }
    return rows;
  }

  Widget _buildGrid() {
    if (_onlinePick != null) {
      return _buildOnlinePicker();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: _pairedRows(_actionTiles()),
    );
  }

  Widget _buildOnlinePicker() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pick = _onlinePick!;
    Widget content;
    if (pick.isSearching) {
      content = const Padding(
        padding: EdgeInsets.all(AppTokens.s2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppTokens.s2),
            Text('Searching online lyrics…'),
          ],
        ),
      );
    } else if (pick.isOffline) {
      content = Text(
        'You are offline — connect to search online lyrics.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      );
    } else if (pick.isError) {
      content = Text(
        'Searching online lyrics failed. Try again.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      );
    } else if (pick.results == null || pick.results!.isEmpty) {
      content = Text(
        'No online lyrics found for this song.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      );
    } else {
      final results = pick.results!;
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Choose a result',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: AppTokens.s1),
          for (var i = 0; i < results.length; i++) ...[
            _ResultTile(
              index: i,
              result: results[i],
              onTap: () {
                final data = ref
                    .read(lyricsServiceProvider)
                    .lyricsFromResult(results[i]);
                if (data.isEmpty) {
                  _snack('This result has no usable lyrics.');
                  return;
                }
                _useLyrics(data);
              },
            ),
            const SizedBox(height: AppTokens.s1),
          ],
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        content,
        const SizedBox(height: AppTokens.s2),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: _pairedRows([
            _button(
              'Back',
              Icons.arrow_back_rounded,
              () async => setState(() => _onlinePick = null),
            ),
            ..._actionTiles(),
          ]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final uploaded = ref.watch(uploadedLrcProvider).valueOrNull;

    final buttons = _actionTiles();

    if (widget.grid) {
      return _buildGrid();
    }

    if (widget.row) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.s3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _chip(
              'Show online',
              Icons.cloud_download_outlined,
              _showOnlineLyrics,
              enabled: !_searchingOnline,
            ),
            const SizedBox(width: AppTokens.s1),
            _chip(
              'Search online',
              Icons.travel_explore_rounded,
              _searchLyricsOnWeb,
            ),
            const SizedBox(width: AppTokens.s1),
            if (uploaded != null)
              _chip('Remove .lrc', Icons.delete_outline_rounded, _removeUploadedLrc)
            else
              _chip('Upload .lrc', Icons.upload_file_rounded, _uploadLrc),
          ],
        ),
      );
    }

    if (widget.compact) {
      return Column(mainAxisSize: MainAxisSize.min, children: _pairedRows(buttons));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [SizedBox(width: 260, child: Column(children: buttons))],
    );
  }
}

/// Lightweight inline picker result row that shows a visible selection affordance
/// (index + synced/timed indicator) so the user can confirm which result they
/// are about to load.
class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.index,
    required this.result,
    required this.onTap,
  });

  final int index;
  final LrclibResult result;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(AppTokens.s3),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.s3),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s3,
            vertical: AppTokens.s2,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: colorScheme.primaryContainer,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.s2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.trackName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      result.artistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (result.syncedLyrics?.isNotEmpty == true) ...[
                const SizedBox(width: AppTokens.s2),
                Icon(Icons.sync_rounded, size: 16, color: colorScheme.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The transient state of the inline online-option phase.
class _OnlinePick {
  const _OnlinePick.searching()
      : status = _OnlineStatus.searching,
        results = null;
  const _OnlinePick.offline()
      : status = _OnlineStatus.offline,
        results = null;
  const _OnlinePick.error()
      : status = _OnlineStatus.error,
        results = null;
  const _OnlinePick.done(this.results)
      : status = _OnlineStatus.done;

  final _OnlineStatus status;
  final List<LrclibResult>? results;

  bool get isSearching => status == _OnlineStatus.searching;
  bool get isOffline => status == _OnlineStatus.offline;
  bool get isError => status == _OnlineStatus.error;
}

enum _OnlineStatus { searching, offline, error, done }

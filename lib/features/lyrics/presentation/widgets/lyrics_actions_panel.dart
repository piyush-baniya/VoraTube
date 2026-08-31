import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/models/lyrics.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../data/lrclib_client.dart';
import '../providers/lyrics_providers.dart';

/// The action panel offered whenever no suitable lyrics are available.
///
/// Provides a consistent set of options for the current song: fetch lyrics from
/// an online service, search the web, upload a `.lrc` file — and, only when the
/// user has already uploaded one for this song, show those uploaded lyrics.
///
/// Shared between the standalone [LyricsView] and the full player's compact
/// lyrics panel so the actions are reachable in both places.
class LyricsActionsPanel extends ConsumerStatefulWidget {
  const LyricsActionsPanel({super.key, this.compact = false});

  /// When true the buttons are sized for a tighter panel (used by the compact
  /// full-player lyrics panel) and render without the fixed 260 dp column.
  final bool compact;

  @override
  ConsumerState<LyricsActionsPanel> createState() => _LyricsActionsPanelState();
}

class _LyricsActionsPanelState extends ConsumerState<LyricsActionsPanel> {
  bool _searchingOnline = false;

  void _useLyrics(LyricsData data) {
    ref.read(manualLyricsProvider.notifier).state = data;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showOnlineLyrics() async {
    if (_searchingOnline) return;
    final song = ref.read(currentTrackProvider);
    if (song == null) return;
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

  Future<void> _showUploadedLrc() async {
    
    final song = ref.read(currentTrackProvider);
    if (song == null) return;
    final service = ref.read(lyricsServiceProvider);
    final stored = await service.userLrc.load(song.identityKey);
    final data = stored == null ? null : service.lyricsFromUserLrc(stored.lrc);
    if (data == null) {
      ref.invalidate(uploadedLrcProvider);
      _snack('The saved lyrics are unavailable. Upload the file again.');
      return;
    }
    _useLyrics(data);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final uploaded = ref.watch(uploadedLrcProvider).valueOrNull;

    Widget button(
      String label,
      IconData icon,
      Future<void> Function() onTap, {
      bool enabled = true,
    }) => OutlinedButton.icon(
      onPressed: enabled ? () => onTap() : null,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.primary,
      padding: EdgeInsets.symmetric(
        vertical: widget.compact ? AppTokens.s2 : AppTokens.s3,
      ),
        visualDensity: widget.compact ? VisualDensity.compact : null,
      ),
    );

    final buttons = <Widget>[
      button(
        'Show online lyrics',
        Icons.cloud_download_outlined,
        _showOnlineLyrics,
        enabled: !_searchingOnline,
      ),
      const SizedBox(height: AppTokens.s1),
      button(
        'Search lyrics online',
        Icons.travel_explore_rounded,
        _searchLyricsOnWeb,
      ),
      const SizedBox(height: AppTokens.s1),
      button('Upload .lrc file', Icons.upload_file_rounded, _uploadLrc),
      // Only meaningful when the user has actually stored an LRC for
      // this song.
      if (uploaded != null) ...[
        const SizedBox(height: AppTokens.s1),
        button(
          'Show lyrics from uploaded LRC file',
          Icons.lyrics_rounded,
          _showUploadedLrc,
        ),
      ],
    ];

    if (widget.compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: buttons,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 260,
          child: Column(children: buttons),
        ),
      ],
    );
  }
}

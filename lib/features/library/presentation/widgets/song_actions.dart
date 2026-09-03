import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../app/widgets/vora_snackbar.dart';
import '../../../../core/genre/genre_enrichment_service.dart';
import '../../../../core/genre/genre_providers.dart';
import '../../../../core/ingest/artwork/artwork_file_cache.dart';
import '../../../../core/player/player_controller.dart';
import '../../../../core/storage/media_delete_service.dart';
import '../../../../shared/widgets/artwork_view.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../core/db/app_database.dart';
import '../../../library/data/library_models.dart';
import '../../../library/data/song_ref_mapper.dart';
import '../../../player/presentation/providers/player_providers.dart';
import '../../../player/presentation/screens/ringtone_cutter_screen.dart';
import '../../../player/presentation/widgets/sleep_timer_sheet.dart';
import '../../../playlists/presentation/providers/playlist_providers.dart';
import '../../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../../../smart_music/data/mood_engine.dart';
import '../../../smart_music/presentation/providers/smart_music_providers.dart';
import '../../data/library_repository.dart';
import '../providers/library_providers.dart';
import '../providers/library_view_providers.dart';
import '../screens/filtered_songs_screen.dart';

enum SongAction {
  playNext,
  addToQueue,
  addToPlaylist,
  toggleFavorite,
  goToAlbum,
  goToArtist,
  changeCover,
  editTags,
  hideSong,
  deleteFromDevice,
  findOnYouTube,
  details,
  shareSong,
  suggestMood,
  setAsRingtone,
  sleepTimer,
  removeFromPlaylist,
}

class SongActions {
  /// Bumps the library refresh tick so any [libraryRefreshTickProvider] watcher
  /// (e.g. Smart Mood mixes) rebuilds after a library-write action. Unlike
  /// `invalidate`, this always produces a state change (even from the initial
  /// 0) so dependent providers reliably refresh.
  static void _refreshLibrary(WidgetRef ref) {
    ref.read(libraryRefreshTickProvider.notifier).state++;
  }

  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required SongTileData tile,

    /// When set (playlist detail), the sheet also offers removing this song
    /// from that playlist.
    int? removeFromPlaylistId,
  }) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final song = tile.song;
    final isFavorite = ref.read(
      favoriteIdsProvider.select((ids) => ids.contains(song.id)),
    );

    // Capture refs before closing sheet
    final player = ref.read(playerProvider);
    final repo = ref.read(libraryRepositoryProvider);
    final songRef = songTileToRef(tile);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _SongActionSheet(
        tile: tile,
        isFavorite: isFavorite,
        removeFromPlaylistId: removeFromPlaylistId,
        onAction: (action) async {
          Navigator.pop(sheetContext);
          // Allow the sheet to close before heavy work, then use the OUTER
          // context (still mounted) so navigation/feedback never depends on
          // the sheet's disposal race.
          await Future<void>.delayed(const Duration(milliseconds: 140));
          if (!context.mounted) return;
          await _handleAction(
            context,
            ref,
            tile: tile,
            action: action,
            player: player,
            repo: repo,
            songRef: songRef,
            isFavorite: isFavorite,
            removeFromPlaylistId: removeFromPlaylistId,
          );
        },
      ),
    );
  }

  static Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref, {
    required SongTileData tile,
    required SongAction action,
    required PlayerController player,
    required LibraryRepository repo,
    required SongRef songRef,
    required bool isFavorite,
    int? removeFromPlaylistId,
  }) async {
    final song = tile.song;
    switch (action) {
      case SongAction.playNext:
        player.playNext(songRef);
        _snack(
          context,
          'Playing next: ${song.title}',
          variant: VoraSnackbarVariant.info,
        );
        break;
      case SongAction.addToQueue:
        player.enqueue(songRef);
        _snack(
          context,
          'Added to queue: ${song.title}',
          variant: VoraSnackbarVariant.info,
        );
        break;
      case SongAction.addToPlaylist:
        if (!context.mounted) return;
        await showAddToPlaylistSheet(context, song.id);
        break;
      case SongAction.toggleFavorite:
        await ref.read(favoriteIdsProvider.notifier).toggle(song.id);
        _snack(
          context,
          '"${song.title}"',
          variant: VoraSnackbarVariant.success,
          title: isFavorite ? 'Removed from favorites' : 'Added to favorites',
        );
        break;
      case SongAction.goToAlbum:
        if (song.albumRowId == null) {
          _snack(
            context,
            'No album information',
            variant: VoraSnackbarVariant.warning,
          );
          return;
        }
        final album = await _resolveAlbum(repo, song.albumRowId!);
        if (!context.mounted) return;
        if (album == null) {
          _snack(
            context,
            'Album not found',
            variant: VoraSnackbarVariant.warning,
          );
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => FilteredSongsScreen.album(album)),
        );
        break;
      case SongAction.goToArtist:
        if (song.artistRowId == null) {
          _snack(
            context,
            'No artist information',
            variant: VoraSnackbarVariant.warning,
          );
          return;
        }
        final artist = await _resolveArtist(repo, song.artistRowId!);
        if (!context.mounted) return;
        if (artist == null) {
          _snack(
            context,
            'Artist not found',
            variant: VoraSnackbarVariant.warning,
          );
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => FilteredSongsScreen.artist(artist)),
        );
        break;
      case SongAction.changeCover:
        await _changeCover(context, repo, tile);
        _refreshLibrary(ref);
        break;
      case SongAction.editTags:
        await _editTags(context, ref, repo, tile);
        break;
      case SongAction.hideSong:
        await _hideSong(context, ref, repo, song);
        break;
      case SongAction.deleteFromDevice:
        await _deleteSong(context, ref, repo, song);
        break;
      case SongAction.findOnYouTube:
        await _findOnYouTube(context, song);
        break;
      case SongAction.details:
        if (!context.mounted) return;
        await _showDetails(context, tile);
        break;
      case SongAction.shareSong:
        await _shareSong(context, song);
        break;
      case SongAction.suggestMood:
        await _suggestMood(ctx: context, ref: ref, song: song);
        break;
      case SongAction.setAsRingtone:
        await _openRingtoneCutter(context, songRef);
        break;
      case SongAction.sleepTimer:
        await showSleepTimerSheet(context);
        break;
      case SongAction.removeFromPlaylist:
        await removeFromPlaylist(context, ref, song, removeFromPlaylistId);
        break;
    }
  }

  /// Removes a song from a specific playlist (playlist detail context).
  static Future<void> removeFromPlaylist(
    BuildContext context,
    WidgetRef ref,
    Song song,
    int? playlistId,
  ) async {
    if (playlistId == null) return;
    try {
      final repository = ref.read(playlistRepositoryProvider);
      final songs = await repository.songsOf(playlistId, limit: 10000);
      final index = songs.indexWhere((s) => s.song.id == song.id);
      if (index < 0) {
        if (context.mounted) {
          _snack(
            context,
            'Song is no longer in this playlist',
            variant: VoraSnackbarVariant.warning,
          );
        }
        return;
      }
      await repository.removeSongAt(playlistId, index);
      // Refresh overview + detail + membership sheets immediately.
      ref.read(playlistRefreshTickProvider.notifier).state++;
      ref.invalidate(playlistMembershipProvider(playlistId));
      if (context.mounted) {
        _snack(
          context,
          '"${song.title}" was removed.',
          variant: VoraSnackbarVariant.success,
          title: 'Removed from playlist',
        );
      }
    } catch (_) {
      if (context.mounted) {
        _snack(
          context,
          'The song could not be removed from the playlist.',
          variant: VoraSnackbarVariant.error,
          title: 'Couldn\'t remove song',
        );
      }
    }
  }

  static Future<AlbumSummary?> _resolveAlbum(
    LibraryRepository repo,
    int albumRowId,
  ) async {
    final albums = await repo.albumOverview(limit: 1000);
    for (final a in albums) {
      if (a.albumRowId == albumRowId) return a;
    }
    return null;
  }

  static Future<ArtistSummary?> _resolveArtist(
    LibraryRepository repo,
    int artistRowId,
  ) async {
    final artists = await repo.artistOverview(limit: 1000);
    for (final a in artists) {
      if (a.artistRowId == artistRowId) return a;
    }
    return null;
  }

  static Future<void> _changeCover(
    BuildContext context,
    LibraryRepository repo,
    SongTileData tile,
  ) async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null || file.path == null) return;
    final pickedPath = file.path!;
    final pickedFile = File(pickedPath);
    if (!await pickedFile.exists()) {
      if (context.mounted) {
        _snack(
          context,
          'Selected file not found',
          variant: VoraSnackbarVariant.error,
        );
      }
      return;
    }
    try {
      final bytes = await pickedFile.readAsBytes();
      // Use path_provider to get art directory: reuse repo's base dir pattern
      // For now store via repo helper which handles dir creation.
      final storedPath = await repo.setCustomArtworkForSongWithBytes(
        tile.song.id,
        bytes,
      );
      if (storedPath == null) {
        if (context.mounted) {
          _snack(
            context,
            'Failed to save cover',
            variant: VoraSnackbarVariant.error,
          );
        }
        return;
      }
      ArtworkFileCache.invalidate();
      if (context.mounted) {
        _snack(
          context,
          'Cover updated',
          variant: VoraSnackbarVariant.success,
        );
      }
    } catch (_) {
      if (context.mounted) {
        _snack(
          context,
          'Failed to update cover',
          variant: VoraSnackbarVariant.error,
        );
      }
    }
  }

  static Future<void> _editTags(
    BuildContext context,
    WidgetRef ref,
    LibraryRepository repo,
    SongTileData tile,
  ) async {
    final song = tile.song;

    // Controllers are owned by the dialog state and disposed in its
    // State.dispose(), which only runs after the dialog route is fully
    // unmounted. Disposing them eagerly here (while the dialog's exit
    // transition is still animating its TextFields) used the controllers
    // after disposal and tripped Flutter's framework lifecycle assertion.
    final saved = await showDialog<EditTagsResult>(
      context: context,
      builder: (dialogContext) => EditTagsDialog(
        initialTitle: song.title,
        initialArtist: song.artist ?? '',
        initialAlbum: song.albumName ?? '',
        initialGenre: song.genre ?? '',
        initialYear: song.year != null && song.year! > 0 ? '${song.year}' : '',
      ),
    );

    if (saved == null || !saved.confirmed) return;
    if (saved.title.isEmpty) {
      if (context.mounted) {
        _snack(
          context,
          'Title cannot be empty',
          variant: VoraSnackbarVariant.warning,
        );
      }
      return;
    }
    try {
      await repo.updateSongTags(
        song.id,
        title: saved.title,
        artist: saved.artist.isEmpty ? null : saved.artist,
        albumName: saved.album.isEmpty ? null : saved.album,
        genre: saved.genre.isEmpty ? null : saved.genre,
        year: saved.year,
      );
      ref.invalidate(pagedSongsProvider);
      _refreshLibrary(ref);
      if (context.mounted) {
        _snack(
          context,
          'Tags updated',
          variant: VoraSnackbarVariant.success,
        );
      }
    } catch (_) {
      if (context.mounted) {
        _snack(
          context,
          'Failed to update tags',
          variant: VoraSnackbarVariant.error,
        );
      }
    }
  }

  static Future<void> _hideSong(
    BuildContext context,
    WidgetRef ref,
    LibraryRepository repo,
    Song song,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hide song?'),
        content: Text(
          '"${song.title}" will be hidden from the library. You can show hidden songs again from settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hide'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repo.setHidden(song.id, true);
      ref.invalidate(pagedSongsProvider);
      _refreshLibrary(ref);
      if (context.mounted) {
        _snack(
          context,
          '"${song.title}" was hidden from your library.',
          variant: VoraSnackbarVariant.success,
          title: 'Song hidden',
        );
      }
    } catch (_) {
      if (context.mounted) {
        _snack(
          context,
          'The song could not be hidden.',
          variant: VoraSnackbarVariant.error,
          title: 'Couldn\'t hide song',
        );
      }
    }
  }

  static Future<void> _deleteSong(
    BuildContext context,
    WidgetRef ref,
    LibraryRepository repo,
    Song song,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete from device?'),
        content: Text(
          '"${song.title}" will be removed from your library and the file will be deleted where possible. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Determine the source of this song. MediaStore-sourced tracks are
    // deleted through the platform bridge so Android can launch its system
    // confirmation dialog (Android 11+/API 30+ scoped storage). Imported
    // files owned by VoraTube are deleted directly from the filesystem.
    final isMediaStore = song.source == 'mediastore';

    var deleteSucceeded = false;
    var deleteCancelled = false;

    if (isMediaStore) {
      final contentUri = song.contentUri;
      if (contentUri.isNotEmpty) {
        final result = await MediaDeleteService().deleteMediaFile(contentUri);
        deleteSucceeded = result.deleted;
        deleteCancelled = result.cancelled;
      }
    } else if (song.path != null && song.path!.isNotEmpty) {
      final f = File(song.path!);
      try {
        if (await f.exists()) {
          await f.delete();
          deleteSucceeded = true;
        } else {
          deleteSucceeded = true;
        }
      } catch (_) {
        deleteSucceeded = false;
      }
    }

    if (deleteCancelled) {
      // The user cancelled the Android system confirmation dialog — not an
      // error.  Keep the song in place.
      return;
    }

    // Only remove from the local database when the file was actually deleted
    // (or the MediaStore row is unreachable/stale, in which case the library
    // should be reconciled).
    if (deleteSucceeded) {
      await repo.deleteSongsByRowIds({song.id});
      ref.invalidate(pagedSongsProvider);
      _refreshLibrary(ref);
      ref.invalidate(albumsOverviewProvider);
      ref.invalidate(artistsOverviewProvider);
      if (context.mounted) {
        _snack(
          context,
          '"${song.title}" was removed from your library.',
          variant: VoraSnackbarVariant.success,
          title: 'Song deleted',
        );
      }
    } else {
      if (context.mounted) {
        _snack(
          context,
          'The song could not be removed.',
          variant: VoraSnackbarVariant.error,
          title: 'Couldn\'t delete song',
        );
      }
    }
  }

  static Future<void> _findOnYouTube(BuildContext context, Song song) async {
    final query = [
      song.artist,
      song.title,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
    final encoded = Uri.encodeComponent(query.isEmpty ? song.title : query);
    final url = Uri.parse(
      'https://www.youtube.com/results?search_query=$encoded',
    );
    try {
      final launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        _snack(
          context,
          'Could not open YouTube',
          variant: VoraSnackbarVariant.error,
        );
      }
    } catch (_) {
      if (context.mounted) {
        _snack(
          context,
          'Could not open YouTube',
          variant: VoraSnackbarVariant.error,
        );
      }
    }
  }

  static Future<void> _shareSong(BuildContext context, Song song) async {
    final path = song.path;
    if (path != null && path.isNotEmpty) {
      final f = File(path);
      if (await f.exists()) {
        try {
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile(path, mimeType: _mimeForPath(path))],
              text: '${song.title} â€” ${song.artist ?? ''}'.trim(),
            ),
          );
          return;
        } catch (_) {}
      }
    }
    // Fallback to text share
    try {
      await SharePlus.instance.share(
        ShareParams(
          text:
              '${song.title} â€” ${song.artist ?? ''}\n${song.albumName ?? ''}'
                  .trim(),
          subject: song.title,
        ),
      );
    } catch (_) {
      if (context.mounted) {
        _snack(
          context,
          'Sharing not available',
          variant: VoraSnackbarVariant.error,
        );
      }
    }
  }

  static String _mimeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.flac')) return 'audio/flac';
    if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return 'audio/mp4';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    return 'audio/*';
  }

  static Future<void> _openRingtoneCutter(
    BuildContext context,
    SongRef songRef,
  ) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RingtoneCutterScreen(song: songRef),
      ),
    );
  }

  /// Resolves the effective genre for a song: local metadata first, then the
  /// local KV cache, then a best-effort iTunes lookup when online.
  static Future<String?> _resolveGenre(BuildContext context, Song song) async {
    final local = song.genre;
    if (local != null && local.isNotEmpty) return local;
    final container = ProviderScope.containerOf(context, listen: false);
    final service = container.read(genreEnrichmentServiceProvider);
    final repo = container.read(libraryRepositoryProvider);
    return service.enrichIfNeeded(
      rowId: song.id,
      title: song.title,
      artist: song.artist,
      existingGenre: song.genre,
      readCache: repo.kvGet,
      writeCache: repo.kvSet,
    );
  }

  /// Lets the user assign (or clear) a mood that overrides the algorithmic
  /// suggestion. Persisted to `song_stats.mood` so it feeds Smart Mixes.
  static Future<void> _suggestMood({
    required BuildContext ctx,
    required WidgetRef ref,
    required Song song,
  }) async {
    final engine = ref.read(moodEngineProvider);
    final classification = engine.classify(
      title: song.title,
      artist: song.artist,
      album: song.albumName,
      genre: song.genre,
      year: song.year,
      durationMs: song.durationMs,
    );
    final recommended = classification.primaryMood == SongMood.unknown
        ? null
        : classification.primaryMood;
    final chosen = await showModalBottomSheet<SongMood>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MoodPicker(initial: recommended),
    );
    if (chosen == null) return; // dismissed without a choice
    final repo = ref.read(libraryRepositoryProvider);
    if (chosen == SongMood.unknown) {
      await repo.setSongMood(song.id, '');
      _snack(
        ctx,
        'Mood cleared',
        variant: VoraSnackbarVariant.success,
      );
    } else {
      await repo.setSongMood(song.id, chosen.name);
      _snack(
        ctx,
        'Mood set to ${chosen.label}',
        variant: VoraSnackbarVariant.success,
      );
    }
    _refreshLibrary(ref);
  }

  static Future<void> _showDetails(
    BuildContext context,
    SongTileData tile,
  ) async {
    final song = tile.song;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final repo = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(libraryRepositoryProvider);
    Map<int, SongStat> stats = {};
    try {
      stats = await repo.getSongStatsForSongs({song.id});
    } catch (_) {}
    final stat = stats[song.id];

    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTokens.rXxl),
          ),
        ),
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
                  ArtworkView(
                    path: tile.artPath,
                    size: AppTokens.artworkXl,
                    radius: AppTokens.rMd,
                  ),
                  const SizedBox(width: AppTokens.s4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (song.artist != null) ...[
                          const SizedBox(height: AppTokens.s1),
                          Text(
                            song.artist!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
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
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s5,
                  vertical: AppTokens.s3,
                ),
                children: [
                  _DetailRow(
                    icon: Icons.album_rounded,
                    label: 'Album',
                    value: song.albumName ?? 'Unknown',
                  ),
                  if (song.artist != null)
                    _DetailRow(
                      icon: Icons.person_rounded,
                      label: 'Artist',
                      value: song.artist!,
                    ),
                  FutureBuilder<String?>(
                    future: _resolveGenre(ctx, song),
                    builder: (context, snapshot) {
                      final genre = snapshot.data;
                      final display = genre != null && genre.isNotEmpty
                          ? genre
                          : 'Unknown';
                      return _DetailRow(
                        icon: Icons.style_rounded,
                        label: 'Genre',
                        value: display,
                      );
                    },
                  ),
                  if (song.year != null && song.year! > 0)
                    _DetailRow(
                      icon: Icons.calendar_today_rounded,
                      label: 'Year',
                      value: '${song.year}',
                    ),
                  _DetailRow(
                    icon: Icons.timer_rounded,
                    label: 'Duration',
                    value: _formatDuration(song.durationMs),
                  ),
                  if (song.format != null && song.format!.isNotEmpty)
                    _DetailRow(
                      icon: Icons.audiotrack_rounded,
                      label: 'Format',
                      value: song.format!.toUpperCase(),
                    ),
                  if (song.sizeBytes != null && song.sizeBytes! > 0)
                    _DetailRow(
                      icon: Icons.storage_rounded,
                      label: 'Size',
                      value: _formatBytes(song.sizeBytes!),
                    ),
                  if (stat != null) ...[
                    const Divider(height: 24),
                    if (stat.mood != null && stat.mood!.isNotEmpty)
                      _DetailRow(
                        icon: Icons.mood_rounded,
                        label: 'Mood',
                        value: stat.mood!,
                      ),
                    _DetailRow(
                      icon: Icons.play_circle_rounded,
                      label: 'Play count',
                      value: '${stat.playCount}',
                    ),
                    if (stat.lastPlayedAt != null)
                      _DetailRow(
                        icon: Icons.history_rounded,
                        label: 'Last played',
                        value: _formatDate(
                          DateTime.fromMillisecondsSinceEpoch(
                            stat.lastPlayedAt!,
                          ),
                        ),
                      ),
                    _DetailRow(
                      icon: stat.isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      label: 'Favorite',
                      value: stat.isFavorite ? 'Yes' : 'No',
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: MediaQuery.paddingOf(ctx).bottom + AppTokens.s4),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(int ms) {
    if (ms <= 0) return 'â€”';
    final total = Duration(milliseconds: ms);
    final s = total.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${total.inMinutes}:$s';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  static void _snack(
    BuildContext context,
    String message, {
    VoraSnackbarVariant variant = VoraSnackbarVariant.info,
    String? title,
  }) {
    VoraSnackbar.show(
      context,
      variant: variant,
      message: message,
      title: title,
    );
  }
}

class _SongActionSheet extends StatelessWidget {
  const _SongActionSheet({
    required this.tile,
    required this.isFavorite,
    required this.onAction,
    this.removeFromPlaylistId,
  });

  final SongTileData tile;
  final bool isFavorite;
  final ValueChanged<SongAction> onAction;

  /// When non-null (playlist detail context) the sheet exposes a
  /// "Remove from playlist" action for this playlist.
  final int? removeFromPlaylistId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.rXxl),
        ),
      ),
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
                ArtworkView(
                  path: tile.artPath,
                  size: AppTokens.artworkMd,
                  radius: AppTokens.rSm,
                ),
                const SizedBox(width: AppTokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tile.song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (tile.song.artist != null)
                        Text(
                          tile.song.artist!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (removeFromPlaylistId != null)
                    _ActionTile(
                      icon: Icons.playlist_remove_rounded,
                      label: 'Remove from playlist',
                      iconColor: colorScheme.primary,
                      onTap: () => onAction(SongAction.removeFromPlaylist),
                    ),
                  _ActionTile(
                    icon: Icons.skip_next_rounded,
                    label: 'Play next',
                    onTap: () => onAction(SongAction.playNext),
                  ),
                  _ActionTile(
                    icon: Icons.queue_music_rounded,
                    label: 'Add to queue',
                    onTap: () => onAction(SongAction.addToQueue),
                  ),
                  _ActionTile(
                    icon: Icons.playlist_add_rounded,
                    label: 'Add to playlist',
                    onTap: () => onAction(SongAction.addToPlaylist),
                  ),
                  _ActionTile(
                    icon: isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    label: isFavorite
                        ? 'Remove from favorites'
                        : 'Add to favorites',
                    iconColor: isFavorite ? colorScheme.primary : null,
                    onTap: () => onAction(SongAction.toggleFavorite),
                  ),
                  const Divider(height: 1, indent: 56),
                  _ActionTile(
                    icon: Icons.album_rounded,
                    label: 'Go to album',
                    onTap: () => onAction(SongAction.goToAlbum),
                  ),
                  _ActionTile(
                    icon: Icons.person_rounded,
                    label: 'Go to artist',
                    onTap: () => onAction(SongAction.goToArtist),
                  ),
                  _ActionTile(
                    icon: Icons.image_rounded,
                    label: 'Change cover',
                    onTap: () => onAction(SongAction.changeCover),
                  ),
                  _ActionTile(
                    icon: Icons.edit_rounded,
                    label: 'Edit tags',
                    onTap: () => onAction(SongAction.editTags),
                  ),
                  _ActionTile(
                    icon: Icons.mood_rounded,
                    label: 'Suggest mood',
                    onTap: () => onAction(SongAction.suggestMood),
                  ),
                  const Divider(height: 1, indent: 56),
                  _ActionTile(
                    icon: Icons.visibility_off_rounded,
                    label: 'Hide song',
                    onTap: () => onAction(SongAction.hideSong),
                  ),
                  _ActionTile(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete from device',
                    iconColor: colorScheme.error,
                    onTap: () => onAction(SongAction.deleteFromDevice),
                  ),
                  const Divider(height: 1, indent: 56),
                  _ActionTile(
                    icon: Icons.ondemand_video_rounded,
                    label: 'Find on YouTube',
                    onTap: () => onAction(SongAction.findOnYouTube),
                  ),
                  _ActionTile(
                    icon: Icons.share_rounded,
                    label: 'Share song',
                    onTap: () => onAction(SongAction.shareSong),
                  ),
                  _ActionTile(
                    icon: Icons.music_note_rounded,
                    label: 'Set as ringtone',
                    onTap: () => onAction(SongAction.setAsRingtone),
                  ),
                  _ActionTile(
                    icon: Icons.bedtime_rounded,
                    label: 'Sleep timer',
                    onTap: () => onAction(SongAction.sleepTimer),
                  ),
                  _ActionTile(
                    icon: Icons.info_outline_rounded,
                    label: 'Details',
                    onTap: () => onAction(SongAction.details),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom + AppTokens.s4),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return PressableScale(
      onTap: onTap,
      // ListTile paints its background/ink on the nearest Material; the
      // actions sheet is a plain DecoratedBox, so provide a transparent
      // Material here to avoid the "ink splashes may be invisible"
      // framework assertion.
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          leading: Icon(
            icon,
            size: 22,
            color: iconColor ?? colorScheme.onSurfaceVariant,
          ),
          title: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s5,
            vertical: AppTokens.s1,
          ),
          dense: true,
          onTap: onTap,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(width: AppTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom-sheet picker used by "Suggest mood".
///
/// Tapping a concrete mood pops it as the choice; tapping "Auto" pops
/// [SongMood.unknown] so the caller can clear a previously assigned mood.
class _MoodPicker extends StatelessWidget {
  const _MoodPicker({this.initial});

  final SongMood? initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final concrete = SongMood.values.where((m) => m != SongMood.unknown);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.rXxl),
        ),
      ),
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
            child: Text(
              'Suggest a mood',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppTokens.s2),
          ...concrete.map(
            (mood) => RadioListTile<SongMood>(
              value: mood,
              groupValue: initial,
              title: Text(mood.label),
              activeColor: colorScheme.primary,
              onChanged: (v) => Navigator.of(context).pop(v),
            ),
          ),
          RadioListTile<SongMood>(
            value: SongMood.unknown,
            groupValue: initial,
            title: Text('Auto (let VoraTube decide)'),
            onChanged: (v) => Navigator.of(context).pop(v),
          ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom + AppTokens.s3),
        ],
      ),
    );
  }
}

/// Values captured from the Edit Tags dialog. [confirmed] is true when the
/// user pressed Save (as opposed to Cancel / dismissing the dialog).
class EditTagsResult {
  const EditTagsResult({
    required this.confirmed,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.year,
  });

  final bool confirmed;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final int? year;
}

/// Edit Tags dialog.
///
/// Owns its [TextEditingController]s in [State] so they are disposed exactly
/// when the dialog's element tree is unmounted â€” after the exit transition
/// finishes â€” never while the TextFields are still alive and referencing them.
class EditTagsDialog extends StatefulWidget {
  const EditTagsDialog({
    super.key,
    required this.initialTitle,
    required this.initialArtist,
    required this.initialAlbum,
    required this.initialGenre,
    required this.initialYear,
  });

  final String initialTitle;
  final String initialArtist;
  final String initialAlbum;
  final String initialGenre;
  final String initialYear;

  @override
  State<EditTagsDialog> createState() => _EditTagsDialogState();
}

class _EditTagsDialogState extends State<EditTagsDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _artistCtrl;
  late final TextEditingController _albumCtrl;
  late final TextEditingController _genreCtrl;
  late final TextEditingController _yearCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle);
    _artistCtrl = TextEditingController(text: widget.initialArtist);
    _albumCtrl = TextEditingController(text: widget.initialAlbum);
    _genreCtrl = TextEditingController(text: widget.initialGenre);
    _yearCtrl = TextEditingController(text: widget.initialYear);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _albumCtrl.dispose();
    _genreCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  EditTagsResult _result(bool confirmed) {
    final year = int.tryParse(_yearCtrl.text.trim());
    return EditTagsResult(
      confirmed: confirmed,
      title: _titleCtrl.text.trim(),
      artist: _artistCtrl.text.trim(),
      album: _albumCtrl.text.trim(),
      genre: _genreCtrl.text.trim(),
      year: year,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit tags'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _artistCtrl,
              decoration: const InputDecoration(labelText: 'Artist'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _albumCtrl,
              decoration: const InputDecoration(labelText: 'Album'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _genreCtrl,
              decoration: const InputDecoration(labelText: 'Genre'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _yearCtrl,
              decoration: const InputDecoration(labelText: 'Year'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            Text(
              'Edits update the library database only and do not modify the original file.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          // Pop with a confirmed=false result; the controllers are disposed
          // later by this State's dispose(), once the route has fully left
          // the tree â€” never during the pop animation.
          onPressed: () => Navigator.pop(context, _result(false)),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _result(true)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Bottom sheet that lists ALL genre options the existing VoraTube genre

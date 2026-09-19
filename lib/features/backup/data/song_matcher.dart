import '../../../core/db/app_database.dart';
import 'backup_models.dart';

/// How strongly a backed-up song reference matches a song row in the current
/// library. The strongest signal that resolves to exactly one row wins.
enum SongMatchTier { identity, relativePath, fileExact, metadata }

class SongMatch {
  const SongMatch({required this.rowId, required this.tier});
  final int rowId;
  final SongMatchTier tier;
}

class SongMatchResult {
  const SongMatchResult({required this.matches, required this.unresolved});
  final Map<int, SongMatch> matches;
  final List<int> unresolved;
  int get matchedCount => matches.length;
  int get unresolvedCount => unresolved.length;
}

String fileNameOf(String? path) =>
    (path ?? '').replaceAll('\\', '/').split('/').last;
String relativePathOf(String? path) {
  final value = (path ?? '').replaceAll('\\', '/');
  return value.replaceFirst(RegExp(r'^/storage/(?:emulated/\d+|[^/]+)/'), '');
}

String songIdentity(Song song) => song.source == 'mediastore'
    ? 'ms:${song.mediaStoreId}'
    : 'h:${song.contentHash}';

class SongMatcher {
  const SongMatcher({this.durationToleranceMs = 2000});
  final int durationToleranceMs;

  SongMatchResult match(List<BackupSongRef> songs, List<Song> library) {
    final matches = <int, SongMatch>{};
    final unresolved = <int>[];
    String normalized(String? s) => (s ?? '').trim().toLowerCase();
    for (final song in songs) {
      bool duration(Song row) =>
          song.durationMs > 0 &&
          (row.durationMs - song.durationMs).abs() <= durationToleranceMs;
      final tests = <SongMatchTier, bool Function(Song)>{
        SongMatchTier.identity: (row) =>
            song.identityKey.startsWith('h:') &&
            song.identityKey.length > 2 &&
            song.identityKey == 'h:${row.contentHash}',
        SongMatchTier.relativePath: (row) =>
            song.relativePath.isNotEmpty &&
            song.fileName.isNotEmpty &&
            relativePathOf(row.path) == song.relativePath &&
            fileNameOf(row.path) == song.fileName,
        SongMatchTier.fileExact: (row) =>
            song.sizeBytes > 0 &&
            row.sizeBytes == song.sizeBytes &&
            song.fileName.isNotEmpty &&
            normalized(fileNameOf(row.path)) == normalized(song.fileName) &&
            duration(row),
        SongMatchTier.metadata: (row) =>
            song.title.isNotEmpty &&
            song.artist.isNotEmpty &&
            normalized(row.title) == normalized(song.title) &&
            normalized(row.artist) == normalized(song.artist) &&
            normalized(row.albumName) == normalized(song.album) &&
            duration(row),
      };
      for (final tier in tests.entries) {
        final candidates = library.where(tier.value).toList();
        if (candidates.isEmpty) continue;
        if (candidates.length == 1) {
          matches[song.index] = SongMatch(
            rowId: candidates.single.id,
            tier: tier.key,
          );
        }
        break;
      }
      if (!matches.containsKey(song.index)) unresolved.add(song.index);
    }
    return SongMatchResult(matches: matches, unresolved: unresolved);
  }
}
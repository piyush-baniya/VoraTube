import '../ingest/artwork/artwork_file_cache.dart';
import 'artwork_palette.dart';
import 'artwork_palette_cache.dart';
import 'artwork_palette_extractor.dart';

/// What palette work should address for the currently loaded track.
///
/// [artPath] is the song's resolved artwork file path (the same one the
/// rendering widgets already use); [songIdentityKey] distinguishes the request
/// for stale-result protection and reporting.
final class ArtworkDescriptor {
  const ArtworkDescriptor({required this.songIdentityKey, this.artPath});

  final String songIdentityKey;
  final String? artPath;

  bool get hasArtwork => artPath != null && artPath!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtworkDescriptor &&
          songIdentityKey == other.songIdentityKey &&
          artPath == other.artPath;

  @override
  int get hashCode => Object.hash(songIdentityKey, artPath);
}

/// One async palette resolution tagged with the generation that started it.
final class ArtworkPaletteResult {
  const ArtworkPaletteResult({
    required this.palette,
    required this.generation,
    required this.fromCache,
  });

  final ArtworkPalette palette;

  /// Token from [ArtworkPaletteService.generation] at request start.
  final int generation;

  final bool fromCache;
}

/// Orchestrates palette resolution against the artwork cache + extractor and
/// protects rapid track changes from stale publications.
///
/// Race protection is a monotonic generation counter: every new request bumps
/// [generation] and the caller checks [isCurrent] with the returned token
/// *after* awaiting. If the user skipped from Song A to Song B while A was
/// still extracting, A's token is stale the moment it completes and its
/// palette is dropped — B's palette (or fallback) is the only one ever
/// applied.
class ArtworkPaletteService {
  ArtworkPaletteService({
    required this.cache,
    ArtworkPaletteExtractor? extractor,
  }) : _extractor = extractor ?? const ArtworkPaletteExtractor();

  final ArtworkPaletteCache cache;
  final ArtworkPaletteExtractor _extractor;

  int _generation = 0;

  /// Latest request token.
  int get generation => _generation;

  /// True while [token] still describes the newest request.
  bool isCurrent(int token) => token == _generation;

  /// Bumps [generation] so any in-flight resolution becomes stale. Called when
  /// the current track is cleared or has no artwork: the controller falls back
  /// immediately and nothing that was extracting may publish afterwards.
  void cancelPending() {
    _generation++;
  }

  /// Resolves the palette for [descriptor]: cache-hit path is fast
  /// (in-memory prevents disk entirely), extraction path is fully async and
  /// never touches playback.
  ///
  /// Returns null when there is no artwork or it cannot produce a palette —
  /// the caller then falls back to its theme-derived palette. The returned
  /// palette is always theme-independent; theme concerns live above this layer.
  Future<ArtworkPaletteResult?> resolve({
    required ArtworkDescriptor descriptor,
  }) async {
    final token = ++_generation;
    if (!descriptor.hasArtwork) return null;

    final file = ArtworkFileCache.resolve(descriptor.artPath);
    if (file == null) {
      return null;
    }
    final key = await ArtworkCacheKey.forFile(file);

    final memory = cache.getSync(key);
    if (memory != null) {
      return ArtworkPaletteResult(
        palette: memory,
        generation: token,
        fromCache: true,
      );
    }

    final cached = await cache.get(key);
    if (cached != null) {
      return ArtworkPaletteResult(
        palette: cached,
        generation: token,
        fromCache: true,
      );
    }

    final extracted = await _extractor.extractFromFile(file);
    if (extracted == null) return null;

    final finalized = extracted.copyWith(sourceArtworkKey: key);
    await cache.put(key, finalized);
    return ArtworkPaletteResult(
      palette: finalized,
      generation: token,
      fromCache: false,
    );
  }
}

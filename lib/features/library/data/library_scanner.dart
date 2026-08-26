import '../../../core/ingest/ingest_service.dart';
import 'library_repository.dart';

typedef ScanProgressListener = void Function(ScanProgress progress);

class LibraryScanner {
  LibraryScanner({
    required this.ingest,
    required this.repository,
    this.batchSize = 500,
    this.artworkChunkSize = 40,
  });

  final IngestService ingest;
  final LibraryRepository repository;
  final int batchSize;
  final int artworkChunkSize;

  Future<ScanSummary> scan({ScanProgressListener? onProgress}) async {
    await ingest.prepareScan();

    final existing = await repository.existingSongIndex();
    final seenIds = <int>{};
    var addedTotal = 0;
    var updatedTotal = 0;
    final dirtyAlbums = <int>{};
    var lastId = 0;

    while (true) {
      final batch = await ingest.getAudioBatch(
        afterId: lastId,
        limit: batchSize,
      );
      if (batch.isEmpty) {
        break;
      }

      final changed = batch
          .where(
            (track) => existing[track.mediaStoreId] != track.dateModifiedSec,
          )
          .toList(growable: false);

      if (changed.isNotEmpty) {
        final result = await repository.syncTracks(changed);
        addedTotal += result.added;
        updatedTotal += result.updated;
        dirtyAlbums.addAll(result.dirtyAlbumMediaStoreIds);
      }

      for (final track in batch) {
        seenIds.add(track.mediaStoreId);
        if (track.mediaStoreId > lastId) {
          lastId = track.mediaStoreId;
        }
      }

      onProgress?.call(
        ScanProgress(
          phase: ScanPhase.reading,
          processedCount: seenIds.length,
          addedCount: addedTotal,
        ),
      );

      if (batch.length < batchSize) {
        break;
      }
    }

    final removedCount = await repository.removeAbsent(seenIds);

    onProgress?.call(
      ScanProgress(
        phase: ScanPhase.artwork,
        processedCount: seenIds.length,
        addedCount: addedTotal,
      ),
    );

    final artworkTargets = (await repository.albumsNeedingArt(dirtyAlbums))
        .toSet();
    var artworksResolved = 0;
    final targetList = artworkTargets.toList(growable: false);
    for (var i = 0; i < targetList.length; i += artworkChunkSize) {
      final chunk = targetList.sublist(
        i,
        (i + artworkChunkSize).clamp(0, targetList.length),
      );
      final resolved = await ingest.resolveArtwork(chunk.toSet());
      await repository.attachArtwork(resolved);
      artworksResolved += resolved.values
          .where((a) => a?.hasArt ?? false)
          .length;
      onProgress?.call(
        ScanProgress(
          phase: ScanPhase.artwork,
          processedCount: seenIds.length,
          addedCount: addedTotal,
          totalHint: targetList.length,
        ),
      );
    }

    onProgress?.call(
      ScanProgress(
        phase: ScanPhase.finalizing,
        processedCount: seenIds.length,
        addedCount: addedTotal,
      ),
    );

    await repository.completeScan(totalSongs: seenIds.length);

    return ScanSummary(
      totalSongs: seenIds.length,
      addedSongs: addedTotal,
      updatedSongs: updatedTotal,
      removedSongs: removedCount,
      artworkAttempts: artworkTargets.length,
      artworksResolved: artworksResolved,
      completedAt: DateTime.now(),
    );
  }
}

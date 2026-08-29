import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/core/ingest/audio_formats.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';

void main() {
  group('extensionOf', () {
    test('lowercases and strips the dot for real paths', () {
      expect(extensionOf('/storage/Music/song.MP3'), 'mp3');
      expect(extensionOf('track.mp3'), 'mp3');
      expect(extensionOf('song.multi.name.flac'), 'flac');
    });

    test('returns null when there is no extension', () {
      expect(extensionOf('Audio/Music/song'), isNull);
      expect(extensionOf('/storage/Music/'), isNull);
      expect(extensionOf(null), isNull);
      expect(extensionOf(''), isNull);
      expect(extensionOf('song.'), isNull);
    });
  });

  group('supportedAudioExtensions', () {
    test('covers every Android MediaStore format seen in the field', () {
      for (final ext in ['mp3', 'wav', 'flac', 'ogg', 'opus', 'm4a', 'aac']) {
        expect(
          isSupportedAudioExtension('song.$ext'),
          isTrue,
          reason: '$ext should be supported',
        );
      }
    });

    test('iOS import set stays narrower than the Android set', () {
      expect(iOsImportExtensions.contains('ogg'), isFalse);
      expect(iOsImportExtensions.contains('opus'), isFalse);
      for (final ext in iOsImportExtensions) {
        expect(supportedAudioExtensions.contains(ext), isTrue);
      }
    });
  });

  group('isValidPlayableTrack', () {
    IngestTrack msTrack({
      required int id,
      int durationMs = 180000,
      String? path = '/storage/emulated/0/Music/song.mp3',
    }) {
      return IngestTrack(
        source: IngestSource.mediastore,
        mediaStoreId: id,
        contentUri: 'content://media/external/audio/media/$id',
        path: path,
        title: 'Song $id',
        durationMs: durationMs,
        dateModifiedSec: 100,
      );
    }

    test('accepts well-formed music', () {
      expect(isValidPlayableTrack(msTrack(id: 1)), isTrue);
      expect(
        isValidPlayableTrack(msTrack(id: 2, path: 'song.UPPER.WAV')),
        isTrue,
      );
    });

    test('rejects zero-length and near-empty artifacts', () {
      expect(isValidPlayableTrack(msTrack(id: 3, durationMs: 0)), isFalse);
      expect(isValidPlayableTrack(msTrack(id: 4, durationMs: 999)), isFalse);
    });

    test('rejects files with non-music extensions', () {
      expect(
        isValidPlayableTrack(
          msTrack(id: 5, path: '/storage/backup/AutoBackup_001.zip'),
        ),
        isFalse,
      );
      expect(
        isValidPlayableTrack(
          msTrack(id: 6, path: '/storage/emulated/0/Documents/notes.txt'),
        ),
        isFalse,
      );
      expect(
        isValidPlayableTrack(
          msTrack(id: 7, path: '/storage/emulated/0/media.mp4'),
          // .mp4 is a playable audio container extension.
        ),
        isTrue,
      );
    });

    test('does not over-filter a track with no path at all', () {
      expect(isValidPlayableTrack(msTrack(id: 8, path: null)), isTrue);
    });

    test('applies to imported tracks too', () {
      IngestTrack imported(String hash, String path, int durationMs) {
        return IngestTrack(
          source: IngestSource.imported,
          contentHash: hash,
          contentUri: 'file:///documents/$path',
          path: path,
          title: path,
          durationMs: durationMs,
          dateModifiedSec: 1,
        );
      }

      expect(isValidPlayableTrack(imported('a', 'song.flac', 120000)), isTrue);
      expect(
        isValidPlayableTrack(imported('b', 'payload.dmg', 120000)),
        isFalse,
      );
      expect(isValidPlayableTrack(imported('c', 'ping.ogg', 0)), isFalse);
    });
  });
}

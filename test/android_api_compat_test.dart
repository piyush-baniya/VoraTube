// Regression test for the Android 9 (API 28) crash:
//
//   java.lang.NoClassDefFoundError: android.provider.MediaStore$Downloads
//
// `MediaStore.Downloads` is an API 29+ class. The ingest bridge used to
// reference it directly inside `cleanupPublishedArtwork()`, which ran on
// every Android version, crashing API 28 devices in release builds (R8).
//
// The fix guards the call with `Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q`
// and isolates every `MediaStore.Downloads` reference inside a dedicated
// `DownloadsArtworkCleanup` class that is only loaded after the guard passes.
// These tests scan the native Kotlin source so the compatibility boundary
// cannot silently regress.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const bridgePath =
    'android/app/src/main/kotlin/com/piyushbaniya/vora_tube/ingest/'
    'VoraTubeIngestBridge.kt';

void main() {
  final file = File(bridgePath);
  final source = file.existsSync() ? file.readAsStringSync() : null;

  test('ingest bridge Kotlin source exists', () {
    expect(source, isNotNull, reason: 'Expected $bridgePath to exist');
  });

  test(
    'MediaStore.Downloads references are isolated behind an API 29 guard',
    () {
      expect(source, isNotNull);
      final src = source!;

      // The SDK guard must exist before any Downloads usage.
      expect(
        src.contains('Build.VERSION.SDK_INT < Build.VERSION_CODES.Q'),
        isTrue,
        reason:
            'cleanupPublishedArtwork must guard on API 29 (VERSION_CODES.Q) '
            'before touching MediaStore.Downloads',
      );

      // Every MediaStore.Downloads reference must live inside the dedicated
      // API-29-only helper class, never in the shared bridge class body.
      // Strip comments first so documentation prose doesn't count as code.
      final noComments = src
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
          .replaceAll(RegExp(r'//[^\n]*'), '');

      final codeHelperStart =
          noComments.indexOf('object DownloadsArtworkCleanup');
      expect(
        codeHelperStart,
        greaterThan(-1),
        reason:
            'MediaStore.Downloads references must be isolated inside the '
            'DownloadsArtworkCleanup helper class',
      );

      for (var i = noComments.indexOf('MediaStore.Downloads');
          i != -1;
          i = noComments.indexOf('MediaStore.Downloads', i + 1)) {
        expect(
          i,
          greaterThan(codeHelperStart),
          reason:
              'MediaStore.Downloads referenced at offset $i outside the '
              'API-29-only DownloadsArtworkCleanup helper; on Android 9 '
              '(API 28) this resolves NoClassDefFoundError',
        );
      }
    },
  );
}

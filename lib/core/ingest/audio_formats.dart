import 'ingest_service.dart';

/// Single source of truth for "what is music worth ingesting and playing".
///
/// Both discovery layers consult these rules:
///
///  * native MediaStore scans (`VoraTubeIngestBridge.kt`) mirror the MIME and
///    extension whitelists so junk never crosses the method channel, and
///  * the Dart scanner ([LibraryScanner]) applies [isValidPlayableTrack] as a
///    second gate that is unit-testable and platform-agnostic, so a future
///    pull-style source cannot accidentally admit non-music.
///
/// Extensions accepted on Android. iOS keeps the stricter [iOsImportExtensions]
/// subset because its system decoders cannot play OGG-family files.
const Set<String> supportedAudioExtensions = {
  'mp3',
  'm4a',
  'm4b',
  'aac',
  'flac',
  'wav',
  'aif',
  'aiff',
  'ogg',
  'oga',
  'opus',
  'mka',
  'amr',
  'caf',
  'mp4',
};

/// Extensions the iOS import pipeline accepts. OGG/Vorbis is deliberately
/// absent: iOS system decoders cannot play it, so ingesting it would produce
/// entries that can never be played. ALAC arrives as `.m4a`.
const Set<String> iOsImportExtensions = {
  'mp3',
  'm4a',
  'm4b',
  'aac',
  'flac',
  'wav',
  'aif',
  'aiff',
};

/// Minimum playable length, in milliseconds.
///
/// Shorter files are notifications, sound effects, jingles or broken/zero-length
/// artifacts. MediaStore's `IS_MUSIC` heuristic is fallible (a corrupt backup
/// or a renamed file can still be flagged as music), and a 0 ms track is one
/// just_audio cannot prepare — both are rejected here so they never surface as
/// unplayable library rows.
const int minPlayableDurationMs = 1000;

/// Lowercased extension of [pathOrName] without the leading dot, or null when
/// the path has no extension.
String? extensionOf(String? pathOrName) {
  if (pathOrName == null || pathOrName.isEmpty) {
    return null;
  }
  final dot = pathOrName.lastIndexOf('.');
  if (dot < 0 || dot == pathOrName.length - 1) {
    return null;
  }
  return pathOrName.substring(dot + 1).toLowerCase();
}

/// Whether a file path/name carries an extension VoraTube can play.
bool isSupportedAudioExtension(String? pathOrName) {
  final ext = extensionOf(pathOrName);
  return ext != null && supportedAudioExtensions.contains(ext);
}

/// Whether [track] is real, playable music rather than an unplayable artifact.
///
/// Rejects with positive evidence only: a short or zero duration, or a known
/// unsupported extension. A track with no path/extension at all is left to the
/// native MIME verdict (typically a MediaStore row with no `DATA`), so we never
/// over-filter legitimate files. These rules apply to every ingest source.
bool isValidPlayableTrack(IngestTrack track) {
  if (track.durationMs < minPlayableDurationMs) {
    return false;
  }
  final ext = extensionOf(track.path);
  if (ext != null && !supportedAudioExtensions.contains(ext)) {
    return false;
  }
  return true;
}

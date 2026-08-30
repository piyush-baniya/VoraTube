import 'package:flutter/services.dart';

/// A successfully exported ringtone clip.
class AudioCutResult {
  const AudioCutResult({
    required this.path,
    required this.contentUri,
    required this.durationMs,
  });

  /// Absolute path to the file inside app-owned storage (always available,
  /// even when the file could not be registered with MediaStore).
  final String path;

  /// A `content://` URI when the file was registered with MediaStore (API 29+)
  /// so it can be assigned as the device ringtone; empty otherwise.
  final String contentUri;

  /// The measured duration of the exported clip, falling back to the requested
  /// length when it could not be measured.
  final int durationMs;

  bool get hasContentUri => contentUri.isNotEmpty;
}

/// A general, user-presentable failure during export/set-ringtone. The [code]
/// is a stable machine-readable key; [message] is safe to show to the user.
class RingtoneOperationException implements Exception {
  const RingtoneOperationException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'RingtoneOperationException($code): $message';

  /// Human copy for a [code]. Kept non-technical per project rules.
  static String describe(String code) {
    switch (code) {
      case 'missing_source':
        return 'The original audio file is no longer available.';
      case 'invalid_range':
        return 'The selected range is outside the track.';
      case 'no_audio_track':
        return 'This file has no audible audio to trim.';
      case 'missing_content_uri':
        return 'This device could not register the clip as a ringtone.';
      case 'write_settings_denied':
        return 'To set ringtones VoraTube needs the '
            '"Modify system settings" permission.';
      case 'set_failed':
      case 'cut_failed':
        return 'The ringtone could not be set. Please try again.';
      case 'unsupported_method':
        return 'This device cannot process ringtones.';
      default:
        return 'The ringtone could not be saved. Please try again.';
    }
  }
}

/// Abstraction over the native audio-util channel so feature code and tests
/// agree on the same contract without touching [MethodChannel] directly.
abstract interface class AudioUtilService {
  /// Whether the running platform can cut audio. The native bridge reports
  /// true on every supported API; this exists so tests/fakes can turn it off.
  Future<bool> supportsCutting();

  /// Cuts [startMs..endMs] from [sourceUri] into a ringtone clip.
  ///
  /// [sourceUri] is the source track's `content://` or `file://` URI (the same
  /// value the player uses). Throws a [RingtoneOperationException] on failure.
  Future<AudioCutResult> cutAudio({
    required String sourceUri,
    required int startMs,
    required int endMs,
    required String songTitle,
  });

  /// Sets the exported [contentUri] as the device's default ringtone without
  /// leaving the app (no system picker is launched). Throws a
  /// [RingtoneOperationException] when the assignment fails.
  Future<void> setDefaultRingtone(String contentUri);
}

/// Default implementation backed by the Android method channel.
class MethodChannelAudioUtilService implements AudioUtilService {
  MethodChannelAudioUtilService({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel(MethodChannelAudioUtilService.channelName);

  static const String channelName = 'voratube/audio_util_v1';

  final MethodChannel _channel;

  @override
  Future<bool> supportsCutting() async {
    try {
      final result = await _channel.invokeMethod<bool>('supportsCutting');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<AudioCutResult> cutAudio({
    required String sourceUri,
    required int startMs,
    required int endMs,
    required String songTitle,
  }) async {
    dynamic raw;
    try {
      raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'cutAudio',
        <String, Object?>{
          'sourceUri': sourceUri,
          'startMs': startMs,
          'endMs': endMs,
          'songTitle': songTitle,
        },
      );
    } on PlatformException catch (e) {
      throw RingtoneOperationException(
        e.code,
        RingtoneOperationException.describe(e.code),
      );
    } on MissingPluginException {
      throw const RingtoneOperationException(
        'unsupported_method',
        'This device cannot process ringtones.',
      );
    }
    if (raw is! Map) {
      throw const RingtoneOperationException(
        'cut_failed',
        'The audio could not be processed. Please try again.',
      );
    }
    final path = raw['path'] as String? ?? '';
    if (path.isEmpty) {
      throw const RingtoneOperationException(
        'cut_failed',
        'The audio could not be processed. Please try again.',
      );
    }
    return AudioCutResult(
      path: path,
      contentUri: raw['contentUri'] as String? ?? '',
      durationMs: (raw['durationMs'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> setDefaultRingtone(String contentUri) async {
    try {
      await _channel.invokeMethod<void>('setDefaultRingtone', <String, Object?>{
        'contentUri': contentUri,
      });
    } on PlatformException catch (e) {
      throw RingtoneOperationException(
        e.code,
        RingtoneOperationException.describe(e.code),
      );
    } on MissingPluginException {
      throw const RingtoneOperationException(
        'unsupported_method',
        'This device cannot process ringtones.',
      );
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Result of a MediaStore deletion request.
@immutable
class DeleteResult {
  const DeleteResult({required this.deleted, this.cancelled = false});

  /// Whether the file was actually deleted.
  final bool deleted;

  /// Whether the user cancelled the system confirmation dialog.
  final bool cancelled;
}

/// Thin MethodChannel wrapper around the native MediaStore deletion bridge.
///
/// On Android 11+ (API 30+), deleting media created by another app requires
/// user consent via the system confirmation dialog.  This service routes the
/// request through the platform, which handles both the direct-delete path
/// (for API < 30 or app-owned files) and the [MediaStore.createDeleteRequest]
/// path (API 30+ user-consent flow).
class MediaDeleteService {
  MediaDeleteService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('voratube/media_delete_v1');

  final MethodChannel _channel;

  /// Deletes the media item identified by [contentUri] (a `content://` URI).
  ///
  /// Returns a [DeleteResult] indicating whether the deletion succeeded or
  /// was cancelled by the user.  Never throws — errors are mapped to a
  /// non-deleted result.
  Future<DeleteResult> deleteMediaFile(String contentUri) async {
    try {
      final raw = await _channel.invokeMethod<Object?>(
        'deleteMediaFile',
        {'contentUri': contentUri},
      );
      if (raw is Map<Object?, Object?>) {
        final deleted = raw['deleted'] == true;
        final cancelled = raw['cancelled'] == true;
        return DeleteResult(deleted: deleted, cancelled: cancelled);
      }
      return const DeleteResult(deleted: false);
    } catch (_) {
      return const DeleteResult(deleted: false);
    }
  }
}

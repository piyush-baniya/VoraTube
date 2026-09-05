import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Result of a MediaStore deletion request.
@immutable
class DeleteResult {
  const DeleteResult({
    required this.deleted,
    this.cancelled = false,
    this.reason,
  });

  /// Whether the file was actually deleted.
  final bool deleted;

  /// Whether the user cancelled the system confirmation dialog.
  final bool cancelled;

  /// Optional machine-readable detail (e.g. `still_present`, `timeout`).
  final String? reason;
}

/// How long a delete may take before the outstanding platform call is
/// abandoned. The system consent dialog legitimately waits on the user, but a
/// lost result must never wedge the UI flow forever.
const Duration kMediaDeleteTimeout = Duration(minutes: 2);

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
  Future<DeleteResult> deleteMediaFile(
    String contentUri, {
    Duration timeout = kMediaDeleteTimeout,
  }) async {
    try {
      final raw = await _channel
          .invokeMethod<Object?>(
            'deleteMediaFile',
            {'contentUri': contentUri},
          )
          .timeout(timeout);
      if (raw is Map<Object?, Object?>) {
        final deleted = raw['deleted'] == true;
        final cancelled = raw['cancelled'] == true;
        final reason = raw['reason'];
        return DeleteResult(
          deleted: deleted,
          cancelled: cancelled,
          reason: reason is String ? reason : null,
        );
      }
      return const DeleteResult(deleted: false);
    } on TimeoutException {
      // The platform never answered (e.g. the consent dialog's result was
      // lost). Report failure so the caller can retry cleanly instead of
      // hanging indefinitely.
      return const DeleteResult(
        deleted: false,
        reason: 'timeout',
      );
    } catch (_) {
      return const DeleteResult(deleted: false);
    }
  }
}

import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';

/// Result of reading a stored user LRC: the raw text plus the original file
/// name for display. [fileName] may be null for rows written by older app
/// versions or when the picker did not report one.
class StoredUserLrc {
  const StoredUserLrc({required this.lrc, this.fileName});

  final String lrc;
  final String? fileName;
}

/// Persists user-uploaded .lrc files, associated with a song's stable identity.
///
/// One row per song: re-uploading replaces the previous LRC instead of
/// accumulating duplicates. The LRC text itself is stored (not a file
/// reference) so the lyrics survive the system revoking access to the
/// originally picked document, the file being moved, or a restart.
class UserLrcStore {
  UserLrcStore(this._db);

  final AppDatabase _db;

  /// Returns the stored LRC for [identityKey], or null when the user has not
  /// uploaded one (or the row is unreadable/corrupted, which is treated the
  /// same as absent: the UI then simply offers the upload action again).
  Future<StoredUserLrc?> load(String identityKey) async {
    if (identityKey.isEmpty) return null;
    try {
      final row = await _db
          .customSelect(
            'SELECT lrc, file_name FROM user_lrc WHERE identity_key = ?',
            variables: [Variable<String>(identityKey)],
          )
          .getSingleOrNull();
      if (row == null) return null;
      final lrc = row.data['lrc'] as String?;
      if (lrc == null || lrc.trim().isEmpty) return null;
      return StoredUserLrc(
        lrc: lrc,
        fileName: row.data['file_name'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Inserts or replaces the stored LRC for [identityKey]. An empty/blank
  /// [lrc] is rejected rather than persisted as a broken entry.
  Future<bool> save({
    required String identityKey,
    required String lrc,
    String? fileName,
  }) async {
    if (identityKey.isEmpty || lrc.trim().isEmpty) return false;
    try {
      await _db.customStatement(
        'INSERT INTO user_lrc (identity_key, lrc, file_name, saved_at) '
        'VALUES (?, ?, ?, ?) '
        'ON CONFLICT(identity_key) DO UPDATE SET '
        'lrc = excluded.lrc, file_name = excluded.file_name, '
        'saved_at = excluded.saved_at',
        [
          identityKey,
          lrc,
          fileName ?? '',
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> delete(String identityKey) async {
    try {
      await _db.customStatement('DELETE FROM user_lrc WHERE identity_key = ?', [
        identityKey,
      ]);
    } catch (_) {
      // Deleting a row that no longer exists is a no-op.
    }
  }
}

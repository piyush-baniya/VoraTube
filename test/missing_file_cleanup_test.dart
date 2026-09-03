import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/features/settings/presentation/screens/settings_screen.dart';

/// Unit tests for the Missing File Cleanup snackbar copy.
///
/// The message must carry the REAL removed-entry count returned by
/// `reconcileMissingFiles` — never scanned rows, estimates or hard-coded
/// numbers — with distinct zero-result and failure paths.
void main() {
  group('missingFileCleanupResult', () {
    test('multiple missing files reports the real count', () {
      final result = missingFileCleanupResult(17);

      expect(result.title, 'Cleanup complete');
      expect(result.message, 'Successfully cleaned 17 missing files.');
      expect(result.isError, isFalse);
    });

    test('one missing file uses the singular form', () {
      final result = missingFileCleanupResult(1);

      expect(result.title, 'Cleanup complete');
      expect(result.message, 'Successfully cleaned 1 missing file.');
      expect(result.isError, isFalse);
    });

    test('zero missing files reports the zero-result message', () {
      final result = missingFileCleanupResult(0);

      expect(result.title, 'Cleanup complete');
      expect(result.message, 'No missing files needed to be cleaned.');
      expect(result.isError, isFalse);
    });

    test('cleanup failure reports the failure message', () {
      final result = missingFileCleanupResult(null);

      expect(result.title, 'Cleanup failed');
      expect(result.message, "We couldn't complete missing file cleanup.");
      expect(result.isError, isTrue);
    });

    test('count is interpolated, never hard-coded', () {
      for (final n in [2, 5, 42, 1000]) {
        expect(missingFileCleanupResult(n).message, contains('$n'));
      }
    });
  });
}

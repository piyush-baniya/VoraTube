import 'dart:math' as math;

/// A parsed semantic-version-like value (e.g. `1.10.0`), comparable
/// numerically field-by-field so that `1.9.0 < 1.10.0`.
///
/// The installed version may carry a build suffix (`1.0.0+1`) and remote
/// versions may carry pre-release suffixes (`1.1.0-beta`); both are stripped
/// before comparison so only the numeric `major.minor.patch` core matters.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.parts);

  final List<int> parts;

  /// Parses a version string. Unparseable segments collapse to 0; an empty
  /// input yields an empty part list (which compares as the lowest version).
  factory AppVersion.tryParse(String raw) {
    final withoutBuild = raw.split('+').first;
    final core = withoutBuild.split('-').first;
    final parts = <int>[];
    for (final segment in core.split('.')) {
      final value = int.tryParse(segment.trim());
      if (value != null) {
        parts.add(value);
      }
    }
    return AppVersion(parts);
  }

  bool get isEmpty => parts.isEmpty;

  @override
  int compareTo(AppVersion other) {
    final length = math.max(parts.length, other.parts.length);
    for (var i = 0; i < length; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a < b) return -1;
      if (a > b) return 1;
    }
    return 0;
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppVersion &&
          parts.length == other.parts.length &&
          _sameParts(other);

  bool _sameParts(AppVersion other) {
    for (var i = 0; i < parts.length; i++) {
      if (parts[i] != other.parts[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(parts);

  @override
  String toString() => parts.join('.');
}

/// Compares two version strings numerically. Returns a negative number when
/// [a] is older than [b], zero when equal, and a positive number when newer.
int compareVersions(String a, String b) =>
    AppVersion.tryParse(a).compareTo(AppVersion.tryParse(b));

String? fallbackTitleFromPath(String? path) {
  if (path == null || path.isEmpty) {
    return null;
  }
  final normalized = path.replaceAll('\\', '/');
  final segment = normalized.split('/').last;
  final dot = segment.lastIndexOf('.');
  if (dot <= 0) {
    return segment;
  }
  return segment.substring(0, dot);
}

String? formatFromPath(String? path) {
  if (path == null) {
    return null;
  }
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) {
    return null;
  }
  final ext = path.substring(dot + 1).toLowerCase();
  if (ext.length > 5) {
    return null;
  }
  return ext;
}

final RegExp _featMarker = RegExp(
  r'\s*(?<![A-Za-z0-9])(?:ft\.?|feat\.?|featuring)(?=\s|$|[),&])',
  caseSensitive: false,
);

/// Splits a raw artist credit string into its individual credited artists.
///
/// `"Daft Punk"` passes through whole, while `"Chance the Rapper feat.
/// Noname"`, `"A ft B"`, `"A featuring B"`, and parenthesized variants like
/// `"A (feat. B)"` are each broken apart. The first entry is the primary
/// credit; the remainder are the featured/credited artists. Entries are
/// trimmed, empty segments dropped, and duplicates collapsed keeping the
/// first occurrence. Returns an empty list when [raw] is null or blank.
List<String> splitArtists(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return const [];
  }
  final normalized = raw
      .replaceAll('(', ' ')
      .replaceAll(')', ' ')
      .replaceAll(_featMarker, ' \u0000');
  final parts = <String>[];
  for (final chunk in normalized.split('\u0000')) {
    final trimmed = chunk.trim().replaceFirst(RegExp(r'^[-,&]\s*'), '');
    if (trimmed.isNotEmpty && !parts.contains(trimmed)) {
      parts.add(trimmed);
    }
  }
  return parts;
}

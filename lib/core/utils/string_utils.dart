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
/// Multi-artist credits are broken apart on every supported separator:
/// `", "`, `"&"`, and the feat markers `"ft."` / `"feat."` / `"featuring"`.
/// `"Daft Punk"` passes through whole, while `"Atif Aslam, Pritam"`,
/// `"A & B"`, `"Chance the Rapper feat. Noname"`, and parenthesized variants
/// like `"A (feat. B)"` are each broken apart. Entries are trimmed, empty
/// segments dropped, and duplicates collapsed keeping the first occurrence.
/// Returns an empty list when [raw] is null or blank.
///
/// The raw combined credit is intentionally NOT returned here; the repository
/// records it separately so a grouped-credit artist page (e.g.
/// "Atif Aslam, Pritam") also exists alongside the individual pages.
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
    // Commas and ampersands separate credited artists within a chunk.
    for (final piece in chunk.split(_creditSeparator)) {
      final trimmed = piece.trim().replaceFirst(RegExp(r'^[-,&]\s*'), '');
      if (trimmed.isNotEmpty && !parts.contains(trimmed)) {
        parts.add(trimmed);
      }
    }
  }
  return parts;
}

/// Characters that separate credited artists inside one credit string.
final RegExp _creditSeparator = RegExp(r'[,;&]');

/// Whether [raw] contains a multi-artist group separator (comma, semicolon,
/// or ampersand) — i.e. the credit itself names a group of artists rather
/// than a single artist or a feat. pairing.
bool hasGroupSeparator(String? raw) =>
    raw != null && _creditSeparator.hasMatch(raw);

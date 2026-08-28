// Local, dependency-free search ranking and fuzzy matching.
//
// Kept deliberately SQL/`package`-free so it can run on the UI isolate without
// FTS5 and stay testable. It ranks a bounded set of substring/prefix candidates
// (selected by an indexed LIKE query) by how well they match the query, and
// admits near-miss tokens via Levenshtein edit distance for light typo
// tolerance. This is intentionally bounded — it never scans the whole library
// on every keystroke.

/// Levenshtein edit distance between two strings.
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      curr[j] = [
        prev[j] + 1,
        curr[j - 1] + 1,
        prev[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }

  return prev[b.length];
}

/// Whether every significant query token matches some token in [fieldText],
/// allowing up to [maxDistance] single-character edits per token.
///
/// Short tokens (< 4 chars) must match exactly to avoid noise. A query token
/// matches a candidate token if they are equal or within the edit distance.
bool tokenFuzzyMatch(String query, String fieldText, {int maxDistance = 1}) {
  final qTokens = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (qTokens.isEmpty) return true;

  final fieldTokens = fieldText
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (fieldTokens.isEmpty) return false;

  for (final qt in qTokens) {
    var matched = false;
    for (final ft in fieldTokens) {
      if (ft == qt ||
          (ft.length >= 4 &&
              qt.length >= 4 &&
              levenshtein(ft, qt) <= maxDistance)) {
        matched = true;
        break;
      }
    }
    if (!matched) return false;
  }
  return true;
}

/// Ranks one candidate given which fields matched. Higher is better.
///
///  * exact equality wins
///  * word/space-prefix beats bare substring
///  * title matches beat artist/album matches
int relevanceScore({
  required String query,
  required String title,
  required String artist,
  required String album,
}) {
  final q = query.toLowerCase().trim();
  final t = title.toLowerCase();
  final a = artist.toLowerCase();
  final al = album.toLowerCase();

  if (t == q) return 1000;
  if (a == q) return 900;
  if (al == q) return 800;

  int fieldScore(String field, int base) {
    if (field == q) return base + 500;
    if (field.startsWith(q)) return base + 300; // prefix
    if (field.contains(' $q') || field.startsWith('$q ')) return base + 200;
    if (field.contains(q)) return base + 100;
    return 0;
  }

  final score = [
    fieldScore(t, 400),
    fieldScore(a, 300),
    fieldScore(al, 200),
  ].reduce((x, y) => x > y ? x : y);

  // Small bonus for matches across the earliest query token, so partial
  // multi-word queries still surface the most relevant titles.
  return score;
}

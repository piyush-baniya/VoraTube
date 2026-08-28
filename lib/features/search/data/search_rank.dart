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

/// Normalizes a piece of text for search comparison.
///
/// Lowercases, drops apostrophes entirely (so "don't" and "dont", and
/// "o'clock" and "oclock", align), then collapses every remaining run of
/// non-alphanumeric characters — spaces, dashes, dots and punctuation — down
/// to a single space. Letters and digits (including accented/Unicode letters)
/// are preserved, so "Beyoncé" stays distinct while noise like "100%" and
/// "a.b,c-d" normalizes cleanly.
String normalizeSearchText(String input) {
  var s = input.toLowerCase().replaceAll("'", '');
  s = s.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ');
  return s.trim();
}

/// The normalized, non-empty tokens of a query or piece of text.
///
/// These are the units that typo-tolerant matching and per-token candidate
/// selection both operate on.
List<String> searchTokens(String text) {
  return normalizeSearchText(text)
      .split(' ')
      .where((t) => t.isNotEmpty)
      .toList();
}

/// Whether every significant query token matches some token in [fieldText],
/// allowing up to [maxDistance] single-character edits per token.
///
/// Short tokens (< 4 chars) must match exactly to avoid noise. A query token
/// matches a candidate token if they are equal or within the edit distance.
/// Both sides are normalized (case/punctuation/apostrophes) before matching.
bool tokenFuzzyMatch(String query, String fieldText, {int maxDistance = 1}) {
  final qTokens = searchTokens(query);
  if (qTokens.isEmpty) return true;

  final fieldTokens = searchTokens(fieldText);
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
  final q = normalizeSearchText(query);
  final t = normalizeSearchText(title);
  final a = normalizeSearchText(artist);
  final al = normalizeSearchText(album);

  if (t == q) return 1000;
  if (a == q) return 900;
  if (al == q) return 800;

  int fieldScore(String field, int base, String rawLabel) {
    if (field == q) return base + 500;
    if (field.startsWith(q)) return base + 300; // prefix
    if (field.contains(' $q') || field.startsWith('$q ')) return base + 200;
    if (field.contains(q)) return base + 100;
    // No exact/prefix/word/substring hit, but the overall match admitted this
    // field only through typo tolerance — keep it above a pure miss, yet below
    // every clean partial match, preserving exact -> prefix -> partial -> fuzzy.
    if (rawLabel.isNotEmpty && tokenFuzzyMatch(q, rawLabel)) return base + 40;
    return 0;
  }

  final score = [
    fieldScore(t, 400, title),
    fieldScore(a, 300, artist),
    fieldScore(al, 200, album),
  ].reduce((x, y) => x > y ? x : y);

  // Small bonus for matches across the earliest query token, so partial
  // multi-word queries still surface the most relevant titles.
  return score;
}

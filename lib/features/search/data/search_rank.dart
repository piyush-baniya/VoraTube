// Local, dependency-free search ranking and match highlighting.
//
// Kept deliberately SQL/`package`-free so it can run on the UI isolate without
// FTS5 and stay testable. Search is intentionally simple: candidates are
// selected by an indexed LIKE query and then filtered/ranked by plain,
// case-insensitive substring matching. There is deliberately NO typo
// correction, fuzzy ranking, spelling suggestions, or
// exact -> prefix -> partial -> fuzzy pipeline — a query token must actually
// appear in the text to match.

/// Marks a run of characters within a search result as a match or not, so the
/// UI can highlight the part of the title/metadata that matched the query.
final class HighlightSpan {
  const HighlightSpan({required this.text, required this.highlight});

  final String text;
  final bool highlight;
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

/// Case-insensitive partial (substring) match with no typo tolerance.
///
/// Every normalized query token must appear as a substring somewhere in the
/// normalized [text]. `Blind`, `Lights` and `blinding` all match
/// "Blinding Lights", but a misspelt token such as `dragins` is not corrected
/// against "Imagine Dragons".
bool matchesPartial(String query, String text) {
  final qTokens = searchTokens(query);
  if (qTokens.isEmpty) return true;

  final normalized = normalizeSearchText(text);
  if (normalized.isEmpty) return false;

  for (final qt in qTokens) {
    if (qt.isEmpty || !normalized.contains(qt)) return false;
  }
  return true;
}

/// Convenience alias kept so existing callers keep working. Now that fuzzy
/// matching has been removed, this simply delegates to [matchesPartial].
bool tokenFuzzyMatch(String query, String fieldText, {int maxDistance = 1}) {
  return matchesPartial(query, fieldText);
}

/// Splits [text] into [HighlightSpan]s, flagging the substrings that match any
/// normalized query token (case-insensitive). Matching text is highlighted so
/// the UI can render the matched fragment distinctly.
///
/// This is cheap and allocation-bounded: it marks a per-character boolean mask
/// and walks it once, producing at most a small number of spans. It never
/// rebuilds the surrounding widget tree.
List<HighlightSpan> highlightOccurrences(String text, String query) {
  final tokens = searchTokens(query);
  if (tokens.isEmpty || text.isEmpty) {
    return [HighlightSpan(text: text, highlight: false)];
  }

  final n = text.length;
  final mask = List<bool>.filled(n, false);
  final lower = text.toLowerCase();

  for (final token in tokens) {
    if (token.isEmpty) continue;
    var start = 0;
    while (start <= lower.length - token.length) {
      final idx = lower.indexOf(token, start);
      if (idx < 0) break;
      for (var i = idx; i < idx + token.length; i++) {
        mask[i] = true;
      }
      start = idx + token.length;
    }
  }

  final spans = <HighlightSpan>[];
  var i = 0;
  while (i < n) {
    final isMatch = mask[i];
    final runStart = i;
    while (i < n && mask[i] == isMatch) {
      i++;
    }
    spans.add(
      HighlightSpan(text: text.substring(runStart, i), highlight: isMatch),
    );
  }
  return spans;
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
  if (q.isEmpty) return 0;
  final t = normalizeSearchText(title);
  final a = normalizeSearchText(artist);
  final al = normalizeSearchText(album);

  if (t == q) return 1000;
  if (a == q) return 900;
  if (al == q) return 800;

  int fieldScore(String field, int base) {
    if (field == q) return base + 500;
    if (field.startsWith(q)) return base + 320; // prefix
    if (field.contains(' $q') || field.startsWith('$q ')) return base + 220;
    if (field.contains(q)) return base + 120; // bare substring
    return 0;
  }

  final score = [
    fieldScore(t, 400),
    fieldScore(a, 300),
    fieldScore(al, 200),
  ].reduce((x, y) => x > y ? x : y);

  return score;
}

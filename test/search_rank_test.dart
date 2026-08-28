import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/features/search/data/search_rank.dart';

void main() {
  group('levenshtein', () {
    test('distance is zero for identical strings', () {
      expect(levenshtein('drake', 'drake'), 0);
    });

    test('distance counts single edit', () {
      expect(levenshtein('kitten', 'sitten'), 1);
      expect(levenshtein('apple', 'aple'), 1);
    });

    test('distance grows with unrelated words', () {
      expect(levenshtein('drizzy', 'drake'), greaterThan(1));
    });

    test('distance for empty strings', () {
      expect(levenshtein('', ''), 0);
      expect(levenshtein('abc', ''), 3);
    });
  });

  group('tokenFuzzyMatch', () {
    test('matches exact tokens ignoring case', () {
      expect(tokenFuzzyMatch('drake', 'Drake'), true);
    });

    test('matches typos within edit distance', () {
      expect(tokenFuzzyMatch('drizzy', 'drizzy'), true);
      expect(tokenFuzzyMatch('drizzy drake', 'drizzy drake'), true);
    });

    test('rejects clearly different tokens', () {
      expect(tokenFuzzyMatch('coldplay', 'drake'), false);
    });

    test('short tokens must match exactly to avoid noise', () {
      expect(tokenFuzzyMatch('drake', 'drake123'), false);
    });

    test('admitted the spec typo examples across tokens', () {
      expect(tokenFuzzyMatch('imagine dragins', 'Imagine Dragons'), true);
      expect(tokenFuzzyMatch('linkn park', 'Linkin Park'), true);
      expect(tokenFuzzyMatch('weeknd', 'The Weeknd'), true);
    });

    test('normalizes case, spaces, punctuation and apostrophes', () {
      expect(tokenFuzzyMatch("o'clock", 'o clock'), true);
      expect(tokenFuzzyMatch("o'clock", 'oclock'), true);
      expect(tokenFuzzyMatch('  hello   world ', 'hello world'), true);
      expect(tokenFuzzyMatch('hello-world', 'hello world'), true);
    });

    test('unrelated multi-token query is rejected', () {
      expect(tokenFuzzyMatch('quantum blender', 'Imagine Dragons'), false);
    });
  });

  group('searchTokens / normalizeSearchText', () {
    test('tokenizes normalized text with apostrophes stripped', () {
      expect(searchTokens("Beyoncé o'clock 100%"), [
        'beyoncé',
        'oclock',
        '100',
      ]);
    });

    test('preserves Unicode letters', () {
      expect(normalizeSearchText('Beyoncé'), 'beyoncé');
    });

    test('strips apostrophes and punctuation into spaces', () {
      expect(normalizeSearchText("don't stop"), 'dont stop');
      expect(normalizeSearchText('a.b,c-d'), 'a b c d');
    });
  });

  group('relevanceScore', () {
    test('exact title beats prefix which beats substring', () {
      final exact = relevanceScore(
        query: 'hello',
        title: 'Hello',
        artist: 'Adele',
        album: '25',
      );
      final prefix = relevanceScore(
        query: 'hel',
        title: 'Hello',
        artist: 'Adele',
        album: '25',
      );
      final substring = relevanceScore(
        query: 'llo',
        title: 'Hello',
        artist: 'Adele',
        album: '25',
      );
      expect(exact, greaterThan(prefix));
      expect(prefix, greaterThan(substring));
    });

    test('exact title match ranks above exact artist match', () {
      final titleExact = relevanceScore(
        query: 'adele',
        title: 'Adele',
        artist: 'Adele',
        album: '',
      );
      final artistExact = relevanceScore(
        query: 'adele',
        title: 'Song',
        artist: 'Adele',
        album: '',
      );
      expect(titleExact, greaterThan(artistExact));
    });

    test('preserves exact -> prefix -> partial -> fuzzy ranking', () {
      final exact = relevanceScore(
        query: 'imagine dragons',
        title: 'Imagine Dragons',
        artist: 'Imagine Dragons',
        album: '',
      );
      final prefix = relevanceScore(
        query: 'imagine',
        title: 'Imagine Dragons',
        artist: '',
        album: '',
      );
      final partial = relevanceScore(
        query: 'agine dragons',
        title: 'Imagine Dragons',
        artist: '',
        album: '',
      );
      final fuzzy = relevanceScore(
        query: 'imagine dragins',
        title: 'Imagine Dragons',
        artist: '',
        album: '',
      );
      expect(exact, greaterThan(prefix));
      expect(prefix, greaterThan(partial));
      expect(partial, greaterThan(fuzzy));
      expect(fuzzy, greaterThan(0));
    });
  });
}

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
  });
}

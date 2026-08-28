import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/features/search/data/search_rank.dart';

void main() {
  group('tokenFuzzyMatch (now simple partial matching)', () {
    test('matches tokens via substring, ignoring case', () {
      expect(tokenFuzzyMatch('drake', 'Drake'), true);
      expect(tokenFuzzyMatch('drizzy drake', 'drizzy drake'), true);
    });

    test(
      'partial tokens match as substrings',
      () => expect(tokenFuzzyMatch('blind', 'Blinding Lights'), true),
    );

    test('rejects clearly different tokens', () {
      expect(tokenFuzzyMatch('coldplay', 'drake'), false);
    });

    test('typos are NOT corrected (fuzzy search removed)', () {
      expect(tokenFuzzyMatch('imagine dragins', 'Imagine Dragons'), false);
      expect(tokenFuzzyMatch('linkn park', 'Linkin Park'), false);
    });

    test('normalizes case, spaces and punctuation', () {
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

    test('exact -> prefix -> partial ranking, no fuzzy tier', () {
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
      final typo = relevanceScore(
        query: 'imagine dragins',
        title: 'Imagine Dragons',
        artist: '',
        album: '',
      );
      expect(exact, greaterThan(prefix));
      expect(prefix, greaterThan(partial));
      expect(typo, 0); // misspelt queries no longer match at all
    });
  });
}

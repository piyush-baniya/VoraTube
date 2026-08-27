import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../library/data/library_models.dart';
import '../../../library/data/library_repository.dart';
import '../../../library/presentation/providers/library_providers.dart';

/// Debounces raw search input by 250 ms before it becomes the active query.
class _SearchDebounce extends StateNotifier<String> {
  _SearchDebounce() : super('');

  Timer? _timer;

  void submit(String text) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), () {
      state = text.trim();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final _searchDebounceProvider = StateNotifierProvider<_SearchDebounce, String>(
  (ref) => _SearchDebounce(),
);

/// Debounced (250 ms) normalized query actually used for searching.
final debouncedSearchQueryProvider = Provider<String>(
  (ref) => ref.watch(_searchDebounceProvider),
);

void submitSearchText(WidgetRef ref, String text) {
  ref.read(_searchDebounceProvider.notifier).submit(text);
}

final searchResultsProvider = FutureProvider.autoDispose<SearchResults>((
  ref,
) async {
  final query = ref.watch(debouncedSearchQueryProvider);
  if (query.isEmpty) {
    return const SearchResults(
      query: '',
      songs: [],
      albums: [],
      artists: [],
      playlists: [],
    );
  }
  final repository = ref.watch(libraryRepositoryProvider);
  return repository.searchAll(query);
});

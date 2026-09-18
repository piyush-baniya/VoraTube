import '../../../core/ui_customization/ui_layout.dart';
import '../../library/data/library_repository.dart';

/// Minimal key/value surface the layout store persists through. Keeping it
/// separate from [LibraryRepository] lets the store be tested without a
/// database and leaves room for a different backing store later.
abstract interface class LayoutKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// The production store: the existing app KV table, which already backs the
/// settings blobs.
class LibraryLayoutKeyValueStore implements LayoutKeyValueStore {
  LibraryLayoutKeyValueStore(this._repository);

  final LibraryRepository _repository;

  @override
  Future<String?> read(String key) => _repository.kvGet(key);

  @override
  Future<void> write(String key, String value) => _repository.kvSet(key, value);
}

/// Persists the user's layout profile.
abstract interface class LayoutRepository {
  /// Returns null when nothing valid is stored (first run, cleared data or a
  /// corrupt blob). Corrupt data is never surfaced as an error.
  Future<LayoutProfile?> load();

  Future<void> save(LayoutProfile profile);
}

/// Versioned KV implementation. The key carries the schema version so a future
/// incompatible schema can move to a new key without touching old rows.
class KvLayoutRepository implements LayoutRepository {
  KvLayoutRepository(this._store);

  static const String storageKey = 'settings.uiLayout.v1';

  final LayoutKeyValueStore _store;

  @override
  Future<LayoutProfile?> load() async {
    try {
      final raw = await _store.read(storageKey);
      if (raw == null || raw.isEmpty) return null;
      return LayoutProfile.tryDecode(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(LayoutProfile profile) =>
      _store.write(storageKey, profile.encode());
}

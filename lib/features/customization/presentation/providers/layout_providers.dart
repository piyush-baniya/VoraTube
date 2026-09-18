import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui_customization/ui_component_registry.dart';
import '../../../../core/ui_customization/ui_layout.dart';
import '../../../../core/ui_customization/ui_layout_normalizer.dart';
import '../../../library/data/library_models.dart';
import '../../../library/data/library_repository.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../../../library/presentation/providers/library_view_providers.dart';
import '../../data/layout_repository.dart';

/// The component definitions the UI edits against.
final uiComponentRegistryProvider = Provider<UiComponentRegistry>(
  (ref) => homeComponentRegistry,
);

/// The registry for any customizable screen. Unknown screens fall back to the
/// Home registry so lookup never throws.
final screenRegistryProvider = Provider.family<UiComponentRegistry, String>((
  ref,
  screenId,
) {
  return switch (screenId) {
    kPlayerScreenId => playerComponentRegistry,
    kMiniScreenId => miniComponentRegistry,
    kEqualizerScreenId => equalizerComponentRegistry,
    _ => homeComponentRegistry,
  };
});

/// Every customizable screen id and its registry.
Map<String, UiComponentRegistry> get layoutSceneRegistries => const {
  kHomeScreenId: homeComponentRegistry,
  kPlayerScreenId: playerComponentRegistry,
  kMiniScreenId: miniComponentRegistry,
  kEqualizerScreenId: equalizerComponentRegistry,
};

final layoutRepositoryProvider = Provider<LayoutRepository>((ref) {
  return KvLayoutRepository(
    LibraryLayoutKeyValueStore(ref.watch(libraryRepositoryProvider)),
  );
});

/// Loads, normalizes and persists the active [LayoutProfile].
///
/// The in-memory value is the source of truth for rendering; the stored blob is
/// only read on creation. A missing or corrupt blob resolves to the default
/// layout that reproduces the pre-customization UI.
class LayoutProfileController extends AsyncNotifier<LayoutProfile> {
  @override
  Future<LayoutProfile> build() async {
    final registry = ref.watch(uiComponentRegistryProvider);
    final stored = await ref.watch(layoutRepositoryProvider).load();
    if (stored == null) {
      return defaultLayoutProfile(
        registry,
        registries: layoutSceneRegistries,
        screens: kLayoutScreenIds,
      );
    }
    return normalizeLayoutProfile(
      stored,
      registry,
      extraRegistries: layoutSceneRegistries,
    );
  }

  Future<void> save(LayoutProfile profile) async {
    final registry = ref.read(uiComponentRegistryProvider);
    final normalized = normalizeLayoutProfile(
      profile,
      registry,
      extraRegistries: layoutSceneRegistries,
    );
    state = AsyncData(normalized);
    await ref.read(layoutRepositoryProvider).save(normalized);
  }

  /// Applies a curated preset to every screen and variant and commits it.
  Future<void> applyPreset(LayoutPreset preset) async {
    final layouts = <LayoutKey, ScreenLayout>{};
    for (final screenId in kLayoutScreenIds) {
      final registry = layoutSceneRegistries[screenId]!;
      for (final variant in LayoutVariant.values) {
        layouts[LayoutKey(screenId, variant)] = applyLayoutPreset(
          preset,
          screenId,
          registry,
        );
      }
    }
    await save(LayoutProfile(preset: preset, layouts: layouts));
  }

  /// Restores the default layout for every screen and commits it.
  Future<void> reset() async {
    final registry = ref.read(uiComponentRegistryProvider);
    await save(
      defaultLayoutProfile(
        registry,
        registries: layoutSceneRegistries,
        screens: kLayoutScreenIds,
      ),
    );
  }
}

final layoutProfileProvider =
    AsyncNotifierProvider<LayoutProfileController, LayoutProfile>(
      LayoutProfileController.new,
    );

/// The resolved Home layout for one device variant. Falls back to the default
/// arrangement until the profile has loaded, so Home never shows a hole.
final homeScreenLayoutProvider = Provider.family<ScreenLayout, LayoutVariant>((
  ref,
  variant,
) {
  final registry = ref.watch(uiComponentRegistryProvider);
  final profile = ref.watch(layoutProfileProvider).valueOrNull;
  if (profile == null) return defaultScreenLayout(kHomeScreenId, registry);
  return profile.screenLayout(kHomeScreenId, variant) ??
      defaultScreenLayout(kHomeScreenId, registry);
});

/// The resolved full player layout for one device variant. Until the profile
/// loads (or the profile has no player entry) this yields the player default.
final playerScreenLayoutProvider = Provider.family<ScreenLayout, LayoutVariant>(
  (ref, variant) {
    final profile = ref.watch(layoutProfileProvider).valueOrNull;
    if (profile == null) {
      return defaultScreenLayout(kPlayerScreenId, playerComponentRegistry);
    }
    return profile.screenLayout(kPlayerScreenId, variant) ??
        defaultScreenLayout(kPlayerScreenId, playerComponentRegistry);
  },
);

/// The resolved mini player layout for one device variant, mirroring
/// [playerScreenLayoutProvider].
final miniScreenLayoutProvider = Provider.family<ScreenLayout, LayoutVariant>((
  ref,
  variant,
) {
  final profile = ref.watch(layoutProfileProvider).valueOrNull;
  if (profile == null) {
    return defaultScreenLayout(kMiniScreenId, miniComponentRegistry);
  }
  return profile.screenLayout(kMiniScreenId, variant) ??
      defaultScreenLayout(kMiniScreenId, miniComponentRegistry);
});

/// The resolved equalizer layout for one device variant. The curve is a
/// protected component, so even a stored profile that tried to hide it is
/// normalized back to visible by [layoutProfileProvider].
final equalizerScreenLayoutProvider =
    Provider.family<ScreenLayout, LayoutVariant>((ref, variant) {
      final profile = ref.watch(layoutProfileProvider).valueOrNull;
      if (profile == null) {
        return defaultScreenLayout(
          kEqualizerScreenId,
          equalizerComponentRegistry,
        );
      }
      return profile.screenLayout(kEqualizerScreenId, variant) ??
          defaultScreenLayout(kEqualizerScreenId, equalizerComponentRegistry);
    });

/// Home "All Songs" preview size for a component size preset.
int homePreviewLimitFor(ComponentSize size) => switch (size) {
  ComponentSize.small => 6,
  ComponentSize.medium => homeSongsLimit,
  ComponentSize.large => 20,
};

/// Home "All Songs" preview at an explicit row count. Separate from
/// [homeSongsProvider] (which stays pinned to [homeSongsLimit]) so the default
/// medium size reproduces existing behavior exactly while other sizes stay
/// provider-family cached.
final homeSongsPreviewProvider = FutureProvider.autoDispose
    .family<List<SongTileData>, int>((ref, limit) async {
      ref.watch(libraryRefreshTickProvider);
      final repository = ref.watch(libraryRepositoryProvider);
      final page = await repository.songsPage(
        limit: limit,
        offset: 0,
        sort: SongSort.recentlyAdded,
        favoritesOnly: false,
      );
      return page.songs;
    });

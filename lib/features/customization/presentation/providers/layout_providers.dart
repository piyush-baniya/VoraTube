import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui_customization/layout_edit_session.dart';
import '../../../../core/ui_customization/layout_geometry.dart';
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

/// The profile the UI renders: the live edit session while the customization
/// editor is open, otherwise the persisted profile. This is what the per-screen
/// layout providers read, so the real screens re-render every edit live.
final resolvedLayoutProfileProvider = Provider<LayoutProfile?>((ref) {
  final editing = ref.watch(layoutEditSessionProvider);
  if (editing != null) return editing;
  return ref.watch(layoutProfileProvider).valueOrNull;
});

/// The live customization session. While [state] is non-null the app renders
/// the in-progress profile on the screen being edited; [save] commits it to
/// the persisted profile and [cancel] discards it.
class LayoutEditController extends Notifier<LayoutProfile?> {
  LayoutEditSession? _session;

  LayoutEditSession? get session => _session;
  bool get isEditing => _session != null;
  bool get isDirty => _session?.isDirty ?? false;
  bool get canUndo => _session?.canUndo ?? false;
  bool get canRedo => _session?.canRedo ?? false;

  @override
  LayoutProfile? build() => null;

  void begin(String screenId, LayoutProfile baseline) {
    _session = LayoutEditSession(baseline: baseline);
    state = baseline;
  }

  /// Applies a freeform placement as ONE undoable step. The canvas updates a
  /// per-block visual during the gesture and calls this once on release; the
  /// whole drag/resize collapses into a single undo entry.
  void commitRect(
    String screenId,
    LayoutVariant variant,
    String componentId,
    NormalizedRect rect,
  ) {
    final layout = state?.screenLayout(screenId, variant);
    if (layout == null) return;
    final component = layout.component(componentId);
    if (component == null) return;
    _session?.beginGesture();
    _session?.applyLive(
      state!.replaceScreen(
        screenId,
        variant,
        layout.replaceComponent(component.copyWith(rect: rect)),
      ),
    );
    _session?.commitGesture();
    state = _session?.current;
  }

  void _apply(LayoutProfile next) {
    _session?.apply(next);
    state = _session?.current;
  }

  ScreenLayout? screenLayout(String screenId, LayoutVariant variant) =>
      state?.screenLayout(screenId, variant);

  void updateComponent(
    String screenId,
    LayoutVariant variant,
    ComponentLayout updated,
  ) {
    final layout = state?.screenLayout(screenId, variant);
    if (layout == null) return;
    _apply(
      state!.replaceScreen(screenId, variant, layout.replaceComponent(updated)),
    );
  }

  void moveComponent(
    String screenId,
    LayoutVariant variant,
    int oldIndex,
    int newIndex,
  ) {
    final layout = state?.screenLayout(screenId, variant);
    final registry = layoutSceneRegistries[screenId];
    if (layout == null || registry == null) return;
    final components = [...layout.components];
    if (oldIndex < 0 || oldIndex >= components.length) return;
    final moved = components.removeAt(oldIndex);
    final definition = registry.definitionFor(moved.id);
    if (definition == null || !definition.canReorder) return;
    newIndex = newIndex.clamp(0, components.length);
    components.insert(newIndex, moved);
    final ordered = screenId == kPlayerScreenId
        ? groupPlayerZones(components)
        : components;
    _apply(
      state!.replaceScreen(
        screenId,
        variant,
        ScreenLayout(screenId: screenId, components: ordered),
      ),
    );
  }

  void hide(String screenId, LayoutVariant variant, String componentId) {
    final layout = state?.screenLayout(screenId, variant);
    final registry = layoutSceneRegistries[screenId];
    if (layout == null || registry == null) return;
    final definition = registry.definitionFor(componentId);
    final component = layout.component(componentId);
    if (definition == null || component == null || !definition.canHide) return;
    _apply(
      state!.replaceScreen(
        screenId,
        variant,
        layout.replaceComponent(component.copyWith(visible: false)),
      ),
    );
  }

  void restore(String screenId, LayoutVariant variant, String componentId) {
    final layout = state?.screenLayout(screenId, variant);
    if (layout == null) return;
    final component = layout.component(componentId);
    if (component == null) return;
    _apply(
      state!.replaceScreen(
        screenId,
        variant,
        layout.replaceComponent(component.copyWith(visible: true)),
      ),
    );
  }

  void setSize(
    String screenId,
    LayoutVariant variant,
    String componentId,
    ComponentSize size,
  ) {
    final layout = state?.screenLayout(screenId, variant);
    final registry = layoutSceneRegistries[screenId];
    if (layout == null || registry == null) return;
    final definition = registry.definitionFor(componentId);
    final component = layout.component(componentId);
    if (definition == null ||
        component == null ||
        !definition.canResize ||
        !definition.supportsSize(size)) {
      return;
    }
    _apply(
      state!.replaceScreen(
        screenId,
        variant,
        layout.replaceComponent(component.copyWith(size: size)),
      ),
    );
  }

  void setStyle(
    String screenId,
    LayoutVariant variant,
    String componentId,
    String? styleId,
  ) {
    final layout = state?.screenLayout(screenId, variant);
    final registry = layoutSceneRegistries[screenId];
    if (layout == null || registry == null) return;
    final definition = registry.definitionFor(componentId);
    final component = layout.component(componentId);
    if (definition == null || component == null) return;
    final nextStyle = definition.supportsStyle(styleId)
        ? styleId
        : definition.effectiveDefaultStyleId;
    _apply(
      state!.replaceScreen(
        screenId,
        variant,
        layout.replaceComponent(component.copyWith(styleId: nextStyle)),
      ),
    );
  }

  void resetComponent(
    String screenId,
    LayoutVariant variant,
    String componentId,
  ) {
    final layout = state?.screenLayout(screenId, variant);
    final registry = layoutSceneRegistries[screenId];
    if (layout == null || registry == null) return;
    final definition = registry.definitionFor(componentId);
    if (definition == null) return;
    final restored = definition
        .defaultLayout()
        .copyWith(
          rect: defaultGeometryFor(
            screenId,
            variant,
            componentId,
          ),
        );
    _apply(
      state!.replaceScreen(screenId, variant, layout.replaceComponent(restored)),
    );
  }

  void applyPreset(LayoutPreset preset, String screenId) {
    final registry = layoutSceneRegistries[screenId];
    if (registry == null || state == null) return;
    final layouts = <LayoutKey, ScreenLayout>{...state!.layouts};
    for (final variant in LayoutVariant.values) {
      layouts[LayoutKey(screenId, variant)] = applyLayoutPreset(
        preset,
        screenId,
        registry,
      );
    }
    _apply(state!.copyWith(preset: preset, layouts: layouts));
  }

  void reset(String screenId) {
    final registry = layoutSceneRegistries[screenId];
    if (registry == null || state == null) return;
    final layouts = <LayoutKey, ScreenLayout>{...state!.layouts};
    for (final variant in LayoutVariant.values) {
      layouts[LayoutKey(screenId, variant)] = defaultScreenLayout(
        screenId,
        registry,
      );
    }
    _apply(state!.copyWith(preset: LayoutPreset.standard, layouts: layouts));
  }

  void undo() {
    if (_session?.undo() == true) state = _session!.current;
  }

  void redo() {
    if (_session?.redo() == true) state = _session!.current;
  }

  /// Commits the session to the persisted profile and ends editing. Geometry is
  /// materialized first so any component that was not touched during the edit
  /// still ends up with a guaranteed placement.
  Future<void> save() async {
    final session = _session;
    if (session == null) return;
    final toPersist = ensureProfileGeometry(
      session.current,
      registries: layoutSceneRegistries,
    );
    await ref
        .read(layoutProfileProvider.notifier)
        .save(toPersist);
    _session = null;
    state = null;
  }

  /// Discards any uncommitted edits and ends editing.
  void cancel() {
    _session = null;
    state = null;
  }
}

final layoutEditSessionProvider =
    NotifierProvider<LayoutEditController, LayoutProfile?>(
      LayoutEditController.new,
    );

/// The resolved Home layout for one device variant. Falls back to the default
/// arrangement until the profile has loaded, so Home never shows a hole.
final homeScreenLayoutProvider = Provider.family<ScreenLayout, LayoutVariant>((
  ref,
  variant,
) {
  final registry = ref.watch(uiComponentRegistryProvider);
  final profile = ref.watch(resolvedLayoutProfileProvider);
  if (profile == null) return defaultScreenLayout(kHomeScreenId, registry);
  return profile.screenLayout(kHomeScreenId, variant) ??
      defaultScreenLayout(kHomeScreenId, registry);
});

/// The resolved full player layout for one device variant. Until the profile
/// loads (or the profile has no player entry) this yields the player default.
final playerScreenLayoutProvider = Provider.family<ScreenLayout, LayoutVariant>(
  (ref, variant) {
    final profile = ref.watch(resolvedLayoutProfileProvider);
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
  final profile = ref.watch(resolvedLayoutProfileProvider);
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
      final profile = ref.watch(resolvedLayoutProfileProvider);
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

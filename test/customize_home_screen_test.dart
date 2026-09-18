import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/core/ui_customization/ui_component_registry.dart';
import 'package:vora_tube/core/ui_customization/ui_layout.dart';
import 'package:vora_tube/core/ui_customization/ui_layout_normalizer.dart';
import 'package:vora_tube/features/customization/data/layout_repository.dart';
import 'package:vora_tube/features/customization/presentation/providers/layout_providers.dart';
import 'package:vora_tube/features/customization/presentation/screens/customize_interface_screen.dart';
import 'package:vora_tube/features/customization/presentation/screens/live_layout_editor.dart';
import 'package:vora_tube/features/customization/presentation/widgets/freeform_layout_canvas.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';

import 'fakes/fake_player.dart';

class _MemoryStore implements LayoutKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  LayoutProfile? get profile {
    final raw = values[KvLayoutRepository.storageKey];
    return raw == null ? null : LayoutProfile.tryDecode(raw);
  }
}

void _usePortrait(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Map<LayoutKey, ScreenLayout> _standardScreenLayouts() {
  return {
    for (final screenId in kLayoutScreenIds)
      for (final variant in LayoutVariant.values)
        LayoutKey(screenId, variant): applyLayoutPreset(
          LayoutPreset.standard,
          screenId,
          layoutSceneRegistries[screenId]!,
        ),
  };
}

/// Seeds a non-default (minimal) Home layout for the reset test.
void _seedNonDefaultHome(_MemoryStore store) {
  final layouts = _standardScreenLayouts();
  final seeded = LayoutProfile(
    preset: LayoutPreset.minimal,
    layouts: {
      for (final variant in LayoutVariant.values)
        LayoutKey(kHomeScreenId, variant): applyLayoutPreset(
          LayoutPreset.minimal,
          kHomeScreenId,
          homeComponentRegistry,
        ),
      // Leave the other screens on their standard arrangements so only Home is
      // out of sync with the seed preset.
      for (final entry in layouts.entries)
        if (entry.key.screenId != kHomeScreenId) entry.key: entry.value,
    },
  );
  store.values[KvLayoutRepository.storageKey] = seeded.encode();
}

void main() {
  late AppDatabase db;
  late LibraryRepository repository;
  late FakePlayerController player;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = LibraryRepository(db);
    player = FakePlayerController(
      initial: PlayerSnapshot(
        status: PlayerStatus.ready,
        isPlaying: false,
        repeatMode: RepeatMode.off,
        shuffleEnabled: false,
        queueLength: 0,
        currentIndex: -1,
        durationMs: 0,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  ProviderScope _wrap(_MemoryStore store, Widget child) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        libraryRepositoryProvider.overrideWithValue(repository),
        playerProvider.overrideWithValue(player),
        layoutRepositoryProvider.overrideWithValue(KvLayoutRepository(store)),
      ],
      child: MaterialApp(home: child),
    );
  }

  Future<void> _openHomeEditor(WidgetTester tester, _MemoryStore store) async {
    await tester.pumpWidget(_wrap(store, const CustomizeInterfaceScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
  }

  /// The label chip floats over the selected block (definition label + size).
  Finder _chip(String text) => find.text(text);

  /// Tap the Continue Listening block's surface. With no current track the
  /// canvas surface shows its empty-state prompt; the block itself is the
  /// tappable target regardless of the IgnorePointer-wrapped surface.
  Future<void> _selectContinueListening(WidgetTester tester) async {
    await tester.tap(find.text('Start Listening'), warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  Future<void> _hideContinueListening(WidgetTester tester) async {
    await _selectContinueListening(tester);
    await tester.tap(_chip('Continue Listening (Medium)'));
    await tester.pumpAndSettle();
    // The block menu sheet can exceed the visible area on small screens, so
    // scroll the Hide action into view before tapping.
    await tester.ensureVisible(find.text('Hide'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
  }

  /// Drag Continue Listening from a point clearly inside its canvas block
  /// (the floating chip and the IgnorePointer-wrapped surface are avoided).
  Future<void> _dragContinueListening(
    WidgetTester tester,
    Offset offset,
  ) async {
    final canvas = tester.getRect(find.byType(FreeformLayoutCanvas));
    final start =
        canvas.topLeft + Offset(canvas.width * 0.8, canvas.height * 0.15);
    await tester.dragFrom(start, offset);
    await tester.pump();
  }

  NormalizedRect? _profileRect(_MemoryStore store, String componentId) {
    return store.profile!
        .screenLayout(kHomeScreenId, LayoutVariant.portrait)!
        .component(componentId)!
        .rect;
  }

  testWidgets('the interface hub is the only entry to the live Home editor', (
    tester,
  ) async {
    _usePortrait(tester);
    await _openHomeEditor(tester, _MemoryStore());

    expect(find.byType(LiveLayoutEditor), findsOneWidget);
    expect(find.text('Customize Home'), findsOneWidget);
    // The freeform canvas renders every visible Home block.
    expect(find.byType(FreeformLayoutCanvas), findsOneWidget);
    expect(find.text('Start Listening'), findsOneWidget);
    expect(find.text('Your Listening'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('All Songs'), findsOneWidget);
    // Home's own customize button is gone: Settings earlier is the entry.
    expect(find.byIcon(Icons.tune_rounded), findsNothing);
  });

  testWidgets('selecting a block frames it and its chip opens a context menu', (
    tester,
  ) async {
    _usePortrait(tester);
    await _openHomeEditor(tester, _MemoryStore());

    await _selectContinueListening(tester);
    expect(_chip('Continue Listening (Medium)'), findsOneWidget);

    await tester.tap(_chip('Continue Listening (Medium)'));
    await tester.pumpAndSettle();
    expect(find.text('Move down'), findsOneWidget);
    expect(find.text('Decrease width'), findsOneWidget);
    expect(find.text('Increase width'), findsOneWidget);
    expect(find.text('Decrease height'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
  });

  testWidgets('hide removes a block live and the hidden sheet restores it', (
    tester,
  ) async {
    _usePortrait(tester);
    await _openHomeEditor(tester, _MemoryStore());

    await _hideContinueListening(tester);

    // The section leaves the canvas immediately.
    expect(find.text('Start Listening'), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Hidden sections'), findsOneWidget);
    await tester.tap(find.text('Continue Listening'));
    await tester.pumpAndSettle();

    expect(find.text('Start Listening'), findsOneWidget);
  });

  testWidgets('undo and redo revert and re-apply an edit', (tester) async {
    _usePortrait(tester);
    await _openHomeEditor(tester, _MemoryStore());

    expect(find.text('Start Listening'), findsOneWidget);
    await _hideContinueListening(tester);
    expect(find.text('Start Listening'), findsNothing);

    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Start Listening'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.redo_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Start Listening'), findsNothing);
  });

  testWidgets('cancel keeps un-done edits out of storage', (tester) async {
    _usePortrait(tester);
    final store = _MemoryStore();
    await _openHomeEditor(tester, store);

    await _hideContinueListening(tester);
    expect(store.profile, isNull, reason: 'nothing persisted while editing');

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.byType(LiveLayoutEditor), findsNothing);
    expect(store.profile, isNull);
  });

  testWidgets('done persists the live edits', (tester) async {
    _usePortrait(tester);
    final store = _MemoryStore();
    await _openHomeEditor(tester, store);

    await _hideContinueListening(tester);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.byType(LiveLayoutEditor), findsNothing);
    final layout = store.profile!.screenLayout(
      kHomeScreenId,
      LayoutVariant.portrait,
    )!;
    expect(layout.component('home.continueListening')!.visible, isFalse);
  });

  testWidgets('reset restores the default layout on save', (tester) async {
    _usePortrait(tester);
    final store = _MemoryStore();
    _seedNonDefaultHome(store);
    await _openHomeEditor(tester, store);

    await tester.tap(find.byIcon(Icons.restart_alt_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(
      store.profile!
          .screenLayout(kHomeScreenId, LayoutVariant.portrait)!
          .component('home.listeningInsights')!
          .visible,
      isTrue,
    );
    expect(
      store.profile!
          .screenLayout(kHomeScreenId, LayoutVariant.portrait)!
          .component('home.continueListening')!
          .size,
      ComponentSize.medium,
    );
    // Only Home was touched: the preset is reapplied to the whole app.
    expect(store.profile!.preset, LayoutPreset.standard);
  });

  testWidgets('applying a preset is live and undoable', (tester) async {
    _usePortrait(tester);
    final store = _MemoryStore();
    await _openHomeEditor(tester, store);

    // Nothing hidden under the standard preset.
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Hidden sections'), findsOneWidget);
    expect(find.text('All sections are visible.'), findsOneWidget);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.auto_awesome_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minimal'));
    await tester.pumpAndSettle();

    // Applied live on screen: Minimal hides the insights and playlists blocks.
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Your Listening'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('All sections are visible.'), findsNothing);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(store.profile, isNull, reason: 'not persisted while editing');

    // Undo reverts to standard (nothing hidden); store still untouched.
    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();
    expect(find.text('All sections are visible.'), findsOneWidget);
    // The hidden sheet no longer lists Your Listening among the hidden ones.
    expect(find.widgetWithText(ListTile, 'Your Listening'), findsNothing);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(store.profile, isNull);
  });

  testWidgets('persisted layouts store normalized geometry, never pixel '
      'offsets', (tester) async {
    _usePortrait(tester);
    final store = _MemoryStore();
    await _openHomeEditor(tester, store);

    await _hideContinueListening(tester);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final raw = store.values[KvLayoutRepository.storageKey]!;
    // Geometry is persisted as normalized x/y/w/h fractions…
    expect(raw.contains('"x"'), isTrue);
    expect(raw.contains('"y"'), isTrue);
    expect(raw.contains('"w"'), isTrue);
    expect(raw.contains('"h"'), isTrue);
    // …never as raw pixel offsets.
    expect(raw.contains('"dx"'), isFalse);
    expect(raw.contains('"dy"'), isFalse);
  });

  testWidgets('portrait and landscape layouts stay independent', (
    tester,
  ) async {
    _usePortrait(tester);
    final store = _MemoryStore();
    await _openHomeEditor(tester, store);

    await _hideContinueListening(tester);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final portrait = store.profile!.screenLayout(
      kHomeScreenId,
      LayoutVariant.portrait,
    )!;
    final landscape = store.profile!.screenLayout(
      kHomeScreenId,
      LayoutVariant.landscape,
    )!;
    expect(portrait.component('home.continueListening')!.visible, isFalse);
    expect(landscape.component('home.continueListening')!.visible, isTrue);
  });

  testWidgets('protected sections cannot be hidden', (tester) async {
    _usePortrait(tester);
    await _openHomeEditor(tester, _MemoryStore());

    // All Songs is the dashboard anchor (canHide: false).
    await tester.tap(find.text('All Songs'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(_chip('All Songs (Medium)'));
    await tester.pumpAndSettle();

    expect(find.text('Hide'), findsNothing);
    expect(find.text('Move up'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
  });

  testWidgets('dragging a block persists normalized geometry', (tester) async {
    _usePortrait(tester);
    final store = _MemoryStore();
    await _openHomeEditor(tester, store);

    // The pure-horizontal drag snaps the block onto the logical grid, so y is
    // the grid-snapped default rather than the raw 0.02. Capture the canvas
    // height while the editor is still open.
    final canvas = tester.getRect(find.byType(FreeformLayoutCanvas));
    final canvasW = canvas.width;
    final canvasH = canvas.height;

    // Drag Continue Listening far enough left that it clamps to the canvas
    // edge: the default x (0.025) minus the visible drag must reach 0.
    await _selectContinueListening(tester);
    await _dragContinueListening(tester, const Offset(-120, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final rect = _profileRect(store, 'home.continueListening');
    expect(rect, isNotNull);
    expect(rect!.x, 0.0);
    final gridY = (0.02 * canvasH / 8).round() * 8 / canvasH;
    final gridW = (0.95 * canvasW / 8).round() * 8 / canvasW;
    final gridH = (0.3 * canvasH / 8).round() * 8 / canvasH;
    expect(rect.y, closeTo(gridY, 0.001));
    expect(rect.width, closeTo(gridW, 0.001));
    expect(rect.height, closeTo(gridH, 0.001));
  });

  testWidgets('an entire drag collapses into a single undo', (tester) async {
    _usePortrait(tester);
    final store = _MemoryStore();
    await _openHomeEditor(tester, store);

    await _selectContinueListening(tester);
    await _dragContinueListening(tester, const Offset(-120, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Undoing the single drag restores the default placement.
    final rect = _profileRect(store, 'home.continueListening');
    expect(rect, isNotNull);
    expect(rect!.x, closeTo(0.025, 0.001));
    expect(rect.y, closeTo(0.02, 0.001));
  });

  testWidgets('a colliding drag snaps back and warns', (tester) async {
    _usePortrait(tester);
    final store = _MemoryStore();
    await _openHomeEditor(tester, store);

    // Push Continue Listening down over Your Listening: collisions are never
    // committed and the block returns to its last valid placement.
    await _selectContinueListening(tester);
    await _dragContinueListening(tester, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.text('Blocks cannot overlap.'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final rect = _profileRect(store, 'home.continueListening');
    expect(rect, isNotNull);
    expect(rect!.x, closeTo(0.025, 0.001));
    expect(rect.y, closeTo(0.02, 0.001));
  });

  testWidgets('resizing a block from the menu persists the new width', (
    tester,
  ) async {
    _usePortrait(tester);
    final store = _MemoryStore();
    await _openHomeEditor(tester, store);

    await _selectContinueListening(tester);
    await tester.tap(_chip('Continue Listening (Medium)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decrease width'));
    await tester.pumpAndSettle();
    // Dismiss the block menu before saving.
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final rect = _profileRect(store, 'home.continueListening');
    expect(rect, isNotNull);
    expect(rect!.width, closeTo(0.93, 0.001));
    expect(rect.x, closeTo(0.025, 0.001));
    expect(rect.height, closeTo(0.3, 0.001));
  });
}

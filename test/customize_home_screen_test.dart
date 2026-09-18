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
import 'package:vora_tube/features/customization/presentation/widgets/editable_layout_frame.dart';
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

  Future<void> _hideContinueListening(WidgetTester tester) async {
    await tester.tap(find.byType(EditableLayoutFrame).first);
    await tester.pumpAndSettle();
    await tester.tap(_chip('Continue Listening (Medium)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
  }

  testWidgets('the interface hub is the only entry to the live Home editor', (
    tester,
  ) async {
    _usePortrait(tester);
    await _openHomeEditor(tester, _MemoryStore());

    expect(find.byType(LiveLayoutEditor), findsOneWidget);
    expect(find.text('Customize Home'), findsOneWidget);
    // The real Home renders inside, framed per section.
    expect(find.byType(EditableLayoutFrame), findsNWidgets(4));
    // Home's own customize button is gone: Settings earlier is the entry.
    expect(find.byIcon(Icons.tune_rounded), findsNothing);
  });

  testWidgets('selecting a block frames it and its chip opens a context menu', (
    tester,
  ) async {
    _usePortrait(tester);
    await _openHomeEditor(tester, _MemoryStore());

    await tester.tap(find.byType(EditableLayoutFrame).first);
    await tester.pumpAndSettle();
    expect(_chip('Continue Listening (Medium)'), findsOneWidget);

    await tester.tap(_chip('Continue Listening (Medium)'));
    await tester.pumpAndSettle();
    expect(find.text('Move down'), findsOneWidget);
    expect(find.text('Decrease size'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
  });

  testWidgets('hide removes a block live and the hidden sheet restores it', (
    tester,
  ) async {
    _usePortrait(tester);
    await _openHomeEditor(tester, _MemoryStore());

    await _hideContinueListening(tester);

    // The section leaves the real screen immediately.
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
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(store.profile, isNull, reason: 'not persisted while editing');

    // Undo reverts to standard (nothing hidden); store still untouched.
    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Your Listening'), findsNothing);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(store.profile, isNull);
  });

  testWidgets('persisted layouts never store raw pixel coordinates', (
    tester,
  ) async {
    _usePortrait(tester);
    final store = _MemoryStore();
    await _openHomeEditor(tester, store);

    await _hideContinueListening(tester);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final raw = store.values[KvLayoutRepository.storageKey]!;
    expect(raw.contains('"x"'), isFalse);
    expect(raw.contains('"y"'), isFalse);
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
    await tester.tap(find.byType(EditableLayoutFrame).last);
    await tester.pumpAndSettle();
    await tester.tap(_chip('All Songs (Medium)'));
    await tester.pumpAndSettle();

    expect(find.text('Hide'), findsNothing);
    expect(find.text('Move up'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
  });
}

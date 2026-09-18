import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/ui_customization/ui_component_registry.dart';
import 'package:vora_tube/core/ui_customization/ui_layout.dart';
import 'package:vora_tube/core/ui_customization/ui_layout_normalizer.dart';
import 'package:vora_tube/features/customization/data/layout_repository.dart';
import 'package:vora_tube/features/customization/presentation/providers/layout_providers.dart';
import 'package:vora_tube/features/customization/presentation/screens/customize_home_screen.dart';
import 'package:vora_tube/features/customization/presentation/screens/customize_interface_screen.dart';

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

void _seedNonDefault(_MemoryStore store) {
  final seeded = LayoutProfile(
    preset: LayoutPreset.minimal,
    layouts: {
      for (final variant in LayoutVariant.values)
        LayoutKey(kHomeScreenId, variant): applyLayoutPreset(
          LayoutPreset.minimal,
          kHomeScreenId,
          homeComponentRegistry,
        ),
    },
  );
  store.values[KvLayoutRepository.storageKey] = seeded.encode();
}

Future<void> _pumpEditor(WidgetTester tester, _MemoryStore store) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        layoutRepositoryProvider.overrideWithValue(KvLayoutRepository(store)),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CustomizeHomeScreen(),
                  ),
                ),
                child: const Text('open editor'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open editor'));
  await tester.pumpAndSettle();
}

Future<void> _pumpInterface(WidgetTester tester, _MemoryStore store) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        layoutRepositoryProvider.overrideWithValue(KvLayoutRepository(store)),
      ],
      child: const MaterialApp(home: CustomizeInterfaceScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

TextButton _saveButton(WidgetTester tester) =>
    tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save'));

void main() {
  testWidgets('toggling a section off then saving persists the layout', (
    tester,
  ) async {
    _usePortrait(tester);
    final store = _MemoryStore();
    await _pumpEditor(tester, store);

    expect(_saveButton(tester).onPressed, isNull, reason: 'clean session');

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(_saveButton(tester).onPressed, isNotNull, reason: 'dirty session');

    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.byType(CustomizeHomeScreen), findsNothing);
    final layout = store.profile!.screenLayout(
      kHomeScreenId,
      LayoutVariant.portrait,
    );
    expect(layout!.component('home.continueListening')!.visible, isFalse);
  });

  testWidgets('undo reverts an unsaved change', (tester) async {
    _usePortrait(tester);
    await _pumpEditor(tester, _MemoryStore());

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(_saveButton(tester).onPressed, isNotNull);

    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.pumpAndSettle();
    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('reset restores the default layout on save', (tester) async {
    _usePortrait(tester);
    final store = _MemoryStore();
    _seedNonDefault(store);
    await _pumpEditor(tester, store);

    await tester.tap(find.byIcon(Icons.restart_alt_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(store.profile, defaultLayoutProfile(homeComponentRegistry));
  });

  testWidgets('applying a preset records it on save', (tester) async {
    _usePortrait(tester);
    final store = _MemoryStore();
    await _pumpEditor(tester, store);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Minimal'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    final profile = store.profile!;
    expect(profile.preset, LayoutPreset.minimal);
    final layout = profile.screenLayout(kHomeScreenId, LayoutVariant.portrait)!;
    expect(layout.component('home.listeningInsights')!.visible, isFalse);
    expect(
      layout.component('home.continueListening')!.size,
      ComponentSize.small,
    );
  });

  testWidgets('the interface hub links to the Home editor', (tester) async {
    await _pumpInterface(tester, _MemoryStore());

    expect(find.text('Customize Interface'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(find.byType(CustomizeHomeScreen), findsOneWidget);
  });
}

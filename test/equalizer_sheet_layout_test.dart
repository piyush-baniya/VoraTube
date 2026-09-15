import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/features/player/presentation/widgets/equalizer_sheet.dart';

/// Regression tests for the (previously overflowing) Equalizer UI.
///
/// The custom equalizer used to overflow by ~7.8 px on small phones (the
/// summary column inside the sheet's [Expanded] region) and the popup header
/// could clip under large text scales. Both regions must always fit, and the
/// dialog must expose all 10 band sliders.
void main() {
  Future<void> pumpWithSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showEqualizerSheet(context),
                  child: const Text('open eq'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> selectCustom(WidgetTester tester) async {
    await tester.tap(find.text('open eq'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester tester) async {
    await selectCustom(tester);
    // The Custom chip pops the editor even when Custom is already selected.
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
  }

  Future<void> expectNoOverflow(
    WidgetTester tester,
    String context,
  ) async {
    expect(tester.takeException(), isNull, reason: '$context must not overflow');
  }

  testWidgets('sheet survives custom summary on a small phone (360x640)', (
    tester,
  ) async {
    await pumpWithSize(tester, const Size(360, 640));
    await selectCustom(tester);

    expect(find.text('Custom curve'), findsOneWidget);
    expect(find.text('Edit bands'), findsOneWidget);
    await expectNoOverflow(tester, 'small sheet with custom summary');
  });

  testWidgets('sheet survives custom summary on a tall phone (393x852)', (
    tester,
  ) async {
    await pumpWithSize(tester, const Size(393, 852));
    await selectCustom(tester);

    expect(find.text('Custom curve'), findsOneWidget);
    expect(find.text('Edit bands'), findsOneWidget);
    await expectNoOverflow(tester, 'tall sheet with custom summary');
  });

  testWidgets('custom editor shows all 10 band sliders on 360x640', (
    tester,
  ) async {
    await pumpWithSize(tester, const Size(360, 640));
    await openEditor(tester);

    expect(find.text('Custom equalizer'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(10));
    await expectNoOverflow(tester, 'small custom editor');
  });

  testWidgets('custom editor shows all 10 band sliders on 393x852', (
    tester,
  ) async {
    await pumpWithSize(tester, const Size(393, 852));
    await openEditor(tester);

    expect(find.text('Custom equalizer'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(10));
    await expectNoOverflow(tester, 'tall custom editor');
  });
}
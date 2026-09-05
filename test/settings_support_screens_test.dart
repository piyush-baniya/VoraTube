import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/features/settings/presentation/screens/faq_screen.dart';
import 'package:vora_tube/features/settings/presentation/screens/privacy_policy_screen.dart';
import 'package:vora_tube/features/settings/presentation/screens/terms_screen.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('FaqScreen', () {
    testWidgets('renders the first question and expands its answer',
        (tester) async {
      await tester.pumpWidget(_wrap(const FaqScreen()));

      final entry = FaqScreen.entries.first;
      final questionFinder = find.text(entry.question).first;

      expect(questionFinder, findsOneWidget);
      expect(find.text(entry.answer), findsNothing);

      await tester.tap(questionFinder);
      await tester.pumpAndSettle();
      expect(find.text(entry.answer), findsOneWidget);

      await tester.tap(questionFinder);
      await tester.pumpAndSettle();
      expect(find.text(entry.answer), findsNothing);
    });

    testWidgets('can scroll through and reveal the final question',
        (tester) async {
      await tester.pumpWidget(_wrap(const FaqScreen()));

      final last = FaqScreen.entries.last;
      final finder = find.text(last.question);

      await tester.scrollUntilVisible(
        finder,
        300,
        scrollable: find.byType(Scrollable),
      );
      expect(finder, findsOneWidget);
    });
  });

  group('TermsScreen', () {
    Future<void> pumpTerms(WidgetTester tester) async {
      // The markdown asset loads through real (async) platform I/O, which
      // needs runAsync inside the fake-async test zone.
      await tester.runAsync(() async {
        await tester.pumpWidget(_wrap(const TermsScreen()));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('renders the Terms of Use header and first section',
        (tester) async {
      await pumpTerms(tester);

      expect(find.widgetWithText(AppBar, 'Terms of Use'), findsOneWidget);
      expect(find.text('1. Use of the App'), findsOneWidget);
    });

    testWidgets('scrolling reveals later sections', (tester) async {
      await pumpTerms(tester);

      final target = find.text('9. Limitation of liability');
      expect(target, findsNothing);

      await tester.scrollUntilVisible(
        target,
        300,
        scrollable: find.byType(Scrollable),
      );
      expect(target, findsOneWidget);
    });
  });

  group('PrivacyPolicyScreen', () {
    Future<void> pumpPrivacy(WidgetTester tester) async {
      // The markdown asset loads through real (async) platform I/O, which
      // needs runAsync inside the fake-async test zone.
      await tester.runAsync(() async {
        await tester.pumpWidget(_wrap(const PrivacyPolicyScreen()));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('renders the Privacy Policy header and intro', (tester) async {
      await pumpPrivacy(tester);

      expect(find.widgetWithText(AppBar, 'Privacy Policy'), findsOneWidget);
      expect(
        find.textContaining('The short version'),
        findsOneWidget,
        reason: 'The summary intro should be visible at the top',
      );
    });

    testWidgets('scrolling reveals later policy sections', (tester) async {
      await pumpPrivacy(tester);

      final target = find.text('10. Data retention and deletion');
      expect(target, findsNothing);

      await tester.scrollUntilVisible(
        target,
        300,
        scrollable: find.byType(Scrollable),
      );
      expect(target, findsOneWidget);
    });
  });
}

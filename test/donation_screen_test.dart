import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:vora_tube/features/donation/presentation/screens/donation_screen.dart';

void main() {
  group('DonationScreen connectivity handling', () {
    testWidgets('shows a loading state while connectivity is pending', (
      tester,
    ) async {
      final check = () => Completer<bool>().future;

      await tester.pumpWidget(
        MaterialApp(home: DonationScreen(connectivityCheck: check)),
      );
      await tester.pump();

      expect(find.text('Checking connection…'), findsOneWidget);
    });

    testWidgets('offline shows the no-internet message and no WebView', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: DonationScreen(connectivityCheck: () async => false)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('No internet connection'), findsOneWidget);
      expect(
        find.textContaining('connect to the internet to donate'),
        findsOneWidget,
      );
      expect(find.byType(WebViewWidget), findsNothing);
    });

    testWidgets('offline retry re-runs the connectivity check', (tester) async {
      var calls = 0;
      Future<bool> check() async {
        calls++;
        return false;
      }

      await tester.pumpWidget(
        MaterialApp(home: DonationScreen(connectivityCheck: check)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('No internet connection'), findsOneWidget);
      expect(calls, 1);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.text('No internet connection'), findsOneWidget);
    });
  });
}

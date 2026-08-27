import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/app/splash_screen.dart';

void main() {
  testWidgets('shows splash then transitions to child', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashGate(
          duration: Duration(milliseconds: 100),
          child: Text('app-ready'),
        ),
      ),
    );

    // Splash visible initially (logo asset renders via placeholder).
    expect(find.text('VoraTube'), findsOneWidget);
    expect(find.text('app-ready'), findsNothing);

    // Advance past the splash duration and let the transition finish.
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(find.text('app-ready'), findsOneWidget);
    expect(find.text('VoraTube'), findsNothing);
  });

  testWidgets('splash renders on near-black background', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashGate(
          duration: Duration(milliseconds: 500),
          child: SizedBox.shrink(),
        ),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, const Color(0xFF09090B));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/app/app.dart';

void main() {
  testWidgets('VoraTube shell renders with four tabs', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: VoraTubeApp()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.search_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Search your library'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.library_music_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.library_music), findsOneWidget);
    expect(find.text('Scan Music'), findsOneWidget);
  });
}

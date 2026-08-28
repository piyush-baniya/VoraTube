import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/shared/utils/scroll_pagination.dart';

void main() {
  group('ScrollPagination.attachLoadMoreListener', () {
    test('installs a listener and is safe before any position is attached', () {
      final controller = ScrollController();
      var calls = 0;
      controller.attachLoadMoreListener(() => calls++);
      // No scrollable attached yet -> position.extentAfter must not throw.
      expect(calls, 0);
      controller.dispose();
    });

    testWidgets('fires when the user scrolls to the bottom of a long list', (
      tester,
    ) async {
      final controller = ScrollController();
      var loadMoreCalls = 0;
      controller.attachLoadMoreListener(() => loadMoreCalls++);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              controller: controller,
              itemCount: 200,
              itemBuilder: (context, index) =>
                  SizedBox(height: 60, child: Text('Item $index')),
            ),
          ),
        ),
      );

      // Scroll toward the bottom; extents shrink below the threshold, so the
      // listener should keep firing and load more than once.
      await tester.drag(find.byType(ListView), const Offset(0, -12000));
      await tester.pump();

      expect(loadMoreCalls, greaterThan(0));
    });
  });
}

import 'package:flutter/widgets.dart';

/// Shared "load the next page when the user scrolls near the list bottom"
/// behaviour, used by every paged song list.
///
/// Keeps the trigger threshold and the lazy-load wiring in one place instead
/// of being copy-pasted across the Library, All Songs and other screens so the
/// pagination stays consistent everywhere.
extension ScrollPagination on ScrollController {
  /// Calls [onNearEnd] whenever the user scrolls within [threshold] pixels of
  /// the bottom of the attached scrollable, so [onNearEnd] can load more data.
  ///
  /// The `hasClients` guard makes the listener safe to install before the
  /// scrollable is laid out; implementations originally read
  /// `position.extentAfter` directly, which threw if there was no attached
  /// position yet.
  void attachLoadMoreListener(
    void Function() onNearEnd, {
    double threshold = 600,
  }) {
    addListener(() {
      if (hasClients && position.extentAfter < threshold) {
        onNearEnd();
      }
    });
  }
}

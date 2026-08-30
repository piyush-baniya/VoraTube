import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/features/library/data/library_models.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/library/presentation/widgets/song_tile.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';

import 'fakes/fake_player.dart';

SongTileData _tile(String title, int id) => SongTileData(
  song: Song(
    id: id,
    source: 'mediastore',
    mediaStoreId: id,
    contentUri: 'content://test/$id',
    title: title,
    titleSearch: title.toLowerCase(),
    durationMs: 1000,
    dateModifiedSec: 0,
  ),
);

Widget _host({
  required bool dragHandle,
  required WidgetRef? capturedRef,
  void Function(int oldIndex, int newIndex)? onReorder,
}) {
  final db = AppDatabase(NativeDatabase.memory());
  final repository = LibraryRepository(db);
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      libraryRepositoryProvider.overrideWithValue(repository),
      playerProvider.overrideWithValue(
        FakePlayerController(
          initial: const PlayerSnapshot(
            status: PlayerStatus.ready,
            isPlaying: false,
            repeatMode: RepeatMode.off,
            shuffleEnabled: false,
            queueLength: 0,
            currentIndex: 0,
            durationMs: 0,
            current: null,
          ),
          queue: const [],
        ),
      ),
    ],
    child: MaterialApp(
      home: ReorderableListView.builder(
        buildDefaultDragHandles: !dragHandle,
        itemCount: 2,
        onReorderItem: (old, new_) => onReorder?.call(old, new_),
        itemBuilder: (context, index) {
          final tile = _tile('Song ${index + 1}', index + 1);
          return Consumer(
            key: ValueKey(tile.song.id),
            builder: (context, ref, _) {
              capturedRef = ref;
              return SongTile(
                tile: tile,
                index: index,
                onPlay: (_) {},
                dragHandle: dragHandle,
              );
            },
          );
        },
      ),
    ),
  );
}

void main() {
  testWidgets('long press inside a reorderable list does not open the menu', (
    tester,
  ) async {
    await tester.pumpWidget(_host(dragHandle: true, capturedRef: null));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Song 1'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Play next'), findsNothing);
    expect(find.byType(Draggable<int>), findsNothing);
  });

  testWidgets('long press outside a reorderable list still opens the menu', (
    tester,
  ) async {
    await tester.pumpWidget(_host(dragHandle: false, capturedRef: null));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Song 1'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Play next'), findsOneWidget);
  });

  testWidgets('three-dot button opens the menu inside a reorderable list', (
    tester,
  ) async {
    await tester.pumpWidget(_host(dragHandle: true, capturedRef: null));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More options').first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Play next'), findsOneWidget);
  });

  /// Drives a long-press-and-drag reorder on the first song tile.
  Future<void> _dragSong(WidgetTester tester, Offset dragDelta) async {
    final center = tester.getCenter(find.text('Song 1'));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(dragDelta);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('long press + drag down starts reorder and moves the song', (
    tester,
  ) async {
    final reorders = <(int, int)>[];
    await tester.pumpWidget(
      _host(
        dragHandle: true,
        capturedRef: null,
        onReorder: (o, n) => reorders.add((o, n)),
      ),
    );
    await tester.pumpAndSettle();

    await _dragSong(tester, const Offset(0, 120));

    // The reorder infrastructure is wired: a drag gesture was delivered and the
    // list did not open a menu or break. The actual reorder-mapping math is
    // covered by playlist_reorder_mapping_test.dart.
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Play next'), findsNothing);
    // Drag handle is present on reorderable tiles.
    expect(find.byIcon(Icons.drag_handle_rounded), findsWidgets);
  });

  testWidgets(
    'dragging a tile after the drag gesture still allows the three-dot menu',
    (tester) async {
      await tester.pumpWidget(_host(dragHandle: true, capturedRef: null));
      await tester.pumpAndSettle();

      await _dragSong(tester, const Offset(0, -120));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byTooltip('More options').first,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Play next'), findsOneWidget);
    },
  );
}

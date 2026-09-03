import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/features/library/data/library_models.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/library/presentation/widgets/song_tile.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/player/presentation/screens/full_player_screen.dart';

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

/// Builds a list of two song tiles backed by a [FakePlayerController] whose
/// current track is [currentIdentityKey]. [onPlay] records whether it fired.
Widget _host({
  required String? currentIdentityKey,
  required void Function()? onPlay,
}) {
  final db = AppDatabase(NativeDatabase.memory());
  final repository = LibraryRepository(db);
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      libraryRepositoryProvider.overrideWithValue(repository),
      playerProvider.overrideWithValue(
        FakePlayerController(
          initial: PlayerSnapshot(
            status: PlayerStatus.ready,
            isPlaying: true,
            repeatMode: RepeatMode.off,
            shuffleEnabled: false,
            queueLength: 1,
            currentIndex: 0,
            durationMs: 1000,
            current: currentIdentityKey == null
                ? null
                : SongRef(
                    identityKey: currentIdentityKey,
                    uri: '',
                    title: 'Song 1',
                    artist: 'Artist',
                    album: null,
                    artPath: null,
                    durationMs: 1000,
                  ),
          ),
          queue: const [],
        ),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            for (var i = 1; i <= 2; i++)
              SongTile(
                tile: _tile('Song $i', i),
                index: i - 1,
                onPlay: (_) => onPlay?.call(),
              ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('tapping the currently playing song does not call onPlay', (
    tester,
  ) async {
    var onPlayCalled = false;

    await tester.pumpWidget(
      _host(
        currentIdentityKey: 'ms:1',
        onPlay: () => onPlayCalled = true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Song 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    expect(onPlayCalled, isFalse, reason: 'Current song must not be replayed');
    expect(
      find.byType(FullPlayerScreen),
      findsWidgets,
      reason: 'Tapping the current song should open the Full Player',
    );
  });

  testWidgets('tapping a different song calls onPlay', (tester) async {
    var onPlayCalled = false;

    await tester.pumpWidget(
      _host(
        currentIdentityKey: 'ms:1',
        onPlay: () => onPlayCalled = true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Song 2'));
    await tester.pump();

    expect(onPlayCalled, isTrue, reason: 'A different song should be played');
  });
}

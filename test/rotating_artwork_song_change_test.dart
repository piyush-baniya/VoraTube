import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/player/player_controller.dart' as player;
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/player/presentation/widgets/rotating_artwork.dart';

player.PlayerSnapshot _playing(String identityKey) => player.PlayerSnapshot(
  status: player.PlayerStatus.ready,
  isPlaying: true,
  repeatMode: player.RepeatMode.off,
  shuffleEnabled: false,
  queueLength: 2,
  currentIndex: 0,
  durationMs: 180000,
  current: player.SongRef(
    identityKey: identityKey,
    uri: 'content://x/$identityKey',
    title: 'Song $identityKey',
    artist: 'Artist',
    album: 'Album',
    artPath: null,
    durationMs: 180000,
  ),
);

void main() {
  testWidgets('full-player artwork keeps rotating when the song changes '
      'while playing', (tester) async {
    rotatingArtworkEnabled = true;
    final key = GlobalKey<RotatingArtworkState>();

    late ProviderContainer container;
    late player.PlayerSnapshot snapshot;

    Widget host(String? path) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: RotatingArtwork(key: key, path: path, size: 120),
        ),
      ),
    );

    snapshot = _playing('ms:1');
    final trackTick = StateProvider<int>((ref) => 0);
    container = ProviderContainer(
      overrides: [
        playbackStateProvider.overrideWith((ref) {
          ref.watch(trackTick);
          return snapshot;
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(host('file:///a.png'));
    await tester.pump();
    expect(
      RotatingArtworkDebug.isRotating(key),
      isTrue,
      reason: 'Playing => the disc rotates.',
    );

    // The song changes while still playing. The old behaviour called
    // reset() (which STOPS a repeating controller) and only restarted on a
    // play/pause flip — so the disc froze until the user paused and resumed.
    snapshot = _playing('ms:2');
    container.read(trackTick.notifier).state++;
    await tester.pumpWidget(host('file:///b.png'));
    await tester.pump();
    expect(
      RotatingArtworkDebug.isRotating(key),
      isTrue,
      reason:
          'A track change while playing must restart the rotation, '
          'not freeze it.',
    );

    // Pausing still stops it.
    snapshot = _playing('ms:2').copyWith(isPlaying: false);
    container.read(trackTick.notifier).state++;
    await tester.pumpWidget(host('file:///b.png'));
    await tester.pump();
    expect(RotatingArtworkDebug.isRotating(key), isFalse);

    // Resuming restarts it.
    snapshot = _playing('ms:2');
    container.read(trackTick.notifier).state++;
    await tester.pumpWidget(host('file:///b.png'));
    await tester.pump();
    expect(RotatingArtworkDebug.isRotating(key), isTrue);
  });
}

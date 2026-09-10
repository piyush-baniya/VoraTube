import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vora_tube/core/player/just_audio_controller.dart';
import 'package:vora_tube/core/player/player_controller.dart';

import 'fakes/fake_audio_player.dart';

class _MemoryPersistence implements PlayerPersistence {
  String? value;

  @override
  Future<String?> read(String key) async => value;

  @override
  Future<void> write(String key, String value) async {
    this.value = value;
  }
}

SongRef _song(int id) => SongRef(
  identityKey: 'song-$id',
  uri: 'https://example.test/$id.mp3',
  title: 'Song $id',
  artist: 'Artist',
  album: 'Album',
  durationMs: 180000,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // audio_session's `configure()` invokes a platform channel; a mocked
  // handler keeps JustAudioController._init() from surfacing a
  // MissingPluginException on the Dart VM.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.audio_session'),
        (call) async => null,
      );

  /// Builds the controller with a recorder on its track-start callback so the
  /// history/ads lifecycle (which songs actually started) is observable.
  JustAudioController build(
    _MemoryPersistence persistence,
    FakeAudioPlayer player,
    List<String> started,
  ) {
    return JustAudioController(
      playbackStorage: persistence,
      songResolver: (keys) async =>
          keys.map((k) => _song(int.parse(k.split('-').last))).toList(),
      player: player,
      onTrackStart: started.add,
    );
  }

  /// Constructs and lets `JustAudioController._init()` (unawaited) fully
  /// settle before the caller drives the controller, so a seeded restore is
  /// complete and user actions are not raced.
  Future<JustAudioController> start(
    _MemoryPersistence persistence,
    FakeAudioPlayer player,
    List<String> started,
  ) async {
    final controller = build(persistence, player, started);
    await pumpEventQueue();
    return controller;
  }

  String currentKey(PlayerController controller) =>
      controller.currentQueue.first.identityKey;

  group('playback history (Previous/Next walk what was actually played)', () {
    test('previous walks the real history and restarts at its very start '
        '(no queue-wrap rotation)', () async {
      final player = FakeAudioPlayer(processing: ProcessingState.ready);
      final started = <String>[];
      final controller = await start(_MemoryPersistence(), player, started);

      await controller.playQueue([_song(1), _song(2), _song(3)]);
      expect(currentKey(controller), 'song-1');
      expect(started, ['song-1']);

      await controller.next(); // queue order fallback
      expect(currentKey(controller), 'song-2');
      expect(started, ['song-1', 'song-2']);
      await controller.next();
      expect(currentKey(controller), 'song-3');
      expect(started, ['song-1', 'song-2', 'song-3']);

      // Previous walks BACK through the actual listening history, re-starting
      // the songs that were really played — not the queue rotation.
      await controller.previous();
      expect(currentKey(controller), 'song-2');
      expect(started, ['song-1', 'song-2', 'song-3', 'song-2']);
      await controller.previous();
      expect(currentKey(controller), 'song-1');
      expect(started, ['song-1', 'song-2', 'song-3', 'song-2', 'song-1']);

      // At the very start of the history, Previous RESTARTS the first song: no
      // rotation (the queue order is untouched) and no extra track start.
      await controller.previous();
      expect(currentKey(controller), 'song-1');
      expect(controller.currentQueue.map((r) => r.identityKey), [
        'song-1',
        'song-2',
        'song-3',
      ], reason: 'history-start previous must never rotate the queue');
      expect(started, hasLength(5));

      // Next now re-walks the recorded forward steps before queue order.
      await controller.next();
      expect(currentKey(controller), 'song-2');
      await controller.next();
      expect(currentKey(controller), 'song-3');
      // No forward entry remains after song-3, so Next falls back to the queue
      // rotation (song-3 -> song-1).
      await controller.next();
      expect(currentKey(controller), 'song-1');
      expect(started, [
        'song-1', //
        'song-2', //
        'song-3', //
        'song-2', //
        'song-1', //
        'song-2', //
        'song-3', //
        'song-1', //
      ]);
    });

    test(
      'history reads skip songs that left the queue (membership filter)',
      () async {
        final player = FakeAudioPlayer(processing: ProcessingState.ready);
        final started = <String>[];
        final controller = await start(_MemoryPersistence(), player, started);

        await controller.playQueue([_song(1), _song(2), _song(3)]);
        await controller.next(); // song-2
        await controller.next(); // song-3
        // Queue is now [song-3, song-1, song-2]; history is [song-1..song-3].
        expect(controller.currentQueue.map((r) => r.identityKey), [
          'song-3',
          'song-1',
          'song-2',
        ]);

        // Remove song-1 from the middle: it must become unreachable via the
        // history walk even though the history still records it.
        await controller.removeAt(1);
        expect(controller.currentQueue.map((r) => r.identityKey), [
          'song-3',
          'song-2',
        ]);

        // Previous skips the departed song-1 and lands on song-2 directly.
        await controller.previous();
        expect(currentKey(controller), 'song-2');
        expect(
          controller.currentQueue.map((r) => r.identityKey),
          isNot(contains('song-1')),
        );

        // Behind song-2 only the departed song-1 remains: Previous restarts
        // song-2 instead of trying to resurrect song-1 (or wrapping).
        await controller.previous();
        expect(currentKey(controller), 'song-2');
        expect(started, hasLength(4)); // playQueue + 2 next + the walk step
      },
    );

    test(
      'single-song queue: previous and next both restart in place',
      () async {
        final player = FakeAudioPlayer(processing: ProcessingState.ready);
        final started = <String>[];
        final controller = await start(_MemoryPersistence(), player, started);

        await controller.playQueue([_song(1)]);
        expect(started, ['song-1']);

        await controller.previous();
        expect(currentKey(controller), 'song-1');
        await controller.next();
        expect(currentKey(controller), 'song-1');
        expect(controller.currentQueue, hasLength(1));
        expect(started, hasLength(1));
      },
    );

    test('notification-swipe stop never skips the dismissed song (the Req 1 '
        'regression)', () async {
      // Emitting engine: stop() drives the real idle processing-state path
      // that used to auto-advance the queue.
      final player = FakeAudioPlayer(
        processing: ProcessingState.ready,
        emitEvents: true,
      );
      final started = <String>[];
      final controller = await start(_MemoryPersistence(), player, started);

      await controller.playQueue([_song(1), _song(2)]);
      expect(currentKey(controller), 'song-1');
      expect(started, hasLength(1));

      // What the platform does when the media notification is swiped away:
      // the handler's default onNotificationDeleted routes to stop().
      await controller.stop();
      await pumpEventQueue();

      // The queue and current song are preserved — nothing advanced.
      expect(controller.currentQueue.map((r) => r.identityKey), [
        'song-1',
        'song-2',
      ]);
      expect(currentKey(controller), 'song-1');
      expect(started, hasLength(1));
    });

    test('a restored session never counts a start and previous restarts the '
        'restored song', () async {
      final player = FakeAudioPlayer(processing: ProcessingState.ready);
      final persistence = _MemoryPersistence()
        ..value =
            '{"v":1,"keys":["song-1"],"index":0,"posMs":0,"shuffle":false,'
            '"repeat":"off"}';
      final started = <String>[];
      final controller = await start(persistence, player, started);

      // Restoring the persisted session must NOT emit a track start (it is a
      // resume, not a new play) even though the engine reports ready.
      expect(started, isEmpty);
      expect(currentKey(controller), 'song-1');

      await controller.previous();
      expect(currentKey(controller), 'song-1');
      expect(controller.currentQueue.map((r) => r.identityKey), [
        'song-1',
      ], reason: 'restored-session previous must restart in place');
      expect(started, isEmpty);
    });

    test('explicit playQueue resets the history so replaying the same first '
        'song counts again', () async {
      final player = FakeAudioPlayer(processing: ProcessingState.ready);
      final started = <String>[];
      final controller = await start(_MemoryPersistence(), player, started);

      await controller.playQueue([_song(1), _song(2)]);
      await controller.next(); // song-2
      await controller.previous(); // back to song-1 (history walk)
      expect(started, [
        'song-1',
        'song-2',
        'song-1',
      ], reason: 'the history walk-back re-plays song-1 and counts it');

      // A brand-new explicit session: the same first song counts as a fresh
      // play again (the ad/stats lifecycle is reset).
      await controller.playQueue([_song(1), _song(2)]);
      expect(started, ['song-1', 'song-2', 'song-1', 'song-1']);
    });
  });
}

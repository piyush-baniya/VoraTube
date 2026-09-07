import 'package:audio_service/audio_service.dart';
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

  JustAudioController build(
    _MemoryPersistence persistence,
    FakeAudioPlayer player,
  ) {
    return JustAudioController(
      playbackStorage: persistence,
      songResolver: (keys) async =>
          keys.map((k) => _song(int.parse(k.split('-').last))).toList(),
      player: player,
    );
  }

  /// Constructs and lets `JustAudioController._init()` (unawaited) fully
  /// settle before the caller drives the controller. Mirrors production cold
  /// start, where restore happens before any user action; without this the
  /// immediately-triggered playQueue could write a snapshot that `_init`'s
  /// restore then reads back, racing itself.
  Future<JustAudioController> start(
    _MemoryPersistence persistence,
    FakeAudioPlayer player,
  ) async {
    final controller = build(persistence, player);
    await pumpEventQueue();
    return controller;
  }

  group('playback service/notification lifecycle', () {
    test('playQueue publishes ready+playing even when the engine emits no '
        'state events', () async {
      final player = FakeAudioPlayer(processing: ProcessingState.ready);
      final controller = await start(_MemoryPersistence(), player);

      await controller.playQueue([_song(1), _song(2)]);

      expect(player.setAudioSourceCalls, 1);
      expect(player.playCalls, greaterThan(0));
      expect(
        controller.playbackState.value.processingState,
        AudioProcessingState.ready,
      );
      expect(controller.playbackState.value.playing, isTrue);
      expect(controller.current.status, PlayerStatus.ready);
      expect(controller.current.isPlaying, isTrue);
    });

    test('clearSession end-with-X: idle + not playing, queue wiped, snapshot '
        'cleared', () async {
      // Emitting engine: a NORMAL Android device that faithfully re-emits
      // state. pause() lands the controller in ready/not-playing (the service
      // stays foregrounded while paused), then the X/Close action must
      // deterministically drive it to idle so the service is torn down and the
      // stale notification is removed.
      final player = FakeAudioPlayer(
        processing: ProcessingState.ready,
        emitEvents: true,
      );
      final persistence = _MemoryPersistence();
      final controller = await start(persistence, player);

      await controller.playQueue([_song(1)]);
      await controller.pause();
      await pumpEventQueue();
      expect(
        controller.playbackState.value.processingState,
        AudioProcessingState.ready,
      );
      expect(controller.playbackState.value.playing, isFalse);

      await controller.clearSession();
      await pumpEventQueue();

      expect(
        controller.playbackState.value.processingState,
        AudioProcessingState.idle,
        reason:
            'clearSession must broadcast idle so native audio_service '
            'stops the foreground service and removes the notification',
      );
      expect(controller.playbackState.value.playing, isFalse);
      expect(controller.current.status, PlayerStatus.idle);
      expect(controller.current.isPlaying, isFalse);
      expect(controller.currentQueue, isEmpty);
      expect(
        player.stopCalls,
        1,
        reason: 'clearSession must actually stop the audio engine',
      );
      expect(
        QueueSnapshot.fromJson(persistence.value!).isEmpty,
        isTrue,
        reason:
            'clearing a session must wipe the persisted snapshot so a '
            'restart cannot resurrect the cleared session',
      );
    });

    test('clearSession tears the service down WITHOUT relying on engine '
        'events (unresponsive platform)', () async {
      // Bug reproduction: on some Android phones the platform side never
      // re-emits state for a stop() of an already-idle/paused engine. With no
      // stream events the only way the native service learns about the stop is
      // the explicit idle broadcast that clearSession must force.
      final player = FakeAudioPlayer(processing: ProcessingState.ready);
      final controller = await start(_MemoryPersistence(), player);

      await controller.playQueue([_song(1)]);
      expect(
        controller.playbackState.value.processingState,
        AudioProcessingState.ready,
      );

      await controller.clearSession();

      expect(
        controller.playbackState.value.processingState,
        AudioProcessingState.idle,
        reason:
            'the engine emitted nothing, so only an explicit idle '
            'broadcast can end the foreground service',
      );
      expect(controller.playbackState.value.playing, isFalse);
      expect(controller.currentQueue, isEmpty);
    });

    test('notification X (close custom action) routes to clearSession and '
        'reports idle', () async {
      final player = FakeAudioPlayer(
        processing: ProcessingState.ready,
        emitEvents: true,
      );
      final controller = await start(_MemoryPersistence(), player);
      await controller.playQueue([_song(1)]);

      await controller.customAction(kNotificationCloseAction, null);
      await pumpEventQueue();

      expect(
        controller.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      expect(controller.playbackState.value.playing, isFalse);
      expect(controller.currentQueue, isEmpty);
    });

    test('non-close custom actions do not tear down the service', () async {
      final player = FakeAudioPlayer(
        processing: ProcessingState.ready,
        emitEvents: true,
      );
      final controller = await start(_MemoryPersistence(), player);
      await controller.playQueue([_song(1)]);

      await controller.customAction(kNotificationFavoriteAction, null);
      await pumpEventQueue();

      expect(
        controller.playbackState.value.processingState,
        AudioProcessingState.ready,
      );
      expect(controller.currentQueue, hasLength(1));
    });

    test('pause keeps the session ready so background resume survives '
        '(stopForegroundOnPause: false)', () async {
      final player = FakeAudioPlayer(
        processing: ProcessingState.ready,
        emitEvents: true,
      );
      final controller = await start(_MemoryPersistence(), player);
      await controller.playQueue([_song(1)]);

      await controller.pause();
      await pumpEventQueue();

      // Still resumable: not idle, so the service stays foregrounded and the
      // pinned notification can resume playback.
      expect(
        controller.playbackState.value.processingState,
        AudioProcessingState.ready,
      );
      expect(controller.playbackState.value.playing, isFalse);
      expect(controller.current.isPlaying, isFalse);
    });

    test('onTaskRemoved persists but does NOT stop playback (background '
        'playback stays alive)', () async {
      final player = FakeAudioPlayer(
        processing: ProcessingState.ready,
        emitEvents: true,
      );
      final persistence = _MemoryPersistence();
      final controller = await start(persistence, player);
      await controller.playQueue([_song(1)]);
      await pumpEventQueue();

      await controller.onTaskRemoved();
      await pumpEventQueue();

      expect(
        player.stopCalls,
        0,
        reason:
            'removing the task must keep the service playing in the '
            'background',
      );
      expect(
        controller.playbackState.value.processingState,
        AudioProcessingState.ready,
      );
      expect(controller.currentQueue, hasLength(1));
      expect(
        persistence.value,
        isNotNull,
        reason:
            'onTaskRemoved must persist the resume point before the '
            'process can be killed',
      );
    });

    test('stop() with an empty queue reports idle (notification-removal '
        'path)', () async {
      final player = FakeAudioPlayer(processing: ProcessingState.ready);
      final controller = await start(_MemoryPersistence(), player);

      await controller.stop();

      expect(
        controller.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      expect(controller.playbackState.value.playing, isFalse);
    });
  });
}

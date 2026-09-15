import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vora_tube/core/audio/audio_effects.dart';
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

  // audio_session's `configure()` invokes a platform channel; the mock keeps
  // JustAudioController._init() from surfacing a MissingPluginException.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.audio_session'),
        (call) async => null,
      );

  Future<JustAudioController> start(
    _MemoryPersistence persistence,
    FakeAudioPlayer player,
  ) async {
    final controller = JustAudioController(
      playbackStorage: persistence,
      songResolver: (keys) async =>
          keys.map((k) => _song(int.parse(k.split('-').last))).toList(),
      player: player,
    );
    await pumpEventQueue();
    return controller;
  }

  group('playback speed', () {
    test('applies the clamped speed to the engine without reloading', () async {
      final player = FakeAudioPlayer(processing: ProcessingState.ready);
      final controller = await start(_MemoryPersistence(), player);

      await controller.playQueue([_song(1), _song(2)]);
      expect(player.setAudioSourceCalls, 1);

      await controller.setPlaybackSpeed(2.0);
      expect(player.lastSetSpeed, 2.0);
      expect(player.setSpeedCalls, 1);
      expect(
        player.setAudioSourceCalls,
        1,
        reason: 'a speed change must never reload the audio source',
      );

      await controller.setPlaybackSpeed(0.25);
      expect(player.lastSetSpeed, 0.25);

      // Clamped to the supported range.
      await controller.setPlaybackSpeed(99.0);
      expect(player.lastSetSpeed, kPlaybackSpeedMax);
      await controller.setPlaybackSpeed(0.0001);
      expect(player.lastSetSpeed, kPlaybackSpeedMin);

      // Cancel the pending warm-up fade before the test tears down.
      await controller.setTransitionMode(PlaybackTransitionMode.off);
    });
  });

  group('crossfade volume ramps', () {
    test('dips the outgoing track then swells the incoming one', () async {
      final player = FakeAudioPlayer(processing: ProcessingState.ready);
      final controller = await start(_MemoryPersistence(), player);

      await controller.playQueue([_song(1), _song(2)]);
      expect(player.setAudioSourceCalls, 1);

      // 2s crossfade → 1s per half; the pre-switch duck is capped at 250ms.
      await controller.setTransitionMode(
        PlaybackTransitionMode.crossfade,
        crossfadeSeconds: 2,
      );

      await controller.next();
      expect(player.setAudioSourceCalls, 2);

      // The pre-switch duck pressed the volume down below 50% somewhere.
      expect(
        player.volumeCalls.any((v) => v < 0.5),
        isTrue,
        reason: 'crossfade should audibly duck the outgoing track',
      );

      // Let the (unawaited) incoming swell finish.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(player.volumeCalls.last, closeTo(1.0, 0.001),
          reason: 'crossfade should restore full volume after the swell');
    });

    test('gapless mode cuts over without any volume dip', () async {
      final player = FakeAudioPlayer(processing: ProcessingState.ready);
      final controller = await start(_MemoryPersistence(), player);

      await controller.playQueue([_song(1), _song(2)]);
      await controller.setTransitionMode(PlaybackTransitionMode.gapless);

      player.volumeCalls.clear();
      await controller.next();
      expect(player.setAudioSourceCalls, 2);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(player.volumeCalls.any((v) => v < 1.0), isFalse,
          reason: 'gapless must be a hard cut — no fade applies');
    });

    test('turning transitions off restores full volume immediately', () async {
      final player = FakeAudioPlayer(processing: ProcessingState.ready);
      final controller = await start(_MemoryPersistence(), player);

      await controller.playQueue([_song(1), _song(2)]);
      await controller.setTransitionMode(
        PlaybackTransitionMode.crossfade,
        crossfadeSeconds: 8,
      );
      // Arm a fade-in (unawaited), then cancel instantly.
      await controller.next();
      await controller.setTransitionMode(PlaybackTransitionMode.off);

      // A cancellation-restore happened right away: last effective volume is 1.0.
      expect(
        player.volumeCalls.lastWhere((v) => v >= 0.99, orElse: () => -1) >= 0.99,
        isTrue,
      );
      // Nothing left mid-ramp: allow the orphaned ramp to tick once and confirm
      // it no longer mutates volume.
      final before = player.volumeCalls.last;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(player.volumeCalls.last, before);
    });
  });

  group('audio balance', () {
    test('stores the clamped balance for persistence / re-application', () async {
      final player = FakeAudioPlayer(processing: ProcessingState.ready);
      final controller = await start(_MemoryPersistence(), player);

      expect(controller.audioBalance, kDefaultAudioBalance);
      await controller.setAudioBalance(0.75);
      expect(controller.audioBalance, 0.75);
      await controller.setAudioBalance(-0.4);
      expect(controller.audioBalance, -0.4);
      await controller.setAudioBalance(9.0);
      expect(controller.audioBalance, 1.0);
      await controller.setAudioBalance(-9.0);
      expect(controller.audioBalance, -1.0);

      await controller.setTransitionMode(PlaybackTransitionMode.off);
    });
  });
}
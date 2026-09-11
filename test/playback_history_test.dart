import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vora_tube/core/player/just_audio_controller.dart';
import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/features/ads/interstitial_ad_service.dart';
import 'package:vora_tube/features/ads/interstitial_ads_provider.dart';

import 'fakes/fake_audio_player.dart';

class _RecordingAdService extends InterstitialAdService {
  int showCalls = 0;

  @override
  void load() {}

  @override
  bool get hasAdReady => true;

  @override
  Future<bool> show() async {
    showCalls++;
    return true;
  }

  @override
  void dispose() {}
}

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
      'removing a song from the queue does not erase its history: Previous '
      'still returns to it via a temporary placeholder, and leaving it again '
      'drops it without re-inserting it permanently',
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

        // Remove song-1 from the queue (swipe or library delete). The history
        // still records it as heard — removal is NOT a history erasure.
        await controller.removeAt(1);
        expect(controller.currentQueue.map((r) => r.identityKey), [
          'song-3',
          'song-2',
        ]);

        // Previous lands on song-2 (still queued, so it rotates normally).
        await controller.previous();
        expect(currentKey(controller), 'song-2');

        // The next Previous returns to the departed-but-still-playable song-1
        // as a TEMPORARY placeholder: it is reachable again even though it left
        // the queue, and its history membership is intact.
        await controller.previous();
        expect(currentKey(controller), 'song-1');
        expect(controller.currentQueue.map((r) => r.identityKey), [
          'song-1',
          'song-2',
          'song-3',
        ]);

        // Next re-walks the forward history (song-2, then song-3). Each
        // placeholder is dropped as it is left, so when the session winds down
        // the departed song-1 is never re-inserted into the permanent rotation.
        await controller.next();
        expect(currentKey(controller), 'song-2');
        await controller.next();
        expect(currentKey(controller), 'song-3');
        expect(controller.currentQueue.map((r) => r.identityKey), [
          'song-3',
          'song-2',
        ]);
        expect(started, [
          'song-1',
          'song-2',
          'song-3',
          'song-2',
          'song-1',
          'song-2',
          'song-3',
        ]);
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

    test(
      'a Repeat-Off finish removes from the queue but Previous still returns '
      'to the departed songs; leaving them again drops the placeholders so '
      'nothing is ever re-inserted into the permanent rotation',
      () async {
        final player = FakeAudioPlayer(
          processing: ProcessingState.ready,
          emitEvents: true,
        );
        final started = <String>[];
        final controller = await start(_MemoryPersistence(), player, started);

        await controller.playQueue([_song(1), _song(2), _song(3)]);
        // Two natural finishes (Repeat Off): each finished song LEAVES the
        // queue — only the still-unplayed song-3 remains.
        player.simulateLoad(ProcessingState.completed, false);
        await pumpEventQueue();
        expect(controller.currentQueue.map((r) => r.identityKey), [
          'song-2',
          'song-3',
        ]);
        player.simulateLoad(ProcessingState.completed, false);
        await pumpEventQueue();
        expect(controller.currentQueue.map((r) => r.identityKey), [
          'song-3',
        ]);
        expect(started, ['song-1', 'song-2', 'song-3']);

        // Previous reaches song-2 even though it finished and left the queue.
        await controller.previous();
        expect(currentKey(controller), 'song-2');
        expect(controller.currentQueue.map((r) => r.identityKey), [
          'song-2',
          'song-3',
        ]);

        // Previous again reaches song-1 (also long gone) — the walk-back is
        // unlimited: every song that was actually heard is reachable.
        await controller.previous();
        expect(currentKey(controller), 'song-1');

        // At the very start of the history, Previous restarts song-1 in place.
        await controller.previous();
        expect(currentKey(controller), 'song-1');
        expect(started, hasLength(5)); // 1,2,3 + walk-backs of 2 and 1

        // Next re-walks the forward history (song-2, then song-3). Each
        // placeholder is dropped as it is left — never rotated to the tail —
        // so the finished-and-removed songs cannot recirculate.
        await controller.next();
        expect(currentKey(controller), 'song-2');
        await controller.next();
        expect(currentKey(controller), 'song-3');
        await controller.next(); // no forward step: single real song restarts
        expect(controller.currentQueue.map((r) => r.identityKey), [
          'song-3',
        ]);
        expect(
          controller.currentQueue.map((r) => r.identityKey),
          isNot(contains('song-1')),
        );
        expect(
          controller.currentQueue.map((r) => r.identityKey),
          isNot(contains('song-2')),
        );
      },
    );

    test(
      'shuffle: Previous follows the actual listening order, not the queue '
      'rotation (all walked songs stay real queue members)',
      () async {
        final player = FakeAudioPlayer(processing: ProcessingState.ready);
        final started = <String>[];
        final controller = await start(_MemoryPersistence(), player, started);

        await controller.playQueue([_song(1), _song(2), _song(3), _song(4)]);
        await controller.setShuffle(true); // current keeps #1, tail shuffled
        expect(currentKey(controller), 'song-1');

        await controller.next();
        final second = currentKey(controller);
        await controller.next();
        final third = currentKey(controller);
        await controller.next();
        final fourth = currentKey(controller);
        expect(started, ['song-1', second, third, fourth]);
        expect(started, hasLength(4));

        // History = song-1, second, third, fourth. Previous must retrace that
        // exact listening order, no matter how the shuffled queue is ordered.
        await controller.previous();
        expect(currentKey(controller), third);
        await controller.previous();
        expect(currentKey(controller), second);
        await controller.previous();
        expect(currentKey(controller), 'song-1');
        // History start: restart song-1 in place.
        await controller.previous();
        expect(currentKey(controller), 'song-1');
        expect(
          controller.currentQueue.map((r) => r.identityKey),
          containsAll(['song-1', second, third, fourth]),
        );
      },
    );

    test(
      'a historically-recorded song deleted from the library is skipped, not '
      'guessed, on the Previous walk',
      () async {
        final player = FakeAudioPlayer(processing: ProcessingState.ready);
        final started = <String>[];
        // The resolver cannot resolve 'song-2' anymore: it was deleted.
        final controller = JustAudioController(
          playbackStorage: _MemoryPersistence(),
          songResolver: (keys) async => [
            for (final k in keys)
              if (k != 'song-2') _song(int.parse(k.split('-').last)),
          ],
          player: player,
          onTrackStart: started.add,
        );
        await pumpEventQueue();

        await controller.playQueue([_song(1), _song(2), _song(3), _song(4)]);
        await controller.next(); // song-2
        await controller.next(); // song-3
        await controller.next(); // song-4
        expect(started, ['song-1', 'song-2', 'song-3', 'song-4']);

        // "Delete" song-2: it leaves the queue AND no longer resolves.
        await controller.removeByIdentityKeys({'song-2'});

        // Previous from song-4 lands on song-3 (still queued)…
        await controller.previous();
        expect(currentKey(controller), 'song-3');

        // …and the next Previous SKIPS the deleted song-2 and lands on
        // song-1 — a graceful dead-away, never a random replacement.
        await controller.previous();
        expect(currentKey(controller), 'song-1');
      },
    );

    test(
      'branching: after walking back, directly selecting a queued song '
      'truncates the re-forward tail instead of replaying it',
      () async {
        final player = FakeAudioPlayer(processing: ProcessingState.ready);
        final started = <String>[];
        final controller = await start(_MemoryPersistence(), player, started);

        await controller.playQueue([_song(1), _song(2), _song(3), _song(4)]);
        await controller.next(); // song-2
        await controller.next(); // song-3
        expect(started, ['song-1', 'song-2', 'song-3']);

        // Walk back one step (song-3 -> song-2).
        await controller.previous();
        expect(currentKey(controller), 'song-2');

        // Directly select the still-unplayed queued song-4 via the queue sheet
        // (display index 2 in the current queue [song-2, song-3, song-4,
        // song-1]).
        await controller.jumpTo(2);
        expect(currentKey(controller), 'song-4');

        // The history must BRANCH — song-1 -> song-2 -> song-4 — the forward
        // tail through song-3 was truncated by the new selection.
        await controller.previous();
        expect(currentKey(controller), 'song-2');
        await controller.previous();
        expect(currentKey(controller), 'song-1');
        // And Next re-walks the branch forward: song-2, then song-4.
        await controller.next();
        expect(currentKey(controller), 'song-2');
        await controller.next();
        expect(currentKey(controller), 'song-4');
        // No forward step remains: Next falls through to the queue rotation
        // instead of cooking up a duplicate step.
        await controller.next();
        expect(currentKey(controller), 'song-1');
      },
    );

    test(
      'Repeat All: Previous walks the history and a natural finish still '
      'rotates the real songs (walk-backs never corrupt the rotation)',
      () async {
        final player = FakeAudioPlayer(
          processing: ProcessingState.ready,
          emitEvents: true,
        );
        final started = <String>[];
        final controller = await start(_MemoryPersistence(), player, started);

        await controller.playQueue([_song(1), _song(2), _song(3)]);
        await controller.setRepeat(RepeatMode.all);
        await controller.next(); // song-2
        await controller.next(); // song-3
        expect(started, ['song-1', 'song-2', 'song-3']);

        // Walk back twice, then walk forward again — all real members rotate.
        await controller.previous();
        await controller.previous();
        expect(currentKey(controller), 'song-1');

        // A natural finish under Repeat All rotates the finished song to the
        // end: song-2 becomes current and every song stays queued.
        player.simulateLoad(ProcessingState.completed, false);
        await pumpEventQueue();
        expect(currentKey(controller), 'song-2');
        expect(controller.currentQueue.map((r) => r.identityKey), [
          'song-2',
          'song-3',
          'song-1',
        ]);
        expect(started, [
          'song-1',
          'song-2',
          'song-3',
          'song-2',
          'song-1',
          'song-2',
        ]);

        // Previous still follows what was HEARD before song-2 (song-1), not
        // what the rotation happens to hold.
        await controller.previous();
        expect(currentKey(controller), 'song-1');
        // History start: restart song-1.
        await controller.previous();
        expect(currentKey(controller), 'song-1');
        expect(controller.currentQueue.map((r) => r.identityKey), [
          'song-1',
          'song-2',
          'song-3',
        ]);
      },
    );
  });

  group('every playback entry point emits the one authoritative track-start', () {
    test(
      'a natural track finish auto-advances and counts the new song once',
      () async {
        final player = FakeAudioPlayer(
          processing: ProcessingState.ready,
          emitEvents: true,
        );
        final started = <String>[];
        final controller = await start(_MemoryPersistence(), player, started);

        await controller.playQueue([_song(1), _song(2), _song(3)]);
        expect(started, ['song-1']);

        // The engine completes song-1 naturally. With a repeat-off queue the
        // finished song leaves and song-2 becomes current and plays — that is a
        // genuine new start and must be reported exactly once.
        player.simulateLoad(ProcessingState.completed, false);
        await pumpEventQueue();
        expect(currentKey(controller), 'song-2');
        expect(started, ['song-1', 'song-2']);

        player.simulateLoad(ProcessingState.completed, false);
        await pumpEventQueue();
        expect(currentKey(controller), 'song-3');
        expect(started, ['song-1', 'song-2', 'song-3']);

        // The finish left only song-3: a further natural finish empties the
        // session and must not fabricate a start.
        player.simulateLoad(ProcessingState.completed, false);
        await pumpEventQueue();
        expect(controller.currentQueue, isEmpty);
        expect(started, ['song-1', 'song-2', 'song-3']);
      },
    );

    test('a broken source is skipped and the replacement counts once', () async {
      final player = FakeAudioPlayer(
        processing: ProcessingState.ready,
        emitEvents: true,
      );
      final started = <String>[];
      final controller = await start(_MemoryPersistence(), player, started);

      await controller.playQueue([_song(1), _song(2)]);
      expect(started, ['song-1']);

      // The engine drops song-1 to idle *while the user still wants playback*
      // (a broken/unloadable source). The controller skips it, loads song-2 and
      // starts it — another real start, not a reload of the same song.
      player.simulateLoad(ProcessingState.idle, false);
      await pumpEventQueue();
      expect(currentKey(controller), 'song-2');
      expect(started, ['song-1', 'song-2']);
    });

    test('removing the playing current song counts the replacement; '
        'removing while paused does not', () async {
      final player = FakeAudioPlayer(processing: ProcessingState.ready);
      final started = <String>[];
      final controller = await start(_MemoryPersistence(), player, started);

      await controller.playQueue([_song(1), _song(2), _song(3)]);
      expect(started, ['song-1']);

      // Removing the current song while playing: song-2 takes over and starts.
      await controller.removeAt(0);
      expect(currentKey(controller), 'song-2');
      expect(started, ['song-1', 'song-2']);

      // Paused, then remove the current song again: song-3 becomes current but
      // only loads — it never starts, so nothing is counted.
      await controller.pause();
      await controller.removeAt(0);
      expect(currentKey(controller), 'song-3');
      expect(started, hasLength(2));
    });

    test(
      'removeByIdentityKeys of the current song counts the next start',
      () async {
        final player = FakeAudioPlayer(processing: ProcessingState.ready);
        final started = <String>[];
        final controller = await start(_MemoryPersistence(), player, started);

        await controller.playQueue([_song(1), _song(2), _song(3)]);
        expect(started, ['song-1']);

        await controller.removeByIdentityKeys({'song-1'});
        expect(currentKey(controller), 'song-2');
        expect(controller.currentQueue.map((r) => r.identityKey), [
          'song-2',
          'song-3',
        ]);
        expect(started, ['song-1', 'song-2']);
      },
    );

    test(
      'the first enqueue into an empty queue counts; later ones do not',
      () async {
        final player = FakeAudioPlayer(processing: ProcessingState.ready);
        final started = <String>[];
        final controller = await start(_MemoryPersistence(), player, started);
        expect(started, isEmpty);

        await controller.enqueue(_song(9));
        expect(currentKey(controller), 'song-9');
        expect(started, ['song-9']);

        // A second enqueue only appends to the queue; nothing new starts.
        await controller.enqueue(_song(8));
        expect(started, hasLength(1));
        expect(controller.currentQueue.map((r) => r.identityKey), [
          'song-9',
          'song-8',
        ]);
      },
    );

    test('pause resume and seek never emit a track start', () async {
      final player = FakeAudioPlayer(processing: ProcessingState.ready);
      final started = <String>[];
      final controller = await start(_MemoryPersistence(), player, started);
      await controller.playQueue([_song(1), _song(2)]);
      expect(started, ['song-1']);

      await controller.pause(); // no count
      await controller.seek(const Duration(seconds: 30)); // no count
      await controller.togglePlay(); // resume same song: no count
      await controller.seekBy(const Duration(seconds: 10)); // no count
      await controller.togglePlay(); // pause again: no count
      expect(started, ['song-1']);
    });

    test('a single-song queue finishing and looping (Repeat Off restart) '
        'counts only the original start', () async {
      // Repeat Off with one song: when it finishes naturally the queue empties
      // and playback stops — no self-loop, no fabricated start.
      final player = FakeAudioPlayer(
        processing: ProcessingState.ready,
        emitEvents: true,
      );
      final started = <String>[];
      final controller = await start(_MemoryPersistence(), player, started);

      await controller.playQueue([_song(1)]);
      expect(started, ['song-1']);

      player.simulateLoad(ProcessingState.completed, false);
      await pumpEventQueue();
      expect(controller.currentQueue, isEmpty);
      expect(started, hasLength(1));
    });

    test('the ad milestone counts starts across mixed entry points through '
        'the single authoritative event', () async {
      final player = FakeAudioPlayer(
        processing: ProcessingState.ready,
        emitEvents: true,
      );
      final adService = _RecordingAdService();
      final adController = InterstitialAdController(
        isPremium: () => false,
        service: adService,
      )..debugSetInterval(2); // every 2nd distinct start -> interstitial
      addTearDown(adController.dispose);

      final started = <String>[];
      final controller = JustAudioController(
        playbackStorage: _MemoryPersistence(),
        songResolver: (keys) async => [
          for (final k in keys) _song(int.parse(k.split('-').last)),
        ],
        player: player,
        onTrackStart: (key) {
          started.add(key);
          adController.onTrackStarted();
        },
      );
      await pumpEventQueue();
      addTearDown(controller.dispose);

      // Selection: 1 start.
      await controller.playQueue([_song(1), _song(2), _song(3), _song(4)]);
      expect(adService.showCalls, 0);
      expect(started, ['song-1']);

      // Natural finish auto-advance: 2nd start -> first interstitial.
      player.simulateLoad(ProcessingState.completed, false);
      await pumpEventQueue();
      await Future<void>.delayed(Duration.zero);
      expect(currentKey(controller), 'song-2');
      expect(started, ['song-1', 'song-2']);
      expect(adService.showCalls, 1);

      // Removing the current song: 3rd start.
      await controller.removeAt(0);
      expect(currentKey(controller), 'song-3');
      expect(started, ['song-1', 'song-2', 'song-3']);
      expect(adService.showCalls, 1);

      // Natural finish auto-advance: 4th start -> second interstitial.
      player.simulateLoad(ProcessingState.completed, false);
      await pumpEventQueue();
      await Future<void>.delayed(Duration.zero);
      expect(currentKey(controller), 'song-4');
      expect(started, ['song-1', 'song-2', 'song-3', 'song-4']);
      expect(adService.showCalls, 2);

      // Nothing new starts when the last song finishes (queue empties).
      player.simulateLoad(ProcessingState.completed, false);
      await pumpEventQueue();
      expect(controller.currentQueue, isEmpty);
      expect(adService.showCalls, 2);
    });
  });
}

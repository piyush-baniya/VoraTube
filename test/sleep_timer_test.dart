import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/player/presentation/providers/sleep_timer_provider.dart';
import 'package:vora_tube/features/player/presentation/widgets/sleep_timer_sheet.dart';

import 'fakes/fake_player.dart';

class _MemoryPersistence implements SleepTimerPersistence {
  int? endMs;

  @override
  Future<int?> readEndTimeMs() async => endMs;

  @override
  Future<void> writeEndTimeMs(int endMs) async => this.endMs = endMs;

  @override
  Future<void> clearEndTimeMs() async => endMs = null;
}

/// Records how many times [pause] was invoked and reports whether playback is
/// currently playing, so expiry behavior can be asserted precisely.
class _RecordingPlayer implements PlayerController {
  _RecordingPlayer({bool playing = true})
    : current = PlayerSnapshot.initial.copyWith(isPlaying: playing);

  @override
  PlayerSnapshot current;

  int pauseCalls = 0;

  @override
  List<SongRef> get currentQueue => const [];

  @override
  Future<void> pause() async {
    pauseCalls++;
    current = current.copyWith(isPlaying: false);
  }

  @override
  Stream<PlayerSnapshot> get snapshot => Stream.value(current);

  @override
  Stream<Duration> get positions => const Stream.empty();

  @override
  Future<void> playQueue(List<SongRef> songs, {int startIndex = 0}) async {}

  @override
  Future<void> togglePlay() async {}

  @override
  Future<void> stop() async {
    current = PlayerSnapshot.initial;
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> seekBy(Duration offset) async {}

  @override
  Future<void> next() async {}

  @override
  Future<void> previous() async {}

  @override
  Future<void> jumpTo(int index) async {}

  @override
  Future<void> enqueue(SongRef song) async {}

  @override
  Future<void> playNext(SongRef song) async {}

  @override
  Future<void> removeAt(int index) async {}

  @override
  Future<void> move(int fromIndex, int toIndex) async {}

  @override
  Future<void> moveQueueItem(int fromIndex, int toIndex) async {}

  @override
  Future<void> clearQueue() async {}

  @override
  Future<void> setShuffle(bool enabled) async {}

  @override
  Future<void> setRepeat(RepeatMode mode) async {}

  @override
  ReplayGainMode get replayGainMode => ReplayGainMode.off;

  @override
  Future<void> setReplayGainMode(
    ReplayGainMode mode, {
    double preampDb = 0,
  }) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setVolumeBoost(double multiplier) async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  group('SleepTimerState.remainingAt', () {
    test('derives remaining from the absolute end timestamp', () {
      final now = DateTime(2026, 1, 1, 0, 0, 0);
      final state = SleepTimerState.active(
        endTimeMs: now.add(const Duration(minutes: 15)).millisecondsSinceEpoch,
        duration: const Duration(minutes: 15),
      );
      expect(
        state.remainingAt(now.add(const Duration(minutes: 5))),
        const Duration(minutes: 10),
      );
    });

    test('clamps to zero once the end timestamp passes', () {
      final now = DateTime(2026, 1, 1, 0, 0, 0);
      final state = SleepTimerState.active(
        endTimeMs: now.add(const Duration(minutes: 15)).millisecondsSinceEpoch,
        duration: const Duration(minutes: 15),
      );
      expect(
        state.remainingAt(now.add(const Duration(minutes: 20))),
        Duration.zero,
      );
    });

    test('inactive and finished states report zero remaining', () {
      expect(
        const SleepTimerState.inactive().remainingAt(DateTime(2026)),
        Duration.zero,
      );
      expect(
        const SleepTimerState.finished().remainingAt(DateTime(2026)),
        Duration.zero,
      );
    });
  });

  group('SleepTimerController', () {
    test('start activates without pausing while music still plays', () {
      fakeAsync((async) {
        final player = _RecordingPlayer(playing: true);
        final pers = _MemoryPersistence();
        var now = DateTime(2026, 1, 1, 0, 0, 0);
        final c = SleepTimerController(
          player: player,
          persistence: pers,
          now: () => now,
        );
        c.start(const Duration(minutes: 15));
        async.flushMicrotasks();

        expect(c.state.isActive, isTrue);
        expect(c.state.remaining, const Duration(minutes: 15));
        expect(player.pauseCalls, 0);
        expect(pers.endMs, isNotNull);
      });
    });

    test('rejects a zero or negative duration', () {
      fakeAsync((async) {
        final c = SleepTimerController(
          player: _RecordingPlayer(),
          persistence: _MemoryPersistence(),
        );
        c.start(const Duration(seconds: 0));
        c.start(const Duration(seconds: -5));
        async.flushMicrotasks();
        expect(c.state.isInactive, isTrue);
      });
    });

    test('caps the custom duration at six hours', () {
      fakeAsync((async) {
        final c = SleepTimerController(
          player: _RecordingPlayer(),
          persistence: _MemoryPersistence(),
        );
        c.start(const Duration(hours: 24));
        async.flushMicrotasks();
        expect(c.state.isActive, isTrue);
        expect(c.state.remaining, const Duration(hours: 6));
      });
    });

    test('counts down on each tick using the wall-clock difference', () {
      fakeAsync((async) {
        var now = DateTime(2026, 1, 1, 0, 0, 0);
        final c = SleepTimerController(
          player: _RecordingPlayer(),
          persistence: _MemoryPersistence(),
          now: () => now,
        );
        c.start(const Duration(minutes: 15));
        async.flushMicrotasks();

        now = now.add(const Duration(seconds: 30));
        async.elapse(const Duration(seconds: 1));
        // The tick recomputes from now regardless of the elapse amount.
        expect(c.state.remaining, const Duration(minutes: 14, seconds: 30));
      });
    });

    test('expiry pauses playback exactly once and clears persistence', () {
      fakeAsync((async) {
        var now = DateTime(2026, 1, 1, 0, 0, 0);
        final player = _RecordingPlayer(playing: true);
        final pers = _MemoryPersistence();
        final c = SleepTimerController(
          player: player,
          persistence: pers,
          now: () => now,
        );
        c.start(const Duration(minutes: 15));
        async.flushMicrotasks();
        expect(pers.endMs, isNotNull);

        // Jump the clock past expiry and fire a single tick.
        now = now.add(const Duration(minutes: 16));
        async.elapse(const Duration(seconds: 1));

        expect(player.pauseCalls, 1);
        expect(c.state.isFinished, isTrue);
        expect(pers.endMs, isNull);
      });
    });

    test(
      'expiry does not call pause when already paused, but still finishes',
      () {
        fakeAsync((async) {
          var now = DateTime(2026, 1, 1, 0, 0, 0);
          final player = _RecordingPlayer(playing: false);
          final c = SleepTimerController(
            player: player,
            persistence: _MemoryPersistence(),
            now: () => now,
          );
          c.start(const Duration(minutes: 15));
          async.flushMicrotasks();

          now = now.add(const Duration(minutes: 16));
          async.elapse(const Duration(seconds: 1));

          expect(player.pauseCalls, 0);
          expect(c.state.isFinished, isTrue);
        });
      },
    );

    test('expiry never changes song, position, or queue', () {
      fakeAsync((async) {
        var now = DateTime(2026, 1, 1, 0, 0, 0);
        final player = _RecordingPlayer(playing: true);
        final pers = _MemoryPersistence();
        final c = SleepTimerController(
          player: player,
          persistence: pers,
          now: () => now,
        );
        c.start(const Duration(minutes: 1));
        async.flushMicrotasks();

        final currentBefore = player.current.current;
        final queueBefore = player.currentQueue;
        now = now.add(const Duration(minutes: 2));
        async.elapse(const Duration(seconds: 1));

        // pause() only flips isPlaying; the current song and queue are intact.
        expect(player.current.current, currentBefore);
        expect(player.currentQueue, queueBefore);
        expect(player.pauseCalls, 1);
      });
    });

    test('cancel stops the timer, never pauses, and clears persistence', () {
      fakeAsync((async) {
        var now = DateTime(2026, 1, 1, 0, 0, 0);
        final player = _RecordingPlayer(playing: true);
        final pers = _MemoryPersistence();
        final c = SleepTimerController(
          player: player,
          persistence: pers,
          now: () => now,
        );
        c.start(const Duration(minutes: 15));
        async.flushMicrotasks();

        c.cancel();
        async.flushMicrotasks();

        expect(c.state.isInactive, isTrue);
        expect(player.pauseCalls, 0);
        expect(pers.endMs, isNull);

        // Cancelled timer must not fire an expiry tick later.
        now = now.add(const Duration(minutes: 30));
        async.elapse(const Duration(seconds: 1));
        expect(c.state.isInactive, isTrue);
        expect(player.pauseCalls, 0);
      });
    });

    test('replacing a timer keeps a single active timer and pauses once', () {
      fakeAsync((async) {
        var now = DateTime(2026, 1, 1, 0, 0, 0);
        final player = _RecordingPlayer(playing: true);
        final c = SleepTimerController(
          player: player,
          persistence: _MemoryPersistence(),
          now: () => now,
        );
        c.start(const Duration(minutes: 10));
        c.start(const Duration(minutes: 20));
        async.flushMicrotasks();

        expect(c.state.isActive, isTrue);
        expect(c.state.remaining, const Duration(minutes: 20));

        now = now.add(const Duration(minutes: 21));
        async.elapse(const Duration(seconds: 1));
        expect(player.pauseCalls, 1);
        expect(c.state.isFinished, isTrue);
      });
    });

    test('restore resumes a future-dated timer without pausing', () {
      fakeAsync((async) {
        var now = DateTime(2026, 1, 1, 0, 0, 0);
        final player = _RecordingPlayer(playing: true);
        final pers = _MemoryPersistence();
        final c = SleepTimerController(
          player: player,
          persistence: pers,
          now: () => now,
        );
        c.start(const Duration(minutes: 30));
        async.flushMicrotasks();
        final saved = pers.endMs!;

        final c2 = SleepTimerController(
          player: _RecordingPlayer(),
          persistence: _MemoryPersistence()..endMs = saved,
          now: () => DateTime(2026, 1, 1, 0, 5, 0),
        );
        c2.restore();
        async.flushMicrotasks();

        expect(c2.state.isActive, isTrue);
        expect(c2.state.remaining, const Duration(minutes: 25));
        expect(
          c2.state.remainingAt(DateTime(2026, 1, 1, 0, 10, 0)),
          const Duration(minutes: 20),
        );
      });
    });

    test(
      'restore marks finished (without pausing) for an already-expired timer',
      () {
        fakeAsync((async) {
          final player = _RecordingPlayer(playing: true);
          final past = DateTime(2026, 1, 1, 0, 0, 0).millisecondsSinceEpoch;
          final c = SleepTimerController(
            player: player,
            persistence: _MemoryPersistence()..endMs = past,
            now: () => DateTime(2026, 1, 1, 0, 10, 0),
          );
          c.restore();
          async.flushMicrotasks();

          expect(c.state.isFinished, isTrue);
          expect(player.pauseCalls, 0);
        });
      },
    );

    test('restore does nothing when no timer was persisted', () {
      fakeAsync((async) {
        final c = SleepTimerController(
          player: _RecordingPlayer(),
          persistence: _MemoryPersistence(),
        );
        c.restore();
        async.flushMicrotasks();
        expect(c.state.isInactive, isTrue);
      });
    });

    test('dismissFinished returns the timer to inactive', () {
      fakeAsync((async) {
        var now = DateTime(2026, 1, 1, 0, 0, 0);
        final c = SleepTimerController(
          player: _RecordingPlayer(playing: true),
          persistence: _MemoryPersistence(),
          now: () => now,
        );
        c.start(const Duration(minutes: 1));
        async.flushMicrotasks();
        now = now.add(const Duration(minutes: 2));
        async.elapse(const Duration(seconds: 1));
        expect(c.state.isFinished, isTrue);

        c.dismissFinished();
        expect(c.state.isInactive, isTrue);
      });
    });
  });

  group('SleepTimerController in a ProviderScope', () {
    testWidgets('sheet shows presets and a start button when inactive', (
      tester,
    ) async {
      final controller = SleepTimerController(
        player: FakePlayerController(),
        persistence: _MemoryPersistence(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sleepTimerProvider.overrideWith((ref) => controller)],
          child: const MaterialApp(home: Scaffold(body: SizedBox())),
        ),
      );
      // Fire-and-forget: the sheet stays open until a Start button closes it.
      showSleepTimerSheet(tester.element(find.byType(Scaffold)));
      await tester.pumpAndSettle();

      expect(find.text('Sleep Timer'), findsOneWidget);
      expect(find.text('15 min'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);
      expect(find.text('Start timer'), findsOneWidget);
      // No timer may have been started by merely rendering the sheet.
      expect(controller.state.isInactive, isTrue);
    });

    testWidgets(
      'custom option lets the user set a sub-minute duration and start it',
      (tester) async {
        final player = FakePlayerController();
        final controller = SleepTimerController(
          player: player,
          persistence: _MemoryPersistence(),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playerProvider.overrideWithValue(player),
              sleepTimerProvider.overrideWith((ref) => controller),
            ],
            child: const MaterialApp(home: Scaffold(body: SizedBox())),
          ),
        );
        showSleepTimerSheet(tester.element(find.byType(Scaffold)));
        await tester.pumpAndSettle();

        // The Custom chip exposes minute and second fields.
        await tester.tap(find.text('Custom'));
        await tester.pumpAndSettle();
        expect(find.text('Minutes'), findsOneWidget);
        expect(find.text('Seconds'), findsOneWidget);

        // Enter 1 minute 30 seconds and confirm the preview updates.
        await tester.enterText(
          find.widgetWithText(TextField, 'Minutes'),
          '1',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Seconds'),
          '30',
        );
        await tester.pumpAndSettle();
        expect(find.text('Custom: 01:30'), findsOneWidget);

        await tester.tap(find.text('Start timer'));
        await tester.pumpAndSettle();

        expect(controller.state.isActive, isTrue);
        expect(controller.state.remaining, const Duration(minutes: 1, seconds: 30));
      },
    );

    testWidgets('sheet shows a countdown and turn-off button when active', (
      tester,
    ) async {
      final player = FakePlayerController();
      final controller = SleepTimerController(
        player: player,
        persistence: _MemoryPersistence(),
      );
      // Pre-activate with a well-known remaining duration (no real Timer).
      controller.start(const Duration(minutes: 30));
      await null; // settle the async write

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerProvider.overrideWithValue(player),
            sleepTimerProvider.overrideWith((ref) => controller),
          ],
          child: const MaterialApp(home: Scaffold(body: SizedBox())),
        ),
      );
      showSleepTimerSheet(tester.element(find.byType(Scaffold)));
      await tester.pumpAndSettle();

      expect(find.text('Playback stops in 30:00'), findsOneWidget);
      expect(find.text('Turn off timer'), findsOneWidget);

      await controller.cancel();
      await tester.pumpAndSettle();
    });

    testWidgets('finished dialog renders title and dismisses', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: SizedBox())),
        ),
      );
      showSleepTimerFinishedDialog(tester.element(find.byType(Scaffold)));
      await tester.pumpAndSettle();

      expect(find.text('Sleep Timer Finished'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text('Sleep Timer Finished'), findsNothing);
    });
  });
}

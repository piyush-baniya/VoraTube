import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/features/ringtones/data/audio_util_service.dart';
import 'package:vora_tube/features/ringtones/domain/ringtone_selection.dart';
import 'package:vora_tube/features/ringtones/presentation/ringtone_cutter_controller.dart';
import 'package:vora_tube/features/ringtones/presentation/ringtone_previewer.dart';

SongRef _song() => const SongRef(
  identityKey: 'ms:1',
  uri: 'content://media/external/audio/media/1',
  title: 'Test Song',
  artist: 'Artist',
  durationMs: 120000,
);

typedef CutRequest = ({int startMs, int endMs});

class _FakeAudioUtilService implements AudioUtilService {
  String? failWith;
  Completer<void>? gate;
  int pickerResult = 1; // 0 cancel, 1 assign
  bool throwOnPicker = false;
  final List<CutRequest> cutRequests = [];

  @override
  Future<bool> supportsCutting() async => true;

  @override
  Future<AudioCutResult> cutAudio({
    required String sourceUri,
    required int startMs,
    required int endMs,
    required String songTitle,
  }) async {
    cutRequests.add((startMs: startMs, endMs: endMs));
    await gate?.future;
    if (failWith != null) {
      throw RingtoneOperationException(failWith!, 'boom');
    }
    return AudioCutResult(
      path: '/data/ringtones/$songTitle - Ringtone.m4a',
      contentUri: 'content://media/external/audio/media/9',
      durationMs: endMs - startMs,
    );
  }

  @override
  Future<RingtonePickerResult> openRingtonePicker(String contentUri) async {
    if (throwOnPicker) {
      throw const RingtoneOperationException('picker_unavailable', 'no picker');
    }
    return pickerResult == 1
        ? RingtonePickerResult.assigned
        : RingtonePickerResult.cancelled;
  }
}

class _FakePlayer implements PlayerController {
  final _positions = StreamController<Duration>.broadcast();
  final playQueueCalls = <List<SongRef>>[];
  final seekCalls = <Duration>[];
  final pauses = <int>[];
  PlayerSnapshot _current = PlayerSnapshot.initial;
  List<SongRef> _queue = const [];

  @override
  Stream<Duration> get positions => _positions.stream;
  @override
  Stream<PlayerSnapshot> get snapshot => const Stream<PlayerSnapshot>.empty();
  @override
  PlayerSnapshot get current => _current;
  @override
  List<SongRef> get currentQueue => List.of(_queue);

  void emitPosition(Duration d) => _positions.add(d);

  @override
  Future<void> playQueue(List<SongRef> songs, {int startIndex = 0}) async {
    playQueueCalls.add(List.of(songs));
    _queue = List.of(songs);
    _current = PlayerSnapshot.initial.copyWith(
      isPlaying: true,
      queueLength: songs.length,
      currentIndex: songs.isEmpty ? -1 : startIndex,
      current: songs.isEmpty
          ? null
          : songs[startIndex.clamp(0, songs.length - 1)],
    );
  }

  @override
  Future<void> pause() async {
    pauses.add(pauses.length);
    _current = _current.copyWith(isPlaying: false);
  }

  @override
  Future<void> seek(Duration position) async => seekCalls.add(position);

  @override
  Future<void> dispose() async {}

  @override
  Future<void> togglePlay() async {}
  @override
  Future<void> stop() async {}
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
  Future<void> move(int from, int to) async {}
  @override
  Future<void> moveQueueItem(int from, int to) async {}
  @override
  Future<void> clearQueue() async {}
  @override
  Future<void> setShuffle(bool enabled) async {}
  @override
  Future<void> setRepeat(RepeatMode mode) async {}
  @override
  Future<void> setReplayGainMode(ReplayGainMode mode) async {}
  @override
  ReplayGainMode get replayGainMode => ReplayGainMode.off;
}

void main() {
  group('RingtoneSelection clamping', () {
    test(
      'valid selection from a known track starts at zero and ends at length',
      () {
        final s = RingtoneSelection.forTrack(durationMs: 90000);
        expect(s.isValid, isTrue);
        expect(s.start, Duration.zero);
        expect(s.end.inMilliseconds, 90000);
        expect(s.isUsable, isTrue);
      },
    );

    test('zero or negative duration is invalid and unusable', () {
      final s0 = RingtoneSelection.forTrack(durationMs: 0);
      expect(s0.isValid, isFalse);
      expect(s0.isUsable, isFalse);
      final sn = RingtoneSelection.forTrack(durationMs: -5);
      expect(sn.isValid, isFalse);
      expect(sn.total, Duration.zero);
    });

    test('start handle clamps at zero', () {
      final s = RingtoneSelection.forTrack(durationMs: 30000).withStart(-5000);
      expect(s.start, Duration.zero);
      expect(s.isUsable, isTrue);
    });

    test('end handle clamps at total duration', () {
      final s = RingtoneSelection.forTrack(durationMs: 30000).withEnd(999999);
      expect(s.end.inMilliseconds, 30000);
    });

    test('start can never overtake the end (minimum duration preserved)', () {
      final s = RingtoneSelection.forTrack(durationMs: 10000).withStart(9000);
      expect(
        s.duration,
        greaterThanOrEqualTo(RingtoneSelection.minimumDuration),
      );
      expect(s.start.inMilliseconds, lessThan(s.end.inMilliseconds));
    });

    test('end can never drop below the start (minimum duration preserved)', () {
      final s = RingtoneSelection.forTrack(durationMs: 10000).withEnd(3000);
      expect(
        s.duration,
        greaterThanOrEqualTo(RingtoneSelection.minimumDuration),
      );
      expect(s.start.inMilliseconds, lessThan(s.end.inMilliseconds));
    });

    test('selection equal to the full track is valid', () {
      final s = RingtoneSelection.forTrack(durationMs: 5000).selectAll();
      expect(s.isUsable, isTrue);
      expect(s.start, Duration.zero);
      expect(s.end.inMilliseconds, 5000);
    });

    test('formatCeil rounds up and keeps seconds two digits', () {
      expect(
        RingtoneSelection.formatCeil(const Duration(milliseconds: 500)),
        '0:01',
      );
      expect(
        RingtoneSelection.formatCeil(const Duration(minutes: 1, seconds: 5)),
        '1:05',
      );
      expect(RingtoneSelection.formatCeil(const Duration(minutes: 2)), '2:00');
    });
  });

  group('RingtoneCutterController export', () {
    test(
      'export succeeds and records the clip with the full-track window',
      () async {
        final service = _FakeAudioUtilService();
        final c = RingtoneCutterController(service: service, durationMs: 120000)
          ..attachTrack(sourceUri: _song().uri, title: _song().title);
        final clip = await c.export();
        expect(clip.contentUri, isNotEmpty);
        expect(c.lastExport, same(clip));
        expect(c.lastError, isNull);
        expect(service.cutRequests.single, (startMs: 0, endMs: 120000));
      },
    );

    test('rejects export for an unusable selection', () async {
      final c = RingtoneCutterController(
        service: _FakeAudioUtilService(),
        durationMs: 0,
      )..attachTrack(sourceUri: _song().uri, title: _song().title);
      expect(c.selection.isUsable, isFalse);
      await expectLater(c.export(), throwsA(isA<RingtoneOperationException>()));
    });

    test('rejects export when no source was attached', () async {
      final c = RingtoneCutterController(
        service: _FakeAudioUtilService(),
        durationMs: 120000,
      );
      expect(c.hasSource, isFalse);
      await expectLater(c.export(), throwsA(isA<RingtoneOperationException>()));
    });

    test('prevents duplicate concurrent exports (busy guard)', () async {
      final service = _FakeAudioUtilService()..gate = Completer<void>();
      final c = RingtoneCutterController(service: service, durationMs: 120000)
        ..attachTrack(sourceUri: _song().uri, title: _song().title);

      final first = c.export();
      expect(c.isBusy, isTrue);
      await expectLater(c.export(), throwsA(isA<RingtoneOperationException>()));

      service.gate!.complete();
      final clip = await first;
      expect(clip, isNotNull);
      expect(c.isBusy, isFalse);
      expect(service.cutRequests, hasLength(1));
    });

    test('failure is surfaced and does not wedge the controller', () async {
      final service = _FakeAudioUtilService()..failWith = 'cut_failed';
      final c = RingtoneCutterController(service: service, durationMs: 120000)
        ..attachTrack(sourceUri: _song().uri, title: _song().title);
      await expectLater(c.export(), throwsA(isA<RingtoneOperationException>()));
      expect(c.lastError, isNotNull);
      expect(c.isBusy, isFalse);
      // A subsequent export succeeds after the failure clears.
      service.failWith = null;
      final clip = await c.export();
      expect(clip, isNotNull);
      expect(c.lastError, isNull);
    });

    test('changing the selection clears the last export', () async {
      final service = _FakeAudioUtilService();
      final c = RingtoneCutterController(service: service, durationMs: 120000)
        ..attachTrack(sourceUri: _song().uri, title: _song().title);
      await c.export();
      expect(c.lastExport, isNotNull);
      c.setEndMs(60000);
      expect(c.lastExport, isNull);
    });
  });

  group('RingtoneCutterController set-as-ringtone', () {
    test('assigned outcome when the picker is confirmed', () async {
      final service = _FakeAudioUtilService()..pickerResult = 1;
      final c = RingtoneCutterController(service: service, durationMs: 120000)
        ..attachTrack(sourceUri: _song().uri, title: _song().title);
      final outcome = await c.setAsRingtone();
      expect(outcome, SetRingtoneOutcome.assigned);
      expect(c.lastSetRingtoneOutcome, SetRingtoneOutcome.assigned);
    });

    test('cancelled outcome when the user closes the picker', () async {
      final service = _FakeAudioUtilService()..pickerResult = 0;
      final c = RingtoneCutterController(service: service, durationMs: 120000)
        ..attachTrack(sourceUri: _song().uri, title: _song().title);
      final outcome = await c.setAsRingtone();
      expect(outcome, SetRingtoneOutcome.cancelled);
    });

    test('failed outcome on export failure (no picker launched)', () async {
      final service = _FakeAudioUtilService()..failWith = 'cut_failed';
      final c = RingtoneCutterController(service: service, durationMs: 120000)
        ..attachTrack(sourceUri: _song().uri, title: _song().title);
      final outcome = await c.setAsRingtone();
      expect(outcome, SetRingtoneOutcome.failed);
    });

    test('failed outcome when the picker cannot be opened', () async {
      final service = _FakeAudioUtilService()..throwOnPicker = true;
      final c = RingtoneCutterController(service: service, durationMs: 120000)
        ..attachTrack(sourceUri: _song().uri, title: _song().title);
      final outcome = await c.setAsRingtone();
      expect(outcome, SetRingtoneOutcome.failed);
    });
  });

  group('RingtonePreviewer', () {
    test('loops back to start only when the position passes the end', () async {
      final player = _FakePlayer();
      final sel = RingtoneSelection.forTrack(durationMs: 20000).withEnd(6000);
      final p = RingtonePreviewer(player);
      await p.start(song: _song(), selection: sel);
      expect(p.isPreviewing, isTrue);
      player.seekCalls.clear();

      // Inside the window: no loop.
      player.emitPosition(const Duration(milliseconds: 4000));
      await pumpEventQueue();
      expect(player.seekCalls, isEmpty);

      // Past the end: loops back to the start.
      player.emitPosition(const Duration(milliseconds: 7000));
      await pumpEventQueue();
      expect(player.seekCalls, contains(sel.start));
    });

    test('stop restores the previous queue and play state', () async {
      final player = _FakePlayer();
      player.playQueue([_song()]); // pre-existing session
      final sel = RingtoneSelection.forTrack(durationMs: 20000).withEnd(6000);
      final p = RingtonePreviewer(player);

      await p.start(song: _song(), selection: sel);
      expect(player.currentQueue, hasLength(1)); // preview queue (single song)
      player.playQueueCalls.clear();

      await p.stop();
      expect(p.isPreviewing, isFalse);
      // The saved session was replayed and re-paused (it was playing before).
      expect(player.playQueueCalls, hasLength(1));
    });
  });
}

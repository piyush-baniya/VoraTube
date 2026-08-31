import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/player/presentation/widgets/mini_player.dart';

import 'fakes/fake_player.dart';

SongRef _song({int id = 1, String title = 'Test Song'}) {
  return SongRef(
    identityKey: 'ms:$id',
    uri: 'content://media/external/audio/media/$id',
    title: title,
    artist: 'Test Artist',
    album: 'Test Album',
    durationMs: 200000,
  );
}

/// A [FakePlayerController] whose [PlayerController.snapshot] stream emits
/// live [PlayerSnapshot]s. Used to prove the MiniPlayer updates immediately
/// when the authoritative current track changes — not only after a pause/play
/// round-trip.
class _StreamPlayer extends FakePlayerController {
  _StreamPlayer({required PlayerSnapshot initial}) : super(initial: initial);

  final _snapshots = StreamController<PlayerSnapshot>.broadcast();

  @override
  Stream<PlayerSnapshot> get snapshot => _snapshots.stream;

  void push(PlayerSnapshot snap) {
    if (!_snapshots.isClosed) _snapshots.add(snap);
  }
}

/// Records which playback actions the UI triggers, so tests can assert that
/// controls and gestures dispatch to the real controller rather than faking.
class _RecordingPlayer extends FakePlayerController {
  _RecordingPlayer({super.initial, super.queue});

  final List<String> calls = [];

  @override
  Future<void> stop() async {
    calls.add('stop');
    current = PlayerSnapshot.initial;
  }

  @override
  Future<void> previous() async => calls.add('previous');

  @override
  Future<void> next() async => calls.add('next');

  @override
  Future<void> seek(Duration position) async => calls.add('seek');

  @override
  Future<void> togglePlay() async => calls.add('togglePlay');
}

void main() {
  late AppDatabase db;
  late LibraryRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = LibraryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  ProviderScope _wrap(FakePlayerController player) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        libraryRepositoryProvider.overrideWithValue(repository),
        playerProvider.overrideWithValue(player),
      ],
      child: MaterialApp(home: MiniPlayer()),
    );
  }

  _RecordingPlayer _playerWithTrack({bool atStart = false}) => _RecordingPlayer(
    initial: PlayerSnapshot(
      status: PlayerStatus.ready,
      isPlaying: false,
      repeatMode: RepeatMode.off,
      shuffleEnabled: false,
      queueLength: 2,
      currentIndex: atStart ? 0 : 1,
      durationMs: 200000,
      current: _song(),
    ),
    queue: [
      _song(id: 1),
      _song(id: 2, title: 'Song 2'),
    ],
  );

  testWidgets('renders artwork, title, artist and transport controls', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_playerWithTrack()));
    await tester.pumpAndSettle();

    expect(find.text('Test Song'), findsOneWidget);
    expect(find.text('Test Artist'), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
  });

  testWidgets('is hidden when no track is loaded', (tester) async {
    await tester.pumpWidget(_wrap(_RecordingPlayer()));
    await tester.pump();

    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsNothing);
    expect(find.text('Test Song'), findsNothing);
  });

  testWidgets(
    'updates the displayed track immediately when the current track changes',
    (tester) async {
      // Regression (Phase 1, Fix 3): selecting a new song must refresh the
      // MiniPlayer instantly — it must never require a pause/play round-trip.
      final player = _StreamPlayer(
        initial: PlayerSnapshot(
          status: PlayerStatus.ready,
          isPlaying: false,
          repeatMode: RepeatMode.off,
          shuffleEnabled: false,
          queueLength: 2,
          currentIndex: 0,
          durationMs: 200000,
          current: _song(id: 1, title: 'Song A'),
        ),
      );

      await tester.pumpWidget(_wrap(player));
      await tester.pump();
      expect(find.text('Song A'), findsOneWidget);

      // Switch to Song B through the authoritative snapshot stream.
      player.push(
        PlayerSnapshot(
          status: PlayerStatus.ready,
          isPlaying: false,
          repeatMode: RepeatMode.off,
          shuffleEnabled: false,
          queueLength: 2,
          currentIndex: 1,
          durationMs: 200000,
          current: _song(id: 2, title: 'Song B'),
        ),
      );
      // No pause/play — just let the provider recompute from the stream.
      await tester.pumpAndSettle();

      expect(find.text('Song B'), findsOneWidget);
      expect(find.text('Song A'), findsNothing);
    },
  );

  testWidgets('previous disabled for a single song dispatches nothing', (
    tester,
  ) async {
    final player = _RecordingPlayer(
      initial: PlayerSnapshot(
        status: PlayerStatus.ready,
        isPlaying: false,
        repeatMode: RepeatMode.off,
        shuffleEnabled: false,
        queueLength: 1,
        currentIndex: 0,
        durationMs: 200000,
        current: _song(),
      ),
      queue: [_song(id: 1)],
    );
    await tester.pumpWidget(_wrap(player));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.skip_previous_rounded));
    await tester.pumpAndSettle();

    expect(player.calls, isNot(contains('previous')));
  });

  testWidgets('next dispatches next action', (tester) async {
    final player = _playerWithTrack(atStart: true);
    await tester.pumpWidget(_wrap(player));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pumpAndSettle();

    expect(player.calls, contains('next'));
  });

  testWidgets('play/pause button dispatches togglePlay', (tester) async {
    final player = _playerWithTrack(atStart: true);
    await tester.pumpWidget(_wrap(player));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();

    expect(player.calls, contains('togglePlay'));
  });

  testWidgets('a quick downward fling stops playback', (tester) async {
    final player = _playerWithTrack();
    await tester.pumpWidget(_wrap(player));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(MiniPlayer), const Offset(0, 120), 2500);
    await tester.pumpAndSettle();

    expect(player.calls, contains('stop'));
  });

  testWidgets('tapping the progress bar seeks', (tester) async {
    final player = _playerWithTrack();
    await tester.pumpWidget(_wrap(player));
    await tester.pumpAndSettle();

    // Tap the progress bar hit-area precisely via its key.
    await tester.tap(find.byKey(const Key('mini_progress')));
    await tester.pump();

    expect(player.calls, contains('seek'));
  });

  testWidgets('transport controls expose accessibility labels', (tester) async {
    final player = _playerWithTrack(atStart: true);
    await tester.pumpWidget(_wrap(player));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Previous'), findsOneWidget);
    expect(find.bySemanticsLabel('Play'), findsWidgets);
    expect(find.bySemanticsLabel('Next'), findsOneWidget);

    // While playing, the primary control reads as Pause.
    final playing = _RecordingPlayer(
      initial: PlayerSnapshot(
        status: PlayerStatus.ready,
        isPlaying: true,
        repeatMode: RepeatMode.off,
        shuffleEnabled: false,
        queueLength: 2,
        currentIndex: 0,
        durationMs: 200000,
        current: _song(),
      ),
      queue: [
        _song(id: 1),
        _song(id: 2, title: 'Song 2'),
      ],
    );
    await tester.pumpWidget(_wrap(playing));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
  });
}

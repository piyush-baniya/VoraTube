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
import 'package:vora_tube/features/player/presentation/screens/full_player_screen.dart';
import 'package:vora_tube/features/player/presentation/widgets/mini_player.dart';
import 'package:vora_tube/features/player/presentation/widgets/player_progress.dart';
import 'package:vora_tube/features/player/presentation/widgets/rotating_artwork.dart';
import 'package:vora_tube/shared/widgets/artwork_view.dart';

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
  }

  @override
  Future<void> clearSession() async {
    calls.add('clearSession');
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

/// Applies shuffle toggles to its snapshot and broadcasts them through the
/// authoritative snapshot stream, exactly as the engine does, so the surfaces
/// that watch playback state re-render without any manual pushing.
class _ShufflePlayer extends _RecordingPlayer {
  _ShufflePlayer({required super.initial, super.queue = const []});

  final List<bool> shuffleCalls = [];

  @override
  Future<void> setShuffle(bool enabled) async {
    calls.add('setShuffle');
    shuffleCalls.add(enabled);
    pushSnapshot(current.copyWith(shuffleEnabled: enabled));
  }
}

_ShufflePlayer _shufflePlayer({
  required bool shuffleEnabled,
  bool isPlaying = false,
}) {
  return _ShufflePlayer(
    initial: PlayerSnapshot(
      status: PlayerStatus.ready,
      isPlaying: isPlaying,
      repeatMode: RepeatMode.off,
      shuffleEnabled: shuffleEnabled,
      queueLength: 2,
      currentIndex: 0,
      durationMs: 200000,
      current: _song(),
    ),
    queue: [_song(id: 1), _song(id: 2, title: 'Song 2')],
  );
}

void main() {
  late AppDatabase db;
  late LibraryRepository repository;

  setUpAll(() {
    // The FullPlayerScreen animations must settle for the cross-surface
    // shuffle-sync tests to pump cleanly.
    disableBackgroundPulseForTesting();
    disableRotatingArtworkForTesting();
    disableWaveTimelineForTesting();
  });

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
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
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

  testWidgets('a horizontal swipe started on the transport controls dispatches next', (
    tester,
  ) async {
    final player = _playerWithTrack(atStart: true);
    await tester.pumpWidget(_wrap(player));
    await tester.pumpAndSettle();

    // Start the swipe over a control button, NOT the middle of the card, to
    // prove the whole card surface participates in the swipe gesture.
    await tester.fling(
      find.byIcon(Icons.skip_previous_rounded),
      const Offset(200, 0),
      1500,
    );
    await tester.pumpAndSettle();

    expect(player.calls, contains('next'));
  });

  testWidgets('swipe left dispatches previous', (tester) async {
    final player = _playerWithTrack();
    await tester.pumpWidget(_wrap(player));
    await tester.pumpAndSettle();

    await tester.fling(
      find.byType(MiniPlayer),
      const Offset(-200, 0),
      1500,
    );
    await tester.pumpAndSettle();

    expect(player.calls, contains('previous'));
  });

  testWidgets('a small horizontal nudge springs back without skipping', (
    tester,
  ) async {
    final player = _playerWithTrack();
    await tester.pumpWidget(_wrap(player));
    await tester.pumpAndSettle();

    final card = tester.getCenter(find.byType(MiniPlayer));
    final gesture = await tester.startGesture(card);
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(player.calls, isNot(contains('next')));
    expect(player.calls, isNot(contains('previous')));
  });

  testWidgets('a quick downward fling stops playback', (tester) async {
    final player = _playerWithTrack();
    await tester.pumpWidget(_wrap(player));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(MiniPlayer), const Offset(0, 120), 2500);
    await tester.pumpAndSettle();

    expect(player.calls, contains('clearSession'));
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

  group('Shuffle button', () {
    testWidgets('renders shuffle OFF when shuffle is disabled', (tester) async {
      await tester.pumpWidget(_wrap(_shufflePlayer(shuffleEnabled: false)));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.shuffle_on_rounded), findsNothing);
      expect(find.bySemanticsLabel('Shuffle'), findsOneWidget);
    });

    testWidgets('renders shuffle ON when shuffle is enabled', (tester) async {
      await tester.pumpWidget(_wrap(_shufflePlayer(shuffleEnabled: true)));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.shuffle_on_rounded), findsOneWidget);
      expect(find.byIcon(Icons.shuffle_rounded), findsNothing);
    });

    testWidgets(
      'tapping shuffle toggles the authoritative player state but never '
      'opens the full player',
      (tester) async {
        final player = _shufflePlayer(shuffleEnabled: false);
        await tester.pumpWidget(_wrap(player));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.shuffle_rounded));
        await tester.pump();
        expect(player.shuffleCalls, [true]);
        expect(find.byIcon(Icons.shuffle_on_rounded), findsOneWidget);

        await tester.tap(find.byIcon(Icons.shuffle_on_rounded));
        await tester.pumpAndSettle();
        expect(player.shuffleCalls, [true, false]);
        expect(player.current.shuffleEnabled, isFalse);
        expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
        expect(find.byType(FullPlayerScreen), findsNothing);
      },
    );

    testWidgets(
      'shuffle state pushed by the Full Player is reflected immediately',
      (tester) async {
        final player = _shufflePlayer(shuffleEnabled: false);
        await tester.pumpWidget(_wrap(player));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);

        // Exactly what the Full Player does when its shuffle button is tapped.
        await player.setShuffle(true);
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.shuffle_on_rounded), findsOneWidget);
        expect(player.current.shuffleEnabled, isTrue);
      },
    );

    testWidgets(
      'shuffle enabled in the Mini Player shows ON in the Full Player',
      (tester) async {
        final player = _shufflePlayer(shuffleEnabled: false);
        await tester.pumpWidget(_wrap(player));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.shuffle_rounded));
        await tester.pump();
        expect(player.current.shuffleEnabled, isTrue);

        await tester.tap(find.byType(CompactArtwork));
        await tester.pumpAndSettle();
        expect(find.byType(FullPlayerScreen), findsOneWidget);

        expect(
          find.descendant(
            of: find.byType(FullPlayerScreen),
            matching: find.byIcon(Icons.shuffle_on_rounded),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'shuffle toggled in the Full Player shows ON in the Mini Player after '
      'returning',
      (tester) async {
        final player = _shufflePlayer(shuffleEnabled: false);
        await tester.pumpWidget(_wrap(player));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(CompactArtwork));
        await tester.pumpAndSettle();
        expect(find.byType(FullPlayerScreen), findsOneWidget);

        final fullShuffle = find.descendant(
          of: find.byType(FullPlayerScreen),
          matching: find.byIcon(Icons.shuffle_rounded),
        );
        expect(fullShuffle, findsOneWidget);
        await tester.tap(fullShuffle);
        await tester.pumpAndSettle();
        expect(player.shuffleCalls, [true]);

        // Let the Full Player's "Shuffle on" toast auto-dismiss so no timer
        // outlives the test.
        await tester.pump(const Duration(seconds: 2));

        // Close the full player back onto the Mini Player.
        await tester.tap(
          find
              .descendant(
                of: find.byType(FullPlayerScreen),
                matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.byType(FullPlayerScreen), findsNothing);

        expect(
          find.descendant(
            of: find.byType(MiniPlayer),
            matching: find.byIcon(Icons.shuffle_on_rounded),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'rapid toggling settles on the last request without interrupting '
      'playback',
      (tester) async {
        final player = _shufflePlayer(shuffleEnabled: false, isPlaying: true);
        await tester.pumpWidget(_wrap(player));
        await tester.pumpAndSettle();

        // Four alternating taps with no settle between them.
        await tester.tap(find.byIcon(Icons.shuffle_rounded));
        await tester.pump();
        await tester.tap(find.byIcon(Icons.shuffle_on_rounded));
        await tester.pump();
        await tester.tap(find.byIcon(Icons.shuffle_rounded));
        await tester.pump();
        await tester.tap(find.byIcon(Icons.shuffle_on_rounded));
        await tester.pumpAndSettle();

        expect(player.shuffleCalls, [true, false, true, false]);
        expect(player.current.shuffleEnabled, isFalse);
        expect(player.current.isPlaying, isTrue);
        expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
        // Only the shuffle action was dispatched: playback was never paused,
        // seeked, restarted or skipped.
        expect(player.calls.where((c) => c != 'setShuffle'), isEmpty);
        expect(find.byType(FullPlayerScreen), findsNothing);
      },
    );
  });
}

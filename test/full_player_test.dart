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
import 'package:vora_tube/features/player/presentation/widgets/player_controls.dart';
import 'package:vora_tube/features/player/presentation/widgets/player_progress.dart';
import 'package:vora_tube/features/player/presentation/widgets/rotating_artwork.dart';

import 'fakes/fake_player.dart';

SongRef _testSong({
  int id = 1,
  String title = 'Test Song',
  String? artist = 'Test Artist',
  String? artPath,
}) {
  return SongRef(
    identityKey: 'ms:$id',
    uri: 'content://media/external/audio/media/$id',
    title: title,
    artist: artist,
    album: 'Test Album',
    artPath: artPath,
    durationMs: 200000,
  );
}

void main() {
  late AppDatabase db;
  late LibraryRepository repository;

  setUpAll(() {
    // Disable background pulse animation for tests to prevent pumpAndSettle timeout.
    disableBackgroundPulseForTesting();
    disableRotatingArtworkForTesting();
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = LibraryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  ProviderScope _wrap(Widget child, {FakePlayerController? player}) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        libraryRepositoryProvider.overrideWithValue(repository),
        playerProvider.overrideWithValue(
          player ??
              FakePlayerController(
                initial: PlayerSnapshot(
                  status: PlayerStatus.ready,
                  isPlaying: false,
                  repeatMode: RepeatMode.off,
                  shuffleEnabled: false,
                  queueLength: 2,
                  currentIndex: 0,
                  durationMs: 200000,
                  current: _testSong(),
                ),
                queue: [
                  _testSong(id: 1),
                  _testSong(id: 2, title: 'Song 2'),
                ],
              ),
        ),
      ],
      child: MaterialApp(home: child),
    );
  }

  // -------------------------------------------------------------------------
  // Full player screen renders
  // -------------------------------------------------------------------------

  group('FullPlayerScreen', () {
    testWidgets('renders song title and artist when track is playing', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const FullPlayerScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Test Song'), findsOneWidget);
      expect(find.text('Test Artist'), findsOneWidget);
    });

    testWidgets('shows empty state when no track', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FullPlayerScreen(),
          player: FakePlayerController(initial: PlayerSnapshot.initial),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No song playing'), findsOneWidget);
    });

    testWidgets('renders play button', (tester) async {
      await tester.pumpWidget(_wrap(const FullPlayerScreen()));
      await tester.pumpAndSettle();

      // Play button is shown (not paused).
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('shows pause icon when playing', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FullPlayerScreen(),
          player: FakePlayerController(
            initial: PlayerSnapshot(
              status: PlayerStatus.ready,
              isPlaying: true,
              repeatMode: RepeatMode.off,
              shuffleEnabled: false,
              queueLength: 2,
              currentIndex: 0,
              durationMs: 200000,
              current: _testSong(),
            ),
            queue: [
              _testSong(id: 1),
              _testSong(id: 2, title: 'Song 2'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    });

    testWidgets('renders previous and next buttons', (tester) async {
      await tester.pumpWidget(_wrap(const FullPlayerScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    });

    testWidgets('renders shuffle and repeat buttons', (tester) async {
      await tester.pumpWidget(_wrap(const FullPlayerScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
    });

    testWidgets('renders queue button in top bar', (tester) async {
      await tester.pumpWidget(_wrap(const FullPlayerScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.queue_music_rounded), findsOneWidget);
    });

    testWidgets('renders favorite button', (tester) async {
      await tester.pumpWidget(_wrap(const FullPlayerScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    });

    testWidgets('renders progress bar', (tester) async {
      await tester.pumpWidget(_wrap(const FullPlayerScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Player controls interaction
  // -------------------------------------------------------------------------

  group('PlayerControls', () {
    testWidgets('play/pause button calls togglePlay', (tester) async {
      bool toggled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerControls(
              snapshot: const PlayerSnapshot(
                status: PlayerStatus.ready,
                isPlaying: false,
                repeatMode: RepeatMode.off,
                shuffleEnabled: false,
                queueLength: 3,
                currentIndex: 1,
                durationMs: 200000,
                current: null,
              ),
              onTogglePlay: () => toggled = true,
              onPrevious: () {},
              onNext: () {},
              onRewind10: () {},
              onForward10: () {},
              onToggleShuffle: () {},
              onToggleRepeat: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      expect(toggled, isTrue);
    });

    testWidgets('next button calls onNext', (tester) async {
      bool called = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerControls(
              snapshot: const PlayerSnapshot(
                status: PlayerStatus.ready,
                isPlaying: true,
                repeatMode: RepeatMode.off,
                shuffleEnabled: false,
                queueLength: 3,
                currentIndex: 1,
                durationMs: 200000,
                current: null,
              ),
              onTogglePlay: () {},
              onPrevious: () {},
              onNext: () => called = true,
              onRewind10: () {},
              onForward10: () {},
              onToggleShuffle: () {},
              onToggleRepeat: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      expect(called, isTrue);
    });

    testWidgets('previous button calls onPrevious', (tester) async {
      bool called = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerControls(
              snapshot: const PlayerSnapshot(
                status: PlayerStatus.ready,
                isPlaying: true,
                repeatMode: RepeatMode.off,
                shuffleEnabled: false,
                queueLength: 3,
                currentIndex: 1,
                durationMs: 200000,
                current: null,
              ),
              onTogglePlay: () {},
              onPrevious: () => called = true,
              onNext: () {},
              onRewind10: () {},
              onForward10: () {},
              onToggleShuffle: () {},
              onToggleRepeat: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.skip_previous_rounded));
      expect(called, isTrue);
    });

    testWidgets('next is disabled at queue end without repeat-all', (
      tester,
    ) async {
      bool nextCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerControls(
              snapshot: const PlayerSnapshot(
                status: PlayerStatus.ready,
                isPlaying: true,
                repeatMode: RepeatMode.off,
                shuffleEnabled: false,
                queueLength: 3,
                currentIndex: 2,
                durationMs: 200000,
                current: null,
              ),
              onTogglePlay: () {},
              onPrevious: () {},
              onNext: () => nextCalled = true,
              onRewind10: () {},
              onForward10: () {},
              onToggleShuffle: () {},
              onToggleRepeat: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      expect(nextCalled, isFalse);
    });

    testWidgets('previous is disabled at index 0 without repeat-all', (
      tester,
    ) async {
      bool prevCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerControls(
              snapshot: const PlayerSnapshot(
                status: PlayerStatus.ready,
                isPlaying: true,
                repeatMode: RepeatMode.off,
                shuffleEnabled: false,
                queueLength: 3,
                currentIndex: 0,
                durationMs: 200000,
                current: null,
              ),
              onTogglePlay: () {},
              onPrevious: () => prevCalled = true,
              onNext: () {},
              onRewind10: () {},
              onForward10: () {},
              onToggleShuffle: () {},
              onToggleRepeat: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.skip_previous_rounded));
      expect(prevCalled, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Full player taps through to controller
  // -------------------------------------------------------------------------

  group('Full player controller integration', () {
    testWidgets('tapping play button triggers togglePlay', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final player = _TestablePlayer(
        initial: PlayerSnapshot(
          status: PlayerStatus.ready,
          isPlaying: false,
          repeatMode: RepeatMode.off,
          shuffleEnabled: false,
          queueLength: 2,
          currentIndex: 0,
          durationMs: 200000,
          current: _testSong(),
        ),
        queue: [
          _testSong(id: 1),
          _testSong(id: 2, title: 'Song 2'),
        ],
      );

      await tester.pumpWidget(_wrap(const FullPlayerScreen(), player: player));
      await tester.pumpAndSettle();

      // Tap the play button (now in a circular container)
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      expect(player.togglePlayCount, 1);
    });

    testWidgets('tapping next triggers next()', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final player = _TestablePlayer(
        initial: PlayerSnapshot(
          status: PlayerStatus.ready,
          isPlaying: true,
          repeatMode: RepeatMode.off,
          shuffleEnabled: false,
          queueLength: 3,
          currentIndex: 0,
          durationMs: 200000,
          current: _testSong(),
        ),
        queue: [_testSong(id: 1), _testSong(id: 2), _testSong(id: 3)],
      );

      await tester.pumpWidget(_wrap(const FullPlayerScreen(), player: player));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      expect(player.nextCount, 1);
    });

    testWidgets('tapping previous triggers previous()', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final player = _TestablePlayer(
        initial: PlayerSnapshot(
          status: PlayerStatus.ready,
          isPlaying: true,
          repeatMode: RepeatMode.off,
          shuffleEnabled: false,
          queueLength: 3,
          currentIndex: 1,
          durationMs: 200000,
          current: _testSong(),
        ),
        queue: [_testSong(id: 1), _testSong(id: 2), _testSong(id: 3)],
      );

      await tester.pumpWidget(_wrap(const FullPlayerScreen(), player: player));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.skip_previous_rounded));
      expect(player.previousCount, 1);
    });

    testWidgets('rewind-10 button calls seekBy(-10s)', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final player = _TestablePlayer(
        initial: PlayerSnapshot(
          status: PlayerStatus.ready,
          isPlaying: true,
          repeatMode: RepeatMode.off,
          shuffleEnabled: false,
          queueLength: 3,
          currentIndex: 1,
          durationMs: 200000,
          current: _testSong(),
        ),
        queue: [_testSong(id: 1), _testSong(id: 2), _testSong(id: 3)],
      );

      await tester.pumpWidget(_wrap(const FullPlayerScreen(), player: player));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.replay_10_rounded));
      expect(player.seekByEvents, [const Duration(seconds: -10)]);
    });

    testWidgets('forward-10 button calls seekBy(+10s)', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final player = _TestablePlayer(
        initial: PlayerSnapshot(
          status: PlayerStatus.ready,
          isPlaying: true,
          repeatMode: RepeatMode.off,
          shuffleEnabled: false,
          queueLength: 3,
          currentIndex: 1,
          durationMs: 200000,
          current: _testSong(),
        ),
        queue: [_testSong(id: 1), _testSong(id: 2), _testSong(id: 3)],
      );

      await tester.pumpWidget(_wrap(const FullPlayerScreen(), player: player));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.forward_10_rounded));
      expect(player.seekByEvents, [const Duration(seconds: 10)]);
    });

    testWidgets('repeated rapid rewind/forward taps queue seekBy calls', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final player = _TestablePlayer(
        initial: PlayerSnapshot(
          status: PlayerStatus.ready,
          isPlaying: true,
          repeatMode: RepeatMode.off,
          shuffleEnabled: false,
          queueLength: 3,
          currentIndex: 1,
          durationMs: 200000,
          current: _testSong(),
        ),
        queue: [_testSong(id: 1), _testSong(id: 2), _testSong(id: 3)],
      );

      await tester.pumpWidget(_wrap(const FullPlayerScreen(), player: player));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.forward_10_rounded));
      await tester.tap(find.byIcon(Icons.forward_10_rounded));
      await tester.tap(find.byIcon(Icons.replay_10_rounded));
      expect(player.seekByEvents, [
        const Duration(seconds: 10),
        const Duration(seconds: 10),
        const Duration(seconds: -10),
      ]);
    });

    testWidgets('shrink wrap: full player does not throw on small viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(const FullPlayerScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // FakePlayer currentQueue
  // -------------------------------------------------------------------------

  group('FakePlayer.currentQueue', () {
    test('returns a copy of the queue', () {
      final songs = [_testSong(id: 1), _testSong(id: 2)];
      final player = FakePlayerController(queue: songs);

      final q1 = player.currentQueue;
      final q2 = player.currentQueue;

      expect(q1, hasLength(2));
      // Each call returns a new list.
      expect(identical(q1, q2), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // 10-second seek clamping
  // -------------------------------------------------------------------------

  group('clampSeekBy', () {
    const duration = Duration(minutes: 4); // 240s

    test('clamps rewind below zero to zero', () {
      expect(
        clampSeekBy(
          const Duration(seconds: 5),
          const Duration(seconds: -10),
          duration,
        ),
        Duration.zero,
      );
    });

    test('clamps forward beyond duration to duration', () {
      expect(
        clampSeekBy(
          const Duration(minutes: 3, seconds: 55),
          const Duration(seconds: 10),
          duration,
        ),
        duration,
      );
    });

    test('normal forward within range is position plus offset', () {
      expect(
        clampSeekBy(
          const Duration(minutes: 1),
          const Duration(seconds: 10),
          duration,
        ),
        const Duration(minutes: 1, seconds: 10),
      );
    });

    test('normal rewind within range is position minus offset', () {
      expect(
        clampSeekBy(
          const Duration(minutes: 2),
          const Duration(seconds: -10),
          duration,
        ),
        const Duration(minutes: 1, seconds: 50),
      );
    });

    test('handles unknown duration by only clamping below zero', () {
      expect(
        clampSeekBy(
          const Duration(seconds: 30),
          const Duration(seconds: 10),
          null,
        ),
        const Duration(seconds: 40),
      );
      expect(
        clampSeekBy(Duration.zero, const Duration(seconds: -5), null),
        Duration.zero,
      );
    });
  });
}

/// A FakePlayer that counts method calls for verification.
class _TestablePlayer extends FakePlayerController {
  _TestablePlayer({required super.initial, List<SongRef> queue = const []})
    : super(queue: queue);

  int togglePlayCount = 0;
  int nextCount = 0;
  int previousCount = 0;
  int shuffleCount = 0;
  int repeatCount = 0;
  final List<Duration> seekByEvents = [];

  @override
  Future<void> seekBy(Duration offset) async {
    seekByEvents.add(offset);
  }

  @override
  Future<void> togglePlay() async {
    togglePlayCount++;
  }

  @override
  Future<void> next() async {
    nextCount++;
  }

  @override
  Future<void> previous() async {
    previousCount++;
  }

  @override
  Future<void> setShuffle(bool enabled) async {
    shuffleCount++;
  }

  @override
  Future<void> setRepeat(RepeatMode mode) async {
    repeatCount++;
  }
}

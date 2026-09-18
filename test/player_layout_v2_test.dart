import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/core/ui_customization/ui_component_registry.dart';
import 'package:vora_tube/core/ui_customization/ui_layout.dart';
import 'package:vora_tube/core/ui_customization/ui_layout_normalizer.dart';
import 'package:vora_tube/features/customization/data/layout_repository.dart';
import 'package:vora_tube/features/customization/presentation/providers/layout_providers.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/player/presentation/screens/full_player_screen.dart';
import 'package:vora_tube/features/player/presentation/widgets/mini_player.dart';
import 'package:vora_tube/features/player/presentation/widgets/player_palette_surface.dart';
import 'package:vora_tube/features/player/presentation/widgets/player_progress.dart';
import 'package:vora_tube/features/player/presentation/widgets/player_track_info.dart';
import 'package:vora_tube/features/player/presentation/widgets/rotating_artwork.dart';

import 'fakes/fake_player.dart';

SongRef _testSong({int id = 1, String title = 'Test Song'}) {
  return SongRef(
    identityKey: 'ms:$id',
    uri: 'content://media/external/audio/media/$id',
    title: title,
    artist: 'Test Artist',
    album: 'Test Album',
    durationMs: 200000,
  );
}

FakePlayerController _playerWithTrack() {
  return FakePlayerController(
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
}

/// In-memory KV backing the real [KvLayoutRepository], matching the pattern in
/// `customize_home_screen_test.dart`.
class _MemoryStore implements LayoutKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// The standard layout for every screen variant, so a seeded profile survives
/// normalization untouched.
Map<LayoutKey, ScreenLayout> _standardScreenLayouts() {
  return {
    for (final screenId in kLayoutScreenIds)
      for (final variant in LayoutVariant.values)
        LayoutKey(screenId, variant): applyLayoutPreset(
          LayoutPreset.standard,
          screenId,
          layoutSceneRegistries[screenId]!,
        ),
  };
}

/// Builds a full profile with optional per-screen mutations applied to every
/// variant of one screen.
LayoutProfile _profile({
  ScreenLayout Function(ScreenLayout layout)? player,
  ScreenLayout Function(ScreenLayout layout)? mini,
}) {
  final layouts = _standardScreenLayouts();
  if (player != null) {
    for (final variant in LayoutVariant.values) {
      final key = LayoutKey(kPlayerScreenId, variant);
      layouts[key] = player(layouts[key]!);
    }
  }
  if (mini != null) {
    for (final variant in LayoutVariant.values) {
      final key = LayoutKey(kMiniScreenId, variant);
      layouts[key] = mini(layouts[key]!);
    }
  }
  return LayoutProfile(layouts: layouts);
}

void main() {
  late AppDatabase db;
  late LibraryRepository repository;

  setUpAll(() {
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

  ProviderScope _wrap({
    required Widget child,
    FakePlayerController? player,
    LayoutProfile? profile,
  }) {
    final overrides = <Override>[
      appDatabaseProvider.overrideWithValue(db),
      libraryRepositoryProvider.overrideWithValue(repository),
      playerProvider.overrideWithValue(player ?? _playerWithTrack()),
    ];
    if (profile != null) {
      final store = _MemoryStore();
      store.values[KvLayoutRepository.storageKey] = profile.encode();
      overrides.add(
        layoutRepositoryProvider.overrideWithValue(KvLayoutRepository(store)),
      );
    }
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: child),
    );
  }

  void _useLandscape(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  void _usePortrait(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('FullPlayerScreen V2 layout', () {
    testWidgets('wraps the player content in the artwork palette surface', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(child: const FullPlayerScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPaletteSurface), findsOneWidget);
    });

    testWidgets('renders every default block exactly once', (tester) async {
      await tester.pumpWidget(_wrap(child: const FullPlayerScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(RotatingArtwork), findsOneWidget);
      expect(find.byType(PlayerTrackInfo), findsOneWidget);
      expect(find.byKey(const Key('player_progress_wave')), findsOneWidget);

      // Secondary (player.secondaryControls).
      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
      // Primary (player.primaryControls).
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
      // Quick actions live only in the top bar: favorite and queue, once each.
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.queue_music_rounded), findsOneWidget);
      // The lyrics toggle lives only in the top bar: exactly one instance.
      expect(find.byIcon(Icons.lyrics_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('short landscape keeps every control reachable, no overflow', (
      tester,
    ) async {
      _useLandscape(tester, const Size(780, 350));

      await tester.pumpWidget(_wrap(child: const FullPlayerScreen()));
      await tester.pumpAndSettle();

      // No row is suppressed on short viewports: shuffle/repeat, the transport,
      // the seek bar work, and the quick actions stay in the top bar.
      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
      expect(find.byKey(const Key('player_progress_wave')), findsOneWidget);
      expect(find.byType(RotatingArtwork), findsOneWidget);
      expect(find.byType(PlayerTrackInfo), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.queue_music_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('normal landscape keeps every control reachable', (
      tester,
    ) async {
      _useLandscape(tester, const Size(1280, 720));

      await tester.pumpWidget(_wrap(child: const FullPlayerScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
      expect(find.byKey(const Key('player_progress_wave')), findsOneWidget);
      expect(find.byType(RotatingArtwork), findsOneWidget);
      expect(find.byType(PlayerTrackInfo), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.queue_music_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide landscape keeps every control reachable', (tester) async {
      _useLandscape(tester, const Size(2000, 800));

      await tester.pumpWidget(_wrap(child: const FullPlayerScreen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
      expect(find.byKey(const Key('player_progress_wave')), findsOneWidget);
      expect(find.byType(RotatingArtwork), findsOneWidget);
      expect(find.byType(PlayerTrackInfo), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.queue_music_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a narrow bar keeps favorite/queue direct and defers the rest '
        'to the overflow menu', (tester) async {
      _usePortrait(tester, const Size(240, 520));

      await tester.pumpWidget(_wrap(child: const FullPlayerScreen()));
      await tester.pumpAndSettle();

      // Two top-bar slots: favorite + queue stay one tap away…
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.queue_music_rounded), findsOneWidget);
      // …while lyrics and the sleep timer fold into the overflow menu.
      expect(find.byIcon(Icons.lyrics_rounded), findsNothing);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Lyrics'), findsOneWidget);
      expect(find.text('Sleep timer'), findsOneWidget);
      expect(find.text('Queue'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides playback modes when the profile hides the block', (
      tester,
    ) async {
      final profile = _profile(
        player: (layout) {
          final secondary = layout.component('player.secondaryControls')!;
          return layout.replaceComponent(secondary.copyWith(visible: false));
        },
      );

      await tester.pumpWidget(
        _wrap(child: const FullPlayerScreen(), profile: profile),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.shuffle_rounded), findsNothing);
      expect(find.byIcon(Icons.repeat_rounded), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.queue_music_rounded), findsOneWidget);
    });

    testWidgets('an immersive artwork style renders the palette surface', (
      tester,
    ) async {
      final profile = _profile(
        player: (layout) {
          final art = layout.component('player.artwork')!;
          return layout.replaceComponent(
            art.copyWith(styleId: 'immersive', size: ComponentSize.large),
          );
        },
      );

      await tester.pumpWidget(
        _wrap(child: const FullPlayerScreen(), profile: profile),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPaletteSurface), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });
  });

  group('MiniPlayer V2 layout', () {
    testWidgets('hides song info when the profile hides mini.trackInfo', (
      tester,
    ) async {
      final profile = _profile(
        player: (layout) => layout,
        mini: (layout) {
          final info = layout.component('mini.trackInfo')!;
          return layout.replaceComponent(info.copyWith(visible: false));
        },
      );

      await tester.pumpWidget(
        _wrap(child: const MiniPlayer(), profile: profile),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test Song'), findsNothing);
      expect(find.text('Test Artist'), findsNothing);
      // The bar itself and its controls stay put.
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    });

    testWidgets('hides shuffle when the profile hides mini.secondaryControls', (
      tester,
    ) async {
      final profile = _profile(
        player: (layout) => layout,
        mini: (layout) {
          final secondary = layout.component('mini.secondaryControls')!;
          return layout.replaceComponent(secondary.copyWith(visible: false));
        },
      );

      await tester.pumpWidget(
        _wrap(child: const MiniPlayer(), profile: profile),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.shuffle_rounded), findsNothing);
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    });

    testWidgets('a bold progress style thickens the line', (tester) async {
      final profile = _profile(
        player: (layout) => layout,
        mini: (layout) {
          final progress = layout.component('mini.progress')!;
          return layout.replaceComponent(progress.copyWith(styleId: 'bold'));
        },
      );

      await tester.pumpWidget(
        _wrap(child: const MiniPlayer(), profile: profile),
      );
      await tester.pumpAndSettle();

      final heights = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byKey(const Key('mini_progress')),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.constraints?.maxHeight)
          .whereType<double>()
          .toList();
      expect(heights, contains(4.0));
      expect(heights, isNot(contains(2.0)));
    });

    testWidgets('the default thin progress style stays 2px', (tester) async {
      await tester.pumpWidget(_wrap(child: const MiniPlayer()));
      await tester.pumpAndSettle();

      final heights = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byKey(const Key('mini_progress')),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.constraints?.maxHeight)
          .whereType<double>()
          .toList();
      expect(heights, contains(2.0));
    });
  });

  group('groupPlayerZones', () {
    test('sorts player components into anchored top and bottom zones', () {
      final layout = applyLayoutPreset(
        LayoutPreset.standard,
        kPlayerScreenId,
        playerComponentRegistry,
      );
      final grouped = groupPlayerZones(layout.components);

      final ids = [for (final c in grouped) c.id];
      expect(
        ids,
        kPlayerTopZoneIds +
            <String>[
              'player.progress',
              'player.secondaryControls',
              'player.primaryControls',
            ],
      );
      expect(grouped, hasLength(layout.components.length));
      // Every component survives the grouping exactly once.
      expect(ids.toSet(), layout.components.map((c) => c.id).toSet());
    });
  });

  group('player quick actions', () {
    test('player.quickActions was removed from the registry and defaults', () {
      expect(playerComponentRegistry.contains('player.quickActions'), isFalse);
      final layout = applyLayoutPreset(
        LayoutPreset.standard,
        kPlayerScreenId,
        playerComponentRegistry,
      );
      expect(layout.component('player.quickActions'), isNull);
    });
  });
}

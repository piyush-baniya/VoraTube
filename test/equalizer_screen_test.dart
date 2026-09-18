import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/audio/audio_effects.dart';
import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/core/ui_customization/ui_component_registry.dart';
import 'package:vora_tube/core/ui_customization/ui_layout.dart';
import 'package:vora_tube/core/ui_customization/ui_layout_normalizer.dart';
import 'package:vora_tube/features/customization/data/layout_repository.dart';
import 'package:vora_tube/features/customization/presentation/providers/layout_providers.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/player/presentation/providers/equalizer_providers.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/player/presentation/screens/equalizer_screen.dart';
import 'package:vora_tube/features/player/presentation/screens/full_player_screen.dart';
import 'package:vora_tube/features/player/presentation/widgets/equalizer_curve.dart';
import 'package:vora_tube/features/settings/presentation/providers/settings_providers.dart';

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

FakePlayerController _playerWithTrack({String title = 'Test Song'}) {
  return FakePlayerController(
    initial: PlayerSnapshot(
      status: PlayerStatus.ready,
      isPlaying: false,
      repeatMode: RepeatMode.off,
      shuffleEnabled: false,
      queueLength: 1,
      currentIndex: 0,
      durationMs: 200000,
      current: _testSong(title: title),
    ),
    queue: [_testSong(title: title)],
  );
}

class _MemoryStore implements LayoutKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  late AppDatabase db;
  late LibraryRepository repository;

  setUpAll(() {
    disableBackgroundPulseForTesting();
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = LibraryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer _container({
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
    return ProviderContainer(overrides: overrides);
  }

  Future<void> _pump(
    WidgetTester tester,
    ProviderContainer container, {
    Size size = const Size(393, 852),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EqualizerScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  LayoutProfile _profileWith({
    bool hideCurve = false,
    bool hideQuick = false,
    bool hidePresets = false,
  }) {
    final layouts = <LayoutKey, ScreenLayout>{};
    for (final screenId in kLayoutScreenIds) {
      for (final variant in LayoutVariant.values) {
        layouts[LayoutKey(screenId, variant)] = defaultScreenLayout(
          screenId,
          layoutSceneRegistries[screenId]!,
        );
      }
    }
    for (final variant in LayoutVariant.values) {
      final key = LayoutKey(kEqualizerScreenId, variant);
      var layout = layouts[key]!;
      if (hideCurve) {
        final curve = layout.component('equalizer.curve')!;
        layout = layout.replaceComponent(curve.copyWith(visible: false));
      }
      if (hideQuick) {
        final quick = layout.component('equalizer.quickControls')!;
        layout = layout.replaceComponent(quick.copyWith(visible: false));
      }
      if (hidePresets) {
        final presets = layout.component('equalizer.presets')!;
        layout = layout.replaceComponent(presets.copyWith(visible: false));
      }
      layouts[key] = layout;
    }
    return LayoutProfile(layouts: layouts);
  }

  group('EqualizerScreen', () {
    testWidgets('renders the curve, now playing and Simple controls', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);

      await _pump(tester, container);

      expect(find.text('Equalizer'), findsOneWidget);
      expect(find.byType(EqualizerCurve), findsOneWidget);
      expect(find.text('Test Song'), findsOneWidget);
      expect(find.text('Quick controls'), findsOneWidget);
      expect(find.text('Sub Bass'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the ON/BYPASS toggle flips eqEnabled without losing values', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      await _pump(tester, container);

      expect(find.text('BYPASS'), findsOneWidget);
      final before = container.read(audioSettingsProvider).eqPreset;

      await tester.tap(find.text('BYPASS'));
      await tester.pumpAndSettle();

      expect(container.read(audioSettingsProvider).eqEnabled, true);
      expect(find.text('ON'), findsOneWidget);
      // Bypassing must preserve the selected curve.
      expect(container.read(audioSettingsProvider).eqPreset, before);
    });

    testWidgets('switching to Advanced swaps macros for band controls', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      await _pump(tester, container);

      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();

      expect(container.read(equalizerSettingsProvider).mode, EqMode.advanced);
      expect(find.text('Bands'), findsOneWidget);
      expect(find.text('Quick controls'), findsNothing);
    });

    testWidgets('picking a built-in preset updates the applied curve', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      await _pump(tester, container);

      await tester.tap(find.text('Rock'));
      await tester.pumpAndSettle();

      expect(container.read(audioSettingsProvider).eqPreset, EqPreset.rock);
    });

    testWidgets('warns about clipping when a boosted curve runs at full gain', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      await container.read(audioSettingsProvider.notifier).setEqEnabled(true);
      await container
          .read(audioSettingsProvider.notifier)
          .setEqPreset(EqPreset.rock);
      await _pump(tester, container);

      expect(find.text('Potential clipping'), findsOneWidget);
      expect(find.textContaining('Apply -'), findsOneWidget);
    });

    testWidgets('Reset returns the applied curve to flat', (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await container
          .read(audioSettingsProvider.notifier)
          .setEqPreset(EqPreset.rock);
      await _pump(tester, container);

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      final audio = container.read(audioSettingsProvider);
      expect(audio.eqPreset, EqPreset.flat);
      expect(audio.eqCustomLevels, List.filled(eqVirtualBandCount, 0.0));
    });

    testWidgets('saved curves appear and apply on tap', (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      final saved = container
          .read(equalizerSettingsProvider.notifier)
          .savePreset('Late night', const [3, 2, 1, 0, -1, -2, -3, 4, 5, 6])!;
      await _pump(tester, container);

      expect(find.text('Late night'), findsOneWidget);
      await tester.tap(find.text('Late night'));
      await tester.pumpAndSettle();

      final audio = container.read(audioSettingsProvider);
      expect(audio.eqPreset, EqPreset.custom);
      expect(audio.eqCustomLevels, saved.levels);
    });

    testWidgets('the protected curve survives a layout that hides it', (
      tester,
    ) async {
      final container = _container(
        profile: _profileWith(hideCurve: true, hideQuick: true),
      );
      addTearDown(container.dispose);

      await _pump(tester, container);

      expect(find.byType(EqualizerCurve), findsOneWidget);
      expect(find.text('Quick controls'), findsNothing);
    });

    testWidgets('hiding presets removes them from the screen', (tester) async {
      final container = _container(profile: _profileWith(hidePresets: true));
      addTearDown(container.dispose);

      await _pump(tester, container);

      expect(find.text('Presets'), findsNothing);
      expect(find.byType(EqualizerCurve), findsOneWidget);
    });

    testWidgets('landscape renders the two-pane layout without overflow', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);

      await _pump(tester, container, size: const Size(820, 420));

      expect(find.byType(EqualizerCurve), findsOneWidget);
      expect(find.text('Quick controls'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a very long track title ellipsizes instead of overflowing', (
      tester,
    ) async {
      final container = _container(
        player: _playerWithTrack(
          title:
              'An Extremely Long Song Title That Would Surely Overflow '
              'Every Reasonable Width On A Small Phone Screen',
        ),
      );
      addTearDown(container.dispose);

      await _pump(tester, container);

      expect(tester.takeException(), isNull);
      expect(find.byType(EqualizerCurve), findsOneWidget);
    });
  });
}

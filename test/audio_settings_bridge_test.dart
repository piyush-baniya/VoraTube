import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/audio/audio_effects.dart';
import 'package:vora_tube/core/audio/parametric_eq.dart';
import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/settings/data/settings_models.dart';
import 'package:vora_tube/features/settings/presentation/providers/settings_providers.dart';

/// Records ReplayGain/preamp calls so a test can assert the bridge forwarded
/// the persisted audio settings to the player.
class SpyPlayerController implements PlayerController {
  SpyPlayerController({PlayerSnapshot? initial})
    : current = initial ?? PlayerSnapshot.initial;

  @override
  PlayerSnapshot current;

  final List<(ReplayGainMode mode, double preampDb)> replayGainCalls = [];

  @override
  Future<void> setReplayGainMode(
    ReplayGainMode mode, {
    double preampDb = 0,
  }) async {
    replayGainCalls.add((mode, preampDb));
  }

  double? lastSpeed;
  ({bool enabled, EqPreset preset, List<double> levels})? lastEq;
  ({PlaybackTransitionMode mode, int seconds})? lastTransition;
  double? lastBalance;

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    lastSpeed = speed;
  }

  @override
  Future<void> setEqualizer({
    required bool enabled,
    required EqPreset preset,
    required List<double> customLevels,
  }) async {
    lastEq = (enabled: enabled, preset: preset, levels: customLevels);
  }

  ({bool enabled, List<ParametricEqBand> bands})? lastParametricEq;

  @override
  Future<void> setParametricEq({
    required bool enabled,
    required List<ParametricEqBand> bands,
  }) async {
    lastParametricEq = (enabled: enabled, bands: bands);
  }

  @override
  Future<void> setTransitionMode(
    PlaybackTransitionMode mode, {
    int crossfadeSeconds = kDefaultCrossfadeSeconds,
  }) async {
    lastTransition = (mode: mode, seconds: crossfadeSeconds);
  }

  @override
  Future<void> setAudioBalance(double balance) async {
    lastBalance = balance;
  }

  // --- Unused below, but required by the interface ---
  @override
  List<SongRef> get currentQueue => const [];
  @override
  Stream<PlayerSnapshot> get snapshot => Stream.value(current);
  @override
  Stream<Duration> get positions => Stream.value(Duration.zero);
  @override
  Future<void> playQueue(List<SongRef> songs, {int startIndex = 0}) async {}
  @override
  Future<void> togglePlay() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> clearSession() async {}
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
  Future<void> removeByIdentityKeys(Set<String> identityKeys) async {}
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
  ReplayGainMode get replayGainMode =>
      replayGainCalls.isEmpty ? ReplayGainMode.off : replayGainCalls.last.$1;
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> dispose() async {}
}

/// A controller that skips the KV persistence layer so tests can drive state
/// without persisting. State changes still notify listeners exactly like the
/// real controller, which is what the bridge reacts to. An empty in-memory
/// database gives it a real [LibraryRepository] so the `_load()` read returns
/// null (the default state).
class _TestAudioSettingsController extends AudioSettingsController {
  _TestAudioSettingsController()
    : super(LibraryRepository(AppDatabase(NativeDatabase.memory())));

  @override
  Future<void> setReplayGain(ReplayGainPreference mode) async {
    state = state.copyWith(replayGain: mode);
  }

  @override
  Future<void> setPreampDb(double v) async {
    state = state.copyWith(preampDb: v.clamp(-12.0, 12.0));
  }

  @override
  Future<void> setEqEnabled(bool v) async {
    state = state.copyWith(eqEnabled: v);
  }

  @override
  Future<void> setEqMode(EqEngineMode v) async {
    state = state.copyWith(eqMode: v);
  }

  @override
  Future<void> setParametricBands(List<ParametricEqBand> v) async {
    state = state.copyWith(parametricBands: v);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('audioSettingsBridgeProvider', () {
    test('pushes stored settings to the player on startup', () {
      final spy = SpyPlayerController();
      final container = ProviderContainer(
        overrides: [
          playerProvider.overrideWithValue(spy),
          audioSettingsProvider.overrideWith(
            (ref) => _TestAudioSettingsController(),
          ),
        ],
      );

      addTearDown(container.dispose);

      // Reading the bridge provider activates it.
      container.read(audioSettingsBridgeProvider);

      expect(spy.replayGainCalls, hasLength(1));
      expect(spy.replayGainCalls.first.$1, ReplayGainMode.off);
      expect(spy.replayGainCalls.first.$2, 0.0);
    });

    test('forwards settings changes to the player', () {
      final spy = SpyPlayerController();
      final container = ProviderContainer(
        overrides: [
          playerProvider.overrideWithValue(spy),
          audioSettingsProvider.overrideWith(
            (ref) => _TestAudioSettingsController(),
          ),
        ],
      );

      addTearDown(container.dispose);

      container.read(audioSettingsBridgeProvider);
      expect(spy.replayGainCalls, hasLength(1));

      // Simulate the user changing ReplayGain + Preamp in Settings.
      container
          .read(audioSettingsProvider.notifier)
          .setReplayGain(ReplayGainPreference.album);
      container.read(audioSettingsProvider.notifier).setPreampDb(-2.0);

      expect(spy.replayGainCalls, hasLength(3));
      expect(spy.replayGainCalls[1].$1, ReplayGainMode.album);
      expect(spy.replayGainCalls[2].$2, -2.0);
    });
  });

  group('parametric engine selection', () {
    ProviderContainer _container(SpyPlayerController spy) {
      final container = ProviderContainer(
        overrides: [
          playerProvider.overrideWithValue(spy),
          audioSettingsProvider.overrideWith(
            (ref) => _TestAudioSettingsController(),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(audioSettingsBridgeProvider);
      return container;
    }

    test('both engines start bypassed when the EQ is disabled', () {
      final spy = SpyPlayerController();
      _container(spy);
      expect(spy.lastEq!.enabled, false);
      expect(spy.lastParametricEq!.enabled, false);
    });

    test('graphic mode enables only the graphic engine', () {
      final spy = SpyPlayerController();
      final container = _container(spy);
      final notifier = container.read(audioSettingsProvider.notifier);
      notifier.setEqEnabled(true);

      expect(spy.lastEq!.enabled, true);
      expect(spy.lastParametricEq!.enabled, false);
    });

    test('parametric mode enables only the parametric engine', () {
      final spy = SpyPlayerController();
      final container = _container(spy);
      final notifier = container.read(audioSettingsProvider.notifier);
      notifier.setEqEnabled(true);
      notifier.setEqMode(EqEngineMode.parametric);

      expect(spy.lastEq!.enabled, false);
      expect(spy.lastParametricEq!.enabled, true);
    });

    test('switching engines never leaves both active', () {
      final spy = SpyPlayerController();
      final container = _container(spy);
      final notifier = container.read(audioSettingsProvider.notifier);
      notifier.setEqEnabled(true);
      notifier.setEqMode(EqEngineMode.parametric);
      notifier.setEqMode(EqEngineMode.graphic);

      expect(spy.lastEq!.enabled, true);
      expect(spy.lastParametricEq!.enabled, false);
    });

    test('the parametric band stack is forwarded to the player', () {
      final spy = SpyPlayerController();
      final container = _container(spy);
      final notifier = container.read(audioSettingsProvider.notifier);
      notifier.setEqEnabled(true);
      notifier.setEqMode(EqEngineMode.parametric);
      notifier.setParametricBands([
        ParametricEqBand(id: 'a', frequencyHz: 250, gainDb: 3),
      ]);

      expect(spy.lastParametricEq!.bands, hasLength(1));
      expect(spy.lastParametricEq!.bands.single.frequencyHz, 250);
      expect(spy.lastParametricEq!.bands.single.gainDb, 3);
      expect(spy.lastEq!.enabled, false);
    });
  });
}

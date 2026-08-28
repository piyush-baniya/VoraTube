import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/player/player_controller.dart';
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
  ReplayGainMode get replayGainMode =>
      replayGainCalls.isEmpty ? ReplayGainMode.off : replayGainCalls.last.$1;
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setVolumeBoost(double multiplier) async {}
  @override
  Future<void> dispose() async {}
}

/// A controller that skips the KV persistence layer so tests can drive state
/// without a database. State changes still notify listeners exactly like the
/// real controller, which is what the bridge reacts to.
class _TestAudioSettingsController extends AudioSettingsController {
  _TestAudioSettingsController() : super(_NullRepo());

  @override
  Future<void> setReplayGain(ReplayGainPreference mode) async {
    state = state.copyWith(replayGain: mode);
  }

  @override
  Future<void> setPreampDb(double v) async {
    state = state.copyWith(preampDb: v.clamp(-12.0, 12.0));
  }
}

class _NullRepo {
  Future<String?> kvGet(String key) async => null;
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
}

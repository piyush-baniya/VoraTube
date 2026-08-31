import 'dart:async';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/db/app_database.dart';
import 'core/player/just_audio_controller.dart';
import 'features/ads/ads_initializer.dart';
import 'features/ads/premium_models.dart';
import 'features/library/data/library_repository.dart';
import 'features/library/presentation/providers/library_providers.dart';
import 'features/library/presentation/providers/library_view_providers.dart';
import 'features/player/presentation/providers/player_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase(driftDatabase(name: 'voratube'));
  final repository = LibraryRepository(db);

  // Wired after the container exists so a flush can bump the stats refresh
  // tick that statistics-facing providers watch (main.dart cannot reference
  // the container before it is created, so the callback is late-bound).
  var notifyStatsChanged = () {};
  final statsBuffer = PlaybackStatsBuffer(
    repository,
    onFlushed: () => notifyStatsChanged(),
  );

  final player = await JustAudioController.create(
    persistence: DriftPlayerPersistence(repository),
    resolveSongs: repository.resolveSongsByIdentityKeys,
    onTrackStarted: statsBuffer.add,
  );

  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      libraryRepositoryProvider.overrideWithValue(repository),
      playerProvider.overrideWithValue(player),
    ],
  );

  // Every committed stats write re-queries the listening strip, statistics
  // screen and collection counts/lists. This never resets the paged browsing
  // lists, which watch the library tick instead.
  notifyStatsChanged = () {
    container.read(statsRefreshTickProvider.notifier).state++;
  };

  // Initialize the Mobile Ads SDK without blocking startup. If Premium is
  // already active, the persisted entitlement is read first so no ad request
  // is made unnecessarily. Failures here are non-fatal.
  unawaited(() async {
    var premiumActive = false;
    try {
      premiumActive =
          (await repository.kvGet(PremiumKeys.activated)) == 'true';
    } catch (_) {
      premiumActive = false;
    }
    await AdsInitializer.initialize(premiumActive: premiumActive);
  }());

  // ProviderScope → VoraTubeApp → MaterialApp → splash → permission gate →
  // HomeShell. Keeping the SplashGate/PermissionGate inside the MaterialApp
  // (as its `home`) guarantees every widget that renders a Scaffold or reads
  // Theme/Directionality/MediaQuery has those inherited ancestors, which is
  // required to avoid a "No Directionality widget found" startup crash.
  // The flutter image cache defaults to 1000 images / 100 MB. A music library
  // easily has more than 1000 distinct covers, so fast scrolling through All
  // Songs / Library used to evict live entries and re-decode them on the way
  // back — visible hitching on every revisited screen. Decode memory per entry
  // is already bounded by ArtworkFileCache.decodeWidth (small tiles decode at
  // ~100-150 device px), so raising the entry cap costs a few MB at most and
  // keeps the whole visible library resident.
  PaintingBinding.instance.imageCache
    ..maximumSize = 8192
    ..maximumSizeBytes = 128 << 20;

  runApp(
    UncontrolledProviderScope(container: container, child: const VoraTubeApp()),
  );
}

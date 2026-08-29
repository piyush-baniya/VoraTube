import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/db/app_database.dart';
import 'core/player/just_audio_controller.dart';
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

  // ProviderScope → VoraTubeApp → MaterialApp → splash → permission gate →
  // HomeShell. Keeping the SplashGate/PermissionGate inside the MaterialApp
  // (as its `home`) guarantees every widget that renders a Scaffold or reads
  // Theme/Directionality/MediaQuery has those inherited ancestors, which is
  // required to avoid a "No Directionality widget found" startup crash.
  runApp(
    UncontrolledProviderScope(container: container, child: const VoraTubeApp()),
  );
}

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/db/app_database.dart';
import 'core/player/just_audio_controller.dart';
import 'features/library/data/library_repository.dart';
import 'features/library/presentation/providers/library_providers.dart';
import 'features/player/presentation/providers/player_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase(driftDatabase(name: 'voratube'));
  final repository = LibraryRepository(db);

  final statsBuffer = PlaybackStatsBuffer(repository);

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

  // ProviderScope → VoraTubeApp → MaterialApp → splash → permission gate →
  // HomeShell. Keeping the SplashGate/PermissionGate inside the MaterialApp
  // (as its `home`) guarantees every widget that renders a Scaffold or reads
  // Theme/Directionality/MediaQuery has those inherited ancestors, which is
  // required to avoid a "No Directionality widget found" startup crash.
  runApp(
    UncontrolledProviderScope(container: container, child: const VoraTubeApp()),
  );
}

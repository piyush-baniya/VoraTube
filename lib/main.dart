import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/db/app_database.dart';
import 'core/permissions/permission_gate.dart';
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

  runApp(
    UncontrolledProviderScope(
      container: container,
      // The permission gate requests audio access on first launch (Android)
      // before revealing the app. See [PermissionGate] for the platform rules.
      child: const PermissionGate(child: VoraTubeApp()),
    ),
  );
}

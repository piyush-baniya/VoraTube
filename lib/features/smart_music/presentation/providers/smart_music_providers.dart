import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/library/data/library_models.dart';
import '../../../../features/library/presentation/providers/library_providers.dart';
import '../../../../features/library/presentation/providers/library_view_providers.dart';
import '../../data/mood_engine.dart';
import '../../data/smart_mix_service.dart';
import '../../data/smart_playlist_service.dart';
import '../../data/smart_queue_service.dart';

final moodEngineProvider = Provider<MoodEngine>((ref) {
  return MoodEngine();
});

final smartMixServiceProvider = Provider<SmartMixService>((ref) {
  final repository = ref.watch(libraryRepositoryProvider);
  final moodEngine = ref.watch(moodEngineProvider);
  return SmartMixService(repository: repository, moodEngine: moodEngine);
});

final smartPlaylistServiceProvider = Provider<SmartPlaylistService>((ref) {
  final repository = ref.watch(libraryRepositoryProvider);
  final moodEngine = ref.watch(moodEngineProvider);
  return SmartPlaylistService(repository: repository, moodEngine: moodEngine);
});

final smartQueueServiceProvider = Provider<SmartQueueService>((ref) {
  final moodEngine = ref.watch(moodEngineProvider);
  return SmartQueueService(moodEngine: moodEngine);
});

final smartMixesProvider = FutureProvider.autoDispose<List<SmartMix>>((
  ref,
) async {
  // Rebuilds when a scan/import, metadata edit, genre enrichment or explicit
  // mood assignment changes the library. Without this, Smart Mood kept showing
  // the previous library state after the user made a change.
  ref.watch(libraryRefreshTickProvider);
  final service = ref.watch(smartMixServiceProvider);
  final mixes = await service.generateAllMixes(limit: 30);
  return mixes;
});

final smartMixProvider = FutureProvider.autoDispose
    .family<SmartMix, SmartMixKind>((ref, kind) async {
      ref.watch(libraryRefreshTickProvider);
      final service = ref.watch(smartMixServiceProvider);
      return service.generateMix(kind, limit: 30);
    });

final smartPlaylistTemplatesProvider = Provider<List<SmartPlaylistTemplate>>((
  ref,
) {
  final service = ref.watch(smartPlaylistServiceProvider);
  return service.getAllTemplates();
});

final smartPlaylistProvider = FutureProvider.autoDispose
    .family<List<SongTileData>, String>((ref, templateId) async {
      final service = ref.watch(smartPlaylistServiceProvider);
      return service.generateFromTemplate(templateId, limit: 50);
    });

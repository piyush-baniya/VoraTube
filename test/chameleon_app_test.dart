import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/app/app.dart';
import 'package:vora_tube/app/theme/app_theme.dart';
import 'package:vora_tube/app/theme/chameleon_theme.dart';
import 'package:vora_tube/app/widgets/glass_nav_bar.dart';
import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/core/ingest/ingest_service.dart';
import 'package:vora_tube/core/permissions/permission_service.dart';
import 'package:vora_tube/core/player/player_controller.dart';
import 'package:vora_tube/features/ads/premium_providers.dart';
import 'package:vora_tube/core/artwork_palette/artwork_palette.dart';
import 'package:vora_tube/core/artwork_palette/artwork_palette_cache.dart';
import 'package:vora_tube/core/artwork_palette/artwork_palette_service.dart';
import 'package:vora_tube/features/player/presentation/providers/artwork_palette_provider.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';
import 'package:vora_tube/features/library/presentation/providers/library_providers.dart';
import 'package:vora_tube/features/player/presentation/providers/player_providers.dart';
import 'package:vora_tube/features/settings/data/settings_models.dart';
import 'package:vora_tube/features/settings/presentation/providers/settings_providers.dart';
import 'package:vora_tube/features/settings/presentation/screens/settings_screen.dart';

import 'fakes/fake_player.dart';

/// Palette service whose resolution is scripted so every extraction resolves
/// deterministically, in any order the test wants (race coverage).
class _ScriptedService extends ArtworkPaletteService {
  _ScriptedService() : super(cache: ArtworkPaletteCache());

  int _gen = 0;
  final List<String> requested = [];
  final List<Completer<ArtworkPalette?>> pending = [];

  @override
  int get generation => _gen;

  @override
  bool isCurrent(int token) => token == _gen;

  @override
  void cancelPending() {
    _gen++;
  }

  @override
  Future<ArtworkPaletteResult?> resolve({
    required ArtworkDescriptor descriptor,
  }) async {
    final token = ++_gen;
    requested.add(descriptor.songIdentityKey);
    final completer = Completer<ArtworkPalette?>();
    pending.add(completer);
    final palette = await completer.future;
    if (palette == null) return null;
    return ArtworkPaletteResult(
      palette: palette,
      generation: token,
      fromCache: false,
    );
  }
}

ArtworkPalette _palette(Color surface, Color accent, String key) {
  return ArtworkPalette(
    dominant: surface,
    vibrant: accent,
    muted: surface,
    dark: surface,
    darkMuted: surface,
    light: surface,
    lightVibrant: surface,
    surface: surface,
    surfaceVariant: surface,
    accent: accent,
    secondaryAccent: accent,
    onSurface: const Color(0xFF000000),
    onAccent: const Color(0xFFFFFFFF),
    backgroundStart: surface,
    backgroundEnd: surface,
    sourceArtworkKey: key,
    extractionVersion: paletteAlgorithmVersion,
    wasFallback: false,
  );
}

// Distinct dark art covers so every identity resolves to dark themes with
// different surfaces/accents.
final _navy = _palette(
  const Color(0xFF16213E),
  const Color(0xFF3B82F6),
  'navy',
);
final _emerald = _palette(
  const Color(0xFF0F2A22),
  const Color(0xFF10B981),
  'emerald',
);
final _amber = _palette(
  const Color(0xFF2A2015),
  const Color(0xFFF59E0B),
  'amber',
);

SongRef _song(String id, String artPath) => SongRef(
  identityKey: id,
  uri: 'file:///tmp/$id.mp3',
  title: 'Track $id',
  artPath: artPath,
);

class _GrantedPermissionService extends PermissionService {
  const _GrantedPermissionService();

  @override
  Future<MediaPermissionStatus> audioStatus() async =>
      MediaPermissionStatus.granted;

  @override
  Future<MediaPermissionStatus> requestAudio() async =>
      MediaPermissionStatus.granted;
}

class _FakeIngestService implements IngestService {
  const _FakeIngestService();

  @override
  IngestCapabilities get capabilities =>
      const IngestCapabilities({IngestCapability.scan});

  @override
  Future<void> prepareScan() async {}

  @override
  Future<List<IngestTrack>> getAudioBatch({
    required int afterId,
    required int limit,
  }) async => [];

  @override
  Future<Map<String, ResolvedArtwork?>> resolveArtwork(
    List<ArtworkTarget> targets,
  ) async => {};

  @override
  Future<List<PickedImportFile>> pickImportFiles() async => [];

  @override
  Future<ProcessedImport> processImportFile(PickedImportFile file) async =>
      throw UnsupportedError('Not supported in test');

  @override
  Future<Directory?> importedFilesRoot() async => null;
}

late FakePlayerController _player;
late _ScriptedService _artwork;

Future<ProviderContainer> _buildApp(WidgetTester tester) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final repo = LibraryRepository(db);
  _player = FakePlayerController();
  _artwork = _ScriptedService();

  final scope = ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      libraryRepositoryProvider.overrideWithValue(repo),
      playerProvider.overrideWithValue(_player),
      ingestServiceProvider.overrideWithValue(const _FakeIngestService()),
      permissionServiceProvider.overrideWithValue(
        const _GrantedPermissionService(),
      ),
      isPremiumProvider.overrideWithValue(true),
      storageInfoProvider.overrideWith(
        (ref) => const StorageInfo(
          databaseSizeBytes: 0,
          artworkCacheSizeBytes: 0,
          importedMusicSizeBytes: 0,
          totalSizeBytes: 0,
        ),
      ),
      artworkPaletteServiceProvider.overrideWithValue(_artwork),
    ],
    child: const VoraTubeApp(),
  );

  final size = tester.view.physicalSize;
  final dpr = tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 2400);

  await tester.pumpWidget(scope);
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle(const Duration(seconds: 5));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  addTearDown(() {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = dpr;
  });

  return ProviderScope.containerOf(tester.element(find.byType(VoraTubeApp)));
}

Future<void> _enableChameleon(ProviderContainer container) async {
  await container
      .read(appearanceSettingsProvider.notifier)
      .setThemeMode(AppThemeMode.chameleon);
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle();
}

/// Pushes a fake playback snapshot so the artwork descriptor resolves, then
/// waits for the scripted extraction request to land (the snapshot travels
/// through the play stream → snapshot provider → descriptor → palette listener
/// before the service records the pending request).
Future<void> _play(WidgetTester tester, SongRef song) async {
  _player.pushSnapshot(
    PlayerSnapshot(
      status: PlayerStatus.ready,
      isPlaying: true,
      repeatMode: RepeatMode.off,
      shuffleEnabled: false,
      queueLength: 1,
      currentIndex: 0,
      durationMs: 30000,
      current: song,
    ),
  );
  for (var i = 0;
      i < 100 && !_artwork.requested.contains(song.identityKey);
      i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(
    _artwork.requested,
    contains(song.identityKey),
    reason: 'the artwork extraction should have started for ${song.identityKey}',
  );
}

ThemeData _homeTheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(GlassNavBar)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Settings: Chameleon disables Color theme, shows helper, wires animation',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final container = await _buildApp(tester);
      await _openSettings(tester);

      // Open the Theme dropdown and pick Chameleon.
      await tester.tap(find.byType(PopupMenuButton<AppThemeMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chameleon'));
      await tester.pumpAndSettle();

      expect(container.read(isChameleonProvider), isTrue);

      // Color theme dropdown is disabled but still shows the saved preset.
      final colorTheme = tester.widget<PopupMenuButton<AppThemePreset>>(
        find.byType(PopupMenuButton<AppThemePreset>),
      );
      expect(colorTheme.enabled, isFalse);
      expect(find.text('Colors follow the current artwork'), findsOneWidget);
      expect(
        find.text('Purple'),
        findsOneWidget,
        reason: 'the preserved preset label stays visible while disabled',
      );

      // The whole app now uses the deterministic neutral Chameleon fallback
      // (no artwork playing yet) with the long animated-crossfade duration.
      final settingsContext = tester.element(find.byType(SettingsScreen));
      expect(
        Theme.of(settingsContext).colorScheme.surface,
        ChameleonTheme.neutralFallback(isDark: true).colorScheme.surface,
      );
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeAnimationDuration, ChameleonTheme.transitionDuration);
    },
  );

  testWidgets(
    'Artwork drives the whole app; system bars and MiniPlayer follow',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final container = await _buildApp(tester);
      await _enableChameleon(container);
      await tester.pumpAndSettle();

      // No artwork yet → neutral purple fallback.
      final expectedFallback = ChameleonTheme.neutralFallback(isDark: true);
      expect(
        _homeTheme(tester).colorScheme.surface,
        expectedFallback.colorScheme.surface,
      );

      // A playing track with artwork flips the entire app theme.
      await _play(tester, _song('A', 'cover-a.png'));
      expect(_artwork.pending, hasLength(1));
      _artwork.pending[0].complete(_navy);
      await tester.pump();
      await tester.pumpAndSettle();

      final expected = ChameleonTheme.build(_navy);
      final theme = _homeTheme(tester);
      expect(theme.colorScheme.surface, expected.colorScheme.surface);
      expect(theme.brightness, Brightness.dark);

      // VoraTheme extension (context.palette consumers like MiniPlayer and
      // the bottom sheet) carries the artwork accent identity.
      final ext = theme.extension<VoraTheme>()!;
      expect(
        ext.palette.primary,
        expected.extension<VoraTheme>()!.palette.primary,
      );
      expect(
        ext.palette.highlight,
        expected.extension<VoraTheme>()!.palette.highlight,
      );

      // Global system-bar region mirrors the artwork-derived theme.
      final regions = tester.widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      );
      expect(
        regions.any(
          (r) =>
              r.value.systemNavigationBarColor == expected.colorScheme.surface,
        ),
        isTrue,
      );

      // Shell + navigation still render under the dynamic theme.
      expect(find.byType(GlassNavBar), findsOneWidget);
    },
  );

  testWidgets(
    'Clearing the track reverts to the neutral fallback; leaving Chameleon restores the saved preset',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final container = await _buildApp(tester);

      // Save a non-neutral preset, then enable Chameleon.
      await container
          .read(appearanceSettingsProvider.notifier)
          .setThemePreset(AppThemePreset.ember);
      await _enableChameleon(container);
      await tester.pumpAndSettle();

      // Chameleon fallback is purple regardless of the preserved preset.
      final fallback = ChameleonTheme.neutralFallback(isDark: true);
      expect(
        _homeTheme(tester).colorScheme.surface,
        fallback.colorScheme.surface,
      );

      // Artwork applies…
      await _play(tester, _song('C', 'cover-c.png'));
      expect(_artwork.pending, hasLength(1));
      _artwork.pending[0].complete(_amber);
      await tester.pump();
      await tester.pumpAndSettle();
      final expected = ChameleonTheme.build(_amber);
      expect(
        _homeTheme(tester).colorScheme.surface,
        expected.colorScheme.surface,
      );

      // Clearing the track (no artwork) reverts to the purple fallback.
      await _player.clearSession();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        _homeTheme(tester).colorScheme.surface,
        fallback.colorScheme.surface,
      );

      // Leaving Chameleon restores the saved preset (Ember, dark at startup)
      // and switches back to instant theme switches.
      await container
          .read(appearanceSettingsProvider.notifier)
          .setThemeMode(AppThemeMode.system);
      await tester.pumpAndSettle();
      expect(
        _homeTheme(tester).colorScheme.primary,
        AppTheme.of(AppThemePreset.ember).dark.colorScheme.primary,
      );
      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .themeAnimationDuration,
        Duration.zero,
      );
    },
  );

  testWidgets(
    'Rapid A→B→C ends on C and never flashes the fallback in between',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final container = await _buildApp(tester);
      await _enableChameleon(container);
      await tester.pumpAndSettle();

      // Baseline artwork A resolves and applies.
      await _play(tester, _song('A', 'cover-a.png'));
      expect(_artwork.pending, hasLength(1));
      _artwork.pending[0].complete(_navy);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        _homeTheme(tester).colorScheme.surface,
        ChameleonTheme.build(_navy).colorScheme.surface,
      );

      // Skip B then C before either resolves.
      await _play(tester, _song('B', 'cover-b.png'));
      await _play(tester, _song('C', 'cover-c.png'));
      expect(_artwork.pending, hasLength(3));
      expect(_artwork.requested, ['A', 'B', 'C']);

      // While extracting, the previous artwork (A) is still applied — a
      // fallback flash never appears on the way to C.
      expect(
        _homeTheme(tester).colorScheme.surface,
        ChameleonTheme.build(_navy).colorScheme.surface,
      );
      expect(container.read(currentArtworkPaletteProvider).isFallback, isFalse);

      // C finishes first → C's theme everywhere.
      _artwork.pending[2].complete(_amber);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        _homeTheme(tester).colorScheme.surface,
        ChameleonTheme.build(_amber).colorScheme.surface,
      );
      expect(
        container.read(currentArtworkPaletteProvider).songIdentityKey,
        'C',
      );

      // B resolves late and must not win.
      _artwork.pending[1].complete(_emerald);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        _homeTheme(tester).colorScheme.surface,
        ChameleonTheme.build(_amber).colorScheme.surface,
      );
      expect(
        container.read(currentArtworkPaletteProvider).songIdentityKey,
        'C',
      );
    },
  );
}

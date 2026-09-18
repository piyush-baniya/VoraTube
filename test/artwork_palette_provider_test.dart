import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show Color, ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/app/theme/app_theme.dart';
import 'package:vora_tube/core/artwork_palette/artwork_palette.dart';
import 'package:vora_tube/core/artwork_palette/artwork_palette_cache.dart';
import 'package:vora_tube/core/artwork_palette/artwork_palette_service.dart';
import 'package:vora_tube/features/player/presentation/providers/artwork_palette_provider.dart';
import 'package:vora_tube/features/settings/presentation/providers/settings_providers.dart';

import 'fakes/tiny_png.dart';

/// Service whose `resolve` is fully scripted so race timing is deterministic
/// (completions are completed manually, in any order).
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

ArtworkPalette artworkPalette(String marker) {
  return ArtworkPalette(
    dominant: Color(0xFF100000 + marker.codeUnitAt(0)),
    vibrant: Color(0xFF200000 + marker.codeUnitAt(0)),
    muted: const Color(0xFF303030),
    dark: const Color(0xFF404040),
    darkMuted: const Color(0xFF505050),
    light: const Color(0xFF606060),
    lightVibrant: const Color(0xFF707070),
    surface: const Color(0xFF767676),
    surfaceVariant: const Color(0xFF868686),
    accent: Color(0xFF00AA00 + marker.codeUnitAt(0)),
    secondaryAccent: const Color(0xFFB0B0B0),
    onSurface: const Color(0xFFFFFFFF),
    onAccent: const Color(0xFF000000),
    backgroundStart: const Color(0xFF969696),
    backgroundEnd: const Color(0xFFA6A6A6),
    sourceArtworkKey: 'art-$marker',
    extractionVersion: paletteAlgorithmVersion,
    wasFallback: false,
  );
}

ArtworkPaletteController _buildController(
  _ScriptedService service, {
  AppThemePreset preset = AppThemePreset.purple,
  bool dark = true,
}) {
  return ArtworkPaletteController(
    service: service,
    themePaletteOf: () => AppPalette.of(preset),
    isDarkModeOf: () => dark,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ArtworkPaletteController state machine', () {
    test('no artwork yields an immediate ready theme fallback', () {
      final controller = _buildController(_ScriptedService());
      controller.setCurrentArtwork(null);
      expect(controller.state.isReady, isTrue);
      expect(controller.state.isFallback, isTrue);
      expect(controller.state.songIdentityKey, isNull);
      expect(controller.state.palette, isNotNull);
    });

    test('loading keeps the previous palette for continuity', () async {
      final service = _ScriptedService();
      final controller = _buildController(service);
      controller.setCurrentArtwork(
        const ArtworkDescriptor(songIdentityKey: 'A', artPath: 'a.png'),
      );
      expect(controller.state.isExtracting, isTrue);
      await pumpEventQueue();
      expect(service.pending.length, 1);
      service.pending[0].complete(artworkPalette('A'));
      await pumpEventQueue();
      expect(controller.state.isReady, isTrue);
      expect(controller.state.songIdentityKey, 'A');
      expect(controller.state.palette!.sourceArtworkKey, 'art-A');

      // Second track: extracting keeps the previous palette visible.
      controller.setCurrentArtwork(
        const ArtworkDescriptor(songIdentityKey: 'B', artPath: 'b.png'),
      );
      await pumpEventQueue();
      expect(controller.state.isExtracting, isTrue);
      expect(controller.state.palette!.sourceArtworkKey, 'art-A');
    });

    test('stale Song A can never override Song B', () async {
      final service = _ScriptedService();
      final controller = _buildController(service);
      controller.setCurrentArtwork(
        const ArtworkDescriptor(songIdentityKey: 'A', artPath: 'a.png'),
      );
      await pumpEventQueue();
      controller.setCurrentArtwork(
        const ArtworkDescriptor(songIdentityKey: 'B', artPath: 'b.png'),
      );
      await pumpEventQueue();
      expect(service.requested, ['A', 'B']);

      // B finishes first.
      service.pending[1].complete(artworkPalette('B'));
      await pumpEventQueue();
      expect(controller.state.isReady, isTrue);
      expect(controller.state.songIdentityKey, 'B');

      // A finishes late — its generation is stale, so it must not publish.
      service.pending[0].complete(artworkPalette('A'));
      await pumpEventQueue();
      expect(controller.state.songIdentityKey, 'B');
      expect(controller.state.palette!.sourceArtworkKey, 'art-B');
    });

    test('clearing the track drops in-flight extraction', () async {
      final service = _ScriptedService();
      final controller = _buildController(service);
      controller.setCurrentArtwork(
        const ArtworkDescriptor(songIdentityKey: 'A', artPath: 'a.png'),
      );
      await pumpEventQueue();
      controller.setCurrentArtwork(null);
      expect(controller.state.isReady, isTrue);
      expect(controller.state.isFallback, isTrue);
      expect(controller.state.songIdentityKey, isNull);

      service.pending[0].complete(artworkPalette('A'));
      await pumpEventQueue();
      expect(controller.state.songIdentityKey, isNull);
      expect(controller.state.isFallback, isTrue);
    });

    test('extraction failure falls back to the theme', () async {
      final service = _ScriptedService();
      final controller = _buildController(service);
      controller.setCurrentArtwork(
        const ArtworkDescriptor(songIdentityKey: 'A', artPath: 'a.png'),
      );
      await pumpEventQueue();
      service.pending[0].complete(null); // service resolved to nothing
      await pumpEventQueue();
      expect(controller.state.isReady, isTrue);
      expect(controller.state.isFallback, isTrue);
      expect(controller.state.palette!.accent, AppPalette.purple.primary);
    });

    test('theme switch refreshes the fallback palette', () async {
      final service = _ScriptedService();
      final controller = _buildController(
        service,
        preset: AppThemePreset.purple,
      );
      controller.setCurrentArtwork(null);
      expect(controller.state.palette!.accent, AppPalette.purple.primary);

      // Simulate a settings change by swapping the read theme and refreshing.
      final swap = _buildController(service, preset: AppThemePreset.emerald);
      swap.setCurrentArtwork(null);
      expect(swap.state.palette!.accent, AppPalette.emerald.primary);
    });

    test('dark and light fallbacks derive from their theme ramp', () {
      final service = _ScriptedService();
      final controllerDark = _buildController(service, dark: true);
      controllerDark.setCurrentArtwork(null);
      final controllerLight = _buildController(service, dark: false);
      controllerLight.setCurrentArtwork(null);
      // Dark accents use the primary hue; light accents use the lightDeep hue.
      expect(controllerDark.state.palette!.accent, AppPalette.purple.primary);
      expect(
        controllerLight.state.palette!.accent,
        AppPalette.purple.lightDeep,
      );
      expect(
        controllerDark.state.palette!.surface,
        isNot(controllerLight.state.palette!.surface),
      );
    });

    test(
      'OLED theme keeps extracted accents over true-black surfaces',
      () async {
        final service = _ScriptedService();
        final controller = _buildController(
          service,
          preset: AppThemePreset.oled,
        );
        controller.setCurrentArtwork(
          const ArtworkDescriptor(songIdentityKey: 'A', artPath: 'a.png'),
        );
        await pumpEventQueue();
        service.pending[0].complete(artworkPalette('A'));
        await pumpEventQueue();
        expect(controller.state.palette!.surface, const Color(0xFF000000));
        expect(
          controller.state.palette!.accent,
          isNot(const Color(0xFF000000)),
        );
        expect(controller.state.isFallback, isFalse);
      },
    );
  });

  group('currentArtworkPaletteProvider wiring', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('palette_provider_test');
    });
    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // best effort cleanup on Windows
      }
    });

    Future<ArtworkPaletteState> waitUntilReady(
      ProviderContainer container,
    ) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      var state = container.read(currentArtworkPaletteProvider);
      while (!state.isReady && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        state = container.read(currentArtworkPaletteProvider);
      }
      return state;
    }

    test(
      'extracts a real on-disk artwork through the provider stack',
      () async {
        final png = await writeTempFile(
          tempDir,
          'cover.png',
          encodePng(
            width: 128,
            height: 128,
            rgba: regionsRgba(
              width: 128,
              height: 128,
              regions: [
                (0, 0, 96, 128, 40, 90, 200, 255),
                (96, 0, 32, 128, 240, 180, 60, 255),
              ],
            ),
          ),
        );
        final container = ProviderContainer(
          overrides: [
            currentArtworkDescriptorProvider.overrideWithValue(
              ArtworkDescriptor(songIdentityKey: 'song-1', artPath: png.path),
            ),
            themePresetProvider.overrideWithValue(AppThemePreset.purple),
            themeModeProvider.overrideWithValue(ThemeMode.dark),
          ],
        );
        addTearDown(container.dispose);

        final state = await waitUntilReady(container);
        expect(state.isReady, isTrue);
        expect(state.songIdentityKey, 'song-1');
        expect(state.isFallback, isFalse);
        expect(state.palette!.isFromArtwork, isTrue);
        expect(state.palette!.sourceArtworkKey, isNotNull);
        expect(state.basePalette, state.palette);
      },
    );

    test('no track still exposes a coherent theme fallback', () async {
      final container = ProviderContainer(
        overrides: [
          currentArtworkDescriptorProvider.overrideWithValue(null),
          themePresetProvider.overrideWithValue(AppThemePreset.midnight),
          themeModeProvider.overrideWithValue(ThemeMode.light),
        ],
      );
      addTearDown(container.dispose);

      final state = await waitUntilReady(container);
      expect(state.isReady, isTrue);
      expect(state.isFallback, isTrue);
      expect(state.songIdentityKey, isNull);
      expect(state.palette!.surface, AppPalette.midnight.lightRamp.surface);
    });

    test('descriptor change drives a fresh extraction', () async {
      final b = await writeTempFile(
        tempDir,
        'b.png',
        encodePng(
          width: 96,
          height: 96,
          rgba: regionsRgba(
            width: 96,
            height: 96,
            regions: [
              (0, 0, 72, 96, 160, 40, 120, 255),
              (72, 0, 24, 96, 40, 200, 80, 255),
            ],
          ),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          currentArtworkDescriptorProvider.overrideWithValue(
            const ArtworkDescriptor(
              songIdentityKey: 'song-1',
              artPath: '<absent>',
            ),
          ),
          themePresetProvider.overrideWithValue(AppThemePreset.purple),
          themeModeProvider.overrideWithValue(ThemeMode.dark),
        ],
      );
      addTearDown(container.dispose);
      await waitUntilReady(container);
      expect(container.read(currentArtworkPaletteProvider).isFallback, isTrue);

      // New descriptor arrives mid-session; the listen path picks it up.
      container.updateOverrides([
        currentArtworkDescriptorProvider.overrideWithValue(
          ArtworkDescriptor(songIdentityKey: 'song-9', artPath: b.path),
        ),
        themePresetProvider.overrideWithValue(AppThemePreset.purple),
        themeModeProvider.overrideWithValue(ThemeMode.dark),
      ]);
      final state = await waitUntilReady(container);
      expect(state.isFallback, isFalse);
      expect(state.songIdentityKey, 'song-9');
    });

    test('default theme preset resolves through AppPalette.of', () {
      expect(AppPalette.of(AppThemePreset.purple), AppPalette.purple);
    });
  });
}

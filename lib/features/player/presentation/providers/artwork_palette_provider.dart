import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show Brightness, ThemeMode;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/artwork_palette/artwork_palette.dart';
import '../../../../core/artwork_palette/artwork_palette_cache.dart';
import '../../../../core/artwork_palette/artwork_palette_extractor.dart';
import '../../../../core/artwork_palette/artwork_palette_factory.dart';
import '../../../../core/artwork_palette/artwork_palette_service.dart';
import '../../../../features/settings/presentation/providers/settings_providers.dart';
import 'player_providers.dart';

/// Identity of the current track's artwork, or null when nothing is loaded or
/// the track has no artwork. Narrow: never reacts to play/pause or position.
final currentArtworkDescriptorProvider = Provider<ArtworkDescriptor?>((ref) {
  final song = ref.watch(currentTrackProvider);
  if (song == null) return null;
  final path = song.artPath;
  if (path == null || path.isEmpty) return null;
  return ArtworkDescriptor(songIdentityKey: song.identityKey, artPath: path);
});

/// Engine layer used across the app: bounded in-memory + versioned disk cache
/// under `<support>/palettes`, async downscaled extraction.
final artworkPaletteServiceProvider = Provider<ArtworkPaletteService>((ref) {
  return ArtworkPaletteService(
    extractor: const ArtworkPaletteExtractor(),
    cache: ArtworkPaletteCache(
      directory: () async {
        final support = await getApplicationSupportDirectory();
        return Directory('${support.path}${Platform.pathSeparator}palettes');
      },
    ),
  );
});

/// Coarse, always-resolved state of the current artwork palette.
///
/// Consumers should prefer [currentArtworkPaletteProvider] via
/// `ref.watch` — the state collapses the extraction lifecycle into one
/// value so widgets never juggle futures or StreamProviders. The state keeps
/// the previously displayed palette while a new extraction is in flight so a
/// quick track change never flashes a blank surface.
final currentArtworkPaletteProvider =
    StateNotifierProvider<ArtworkPaletteController, ArtworkPaletteState>((ref) {
      final controller = ArtworkPaletteController(
        service: ref.watch(artworkPaletteServiceProvider),
        themePaletteOf: () => AppPalette.of(ref.read(themePresetProvider)),
        isDarkModeOf: () {
          final mode = ref.read(themeModeProvider);
          switch (mode) {
            case ThemeMode.dark:
              return true;
            case ThemeMode.light:
              return false;
            case ThemeMode.system:
              return WidgetsBinding
                      .instance
                      .platformDispatcher
                      .platformBrightness ==
                  Brightness.dark;
          }
        },
      );
      ref.listen<ArtworkDescriptor?>(
        currentArtworkDescriptorProvider,
        (previous, next) => controller.setCurrentArtwork(next),
      );
      ref.listen<AppThemePreset>(
        themePresetProvider,
        (previous, next) => controller.refreshForThemeOrBrightness(),
      );
      ref.listen<ThemeMode>(
        themeModeProvider,
        (previous, next) => controller.refreshForThemeOrBrightness(),
      );
      controller.setCurrentArtwork(ref.read(currentArtworkDescriptorProvider));
      return controller;
    });

/// Lifecycle of a palette request.
enum ArtworkPaletteStatus { extracting, ready }

/// Immutable palette state exposed to the UI.
@immutable
final class ArtworkPaletteState {
  const ArtworkPaletteState._({
    required this.status,
    required this.isFallback,
    this.palette,
    this.basePalette,
    this.previousPalette,
    this.songIdentityKey,
    this.artworkKey,
  });

  factory ArtworkPaletteState.extracting({
    ArtworkPalette? palette,
    ArtworkPalette? previousPalette,
    String? songIdentityKey,
    String? artworkKey,
  }) => ArtworkPaletteState._(
    status: ArtworkPaletteStatus.extracting,
    isFallback: false,
    palette: palette,
    basePalette: palette,
    previousPalette: previousPalette,
    songIdentityKey: songIdentityKey,
    artworkKey: artworkKey,
  );

  factory ArtworkPaletteState.ready({
    required ArtworkPalette palette,
    ArtworkPalette? basePalette,
    String? songIdentityKey,
    String? artworkKey,
    bool isFallback = false,
  }) => ArtworkPaletteState._(
    status: ArtworkPaletteStatus.ready,
    isFallback: isFallback,
    palette: palette,
    basePalette: basePalette,
    songIdentityKey: songIdentityKey,
    artworkKey: artworkKey,
  );

  /// Unresolved: nothing loaded, nothing extracted yet.
  static const ArtworkPaletteState idle = ArtworkPaletteState._(
    status: ArtworkPaletteStatus.extracting,
    isFallback: false,
  );

  final ArtworkPaletteStatus status;

  /// Effective palette, always populated for ready states; while extracting it
  /// holds the previous/theme palette so the UI never goes blank.
  final ArtworkPalette? palette;

  /// Theme-independent extracted palette (null for theme fallbacks and idle).
  final ArtworkPalette? basePalette;

  /// Palette shown before the current request began.
  final ArtworkPalette? previousPalette;

  final String? songIdentityKey;

  /// Cache identity the effective palette belongs to (fallbacks: null).
  final String? artworkKey;

  /// True while the effective palette was derived entirely from the theme.
  final bool isFallback;

  bool get isReady => status == ArtworkPaletteStatus.ready;
  bool get isExtracting => status == ArtworkPaletteStatus.extracting;

  ArtworkPaletteState copyWith({ArtworkPalette? palette}) {
    return ArtworkPaletteState._(
      status: status,
      isFallback: isFallback,
      palette: palette ?? this.palette,
      basePalette: basePalette,
      previousPalette: previousPalette,
      songIdentityKey: songIdentityKey,
      artworkKey: artworkKey,
    );
  }
}

/// Drives palette resolution for the current track and guards against stale
/// Song-A-resolves-after-Song-B publications.
class ArtworkPaletteController extends StateNotifier<ArtworkPaletteState> {
  ArtworkPaletteController({
    required ArtworkPaletteService service,
    required AppPalette Function() themePaletteOf,
    required bool Function() isDarkModeOf,
  }) : _service = service,
       _themePaletteOf = themePaletteOf,
       _isDarkModeOf = isDarkModeOf,
       super(ArtworkPaletteState.idle);

  final ArtworkPaletteService _service;
  final AppPalette Function() _themePaletteOf;
  final bool Function() _isDarkModeOf;

  AppPalette get _theme => _themePaletteOf();

  /// New current track (or null when playback stopped / track has no artwork).
  void setCurrentArtwork(ArtworkDescriptor? descriptor) {
    final songKey = descriptor?.songIdentityKey;
    final previous = state.palette;

    if (descriptor == null || !descriptor.hasArtwork) {
      // Invalidate any in-flight extraction so it can never publish a stale
      // palette for a track that is no longer current.
      _service.cancelPending();
      state = _readyFallback(songKey);
      return;
    }

    // Continuity: keep showing the last palette (theme fallback when there was
    // none) so a skip never flashes a blank surface.
    state = ArtworkPaletteState.extracting(
      palette: previous,
      previousPalette: previous,
      songIdentityKey: songKey,
      artworkKey: previous?.sourceArtworkKey,
    );
    unawaited(_extract(descriptor));
  }

  Future<void> _extract(ArtworkDescriptor descriptor) async {
    // The service bumps its generation synchronously when resolve() is called,
    // so this read captures this exact request's token before any interleave.
    final pending = _service.resolve(descriptor: descriptor);
    final token = _service.generation;
    final ArtworkPaletteResult? result;
    try {
      result = await pending;
    } catch (_) {
      // Extraction is best-effort: any unexpected failure (disk, decode, cache
      // serialization) must fall back to the theme, never crash or stall in
      // "extracting" — but only if this request is still the current one.
      if (!_service.isCurrent(token)) return;
      state = _readyFallback(descriptor.songIdentityKey);
      return;
    }
    final songKey = descriptor.songIdentityKey;
    // Stale guard: Song A's extraction finishing after Song B started must
    // never publish. The token invalidates the instant the next request (or a
    // cancelPending) begins. A null result carries no token, so the guard uses
    // the pre-await token captured above.
    if (!_service.isCurrent(token)) return;
    if (result == null) {
      state = _readyFallback(songKey);
      return;
    }
    final base = result.palette;
    state = ArtworkPaletteState.ready(
      palette: _effective(base),
      basePalette: base,
      songIdentityKey: songKey,
      artworkKey: base.sourceArtworkKey,
    );
  }

  /// Re-derives the effective palette after a theme or brightness change.
  /// Extracted palettes are theme-independent except for OLED surface rules;
  /// fallbacks derive entirely from the theme.
  void refreshForThemeOrBrightness() {
    if (!state.isReady) return; // in-flight result re-applies latest theme
    final base = state.basePalette;
    if (state.isFallback || base == null) {
      state = _readyFallback(state.songIdentityKey);
      return;
    }
    final effective = _effective(base);
    if (effective != state.palette) {
      state = state.copyWith(palette: effective);
    }
  }

  ArtworkPalette _effective(ArtworkPalette base) {
    final oled = _theme.preset == AppThemePreset.oled;
    return ArtworkPaletteTheme.resolveForTheme(
      base,
      palette: _theme,
      isDark: _isDarkModeOf(),
      oled: oled,
    );
  }

  ArtworkPaletteState _readyFallback(String? songKey) {
    final fallback = ArtworkPaletteTheme.buildThemeFallback(
      _theme,
      isDark: _isDarkModeOf(),
    );
    return ArtworkPaletteState.ready(
      palette: fallback,
      songIdentityKey: songKey,
      isFallback: true,
    );
  }
}

import 'dart:ui';

import 'package:flutter/foundation.dart' show immutable;

import 'artwork_contrast.dart';

/// Current extraction/cache algorithm version.
///
/// Bumping this invalidates every previously cached palette: cache entries are
/// stored with this version in their key and are rejected (and pruned) when
/// the version changes. That guarantees a future improvement to color
/// extraction never stays permanently stuck behind stale algorithm output.
const int paletteAlgorithmVersion = 1;

/// Maximum artwork size extracted or cached palettes are keyed against.
const int paletteAnalysisWidth = 64;

/// Forward-looking artwork-color settings contract (not yet persisted).
///
/// V2 UI will expose these; the engine only needs the vocabulary to exist so
/// the architecture cannot silently regress toward hardcoding one behavior.
enum ArtworkColorMode {
  /// Dynamic artwork colors are not used at all.
  off,

  /// Gentle accent-only influence from the artwork.
  subtle,

  /// Full Dynamic palette: surfaces, accents and readable foregrounds.
  dynamicMode,

  /// Artwork colors bleed into backgrounds/app-wide chrome while playing.
  immersive,
}

/// Where an active dynamic palette is allowed to apply.
enum ArtworkColorScope {
  /// The full-screen player only.
  playerOnly,

  /// Full screen player and the MiniPlayer.
  playerAndMini,

  /// The entire app while a track is loaded.
  entireApp,
}

/// Immutable, complete dynamic palette for one artwork.
///
/// Semantic slots rather than raw swatches: consumers bind to roles (surface,
/// accent, background gradient…) instead of re-deriving color decisions, so a
/// later algorithm upgrade can change *how* slots are computed without
/// touching the surfaces that read them.
///
/// The palette is theme-independent by design. Theme concerns — fallback and
/// OLED black-surfaces — are applied by whoever resolves the palette for the
/// current theme (see `ArtworkPaletteTheme`).
@immutable
class ArtworkPalette {
  const ArtworkPalette({
    required this.dominant,
    required this.vibrant,
    required this.muted,
    required this.dark,
    required this.darkMuted,
    required this.light,
    required this.lightVibrant,
    required this.surface,
    required this.surfaceVariant,
    required this.accent,
    required this.secondaryAccent,
    required this.onSurface,
    required this.onAccent,
    required this.backgroundStart,
    required this.backgroundEnd,
    this.sourceArtworkKey,
    this.extractionVersion = paletteAlgorithmVersion,
    this.wasFallback = false,
  });

  /// Most frequent color family in the artwork.
  final Color dominant;

  /// High-saturation, mid-luminance color for accents and progress.
  final Color vibrant;

  /// Low-saturation supporting color.
  final Color muted;

  /// Deep shadow variant.
  final Color dark;

  /// Deep, low-saturation shadow variant.
  final Color darkMuted;

  /// Bright tint used for highlights on dark surfaces.
  final Color light;

  /// Bright, chromatic tint (alternative gradient stop).
  final Color lightVibrant;

  /// Main tinted background surface. Never pure white/black for a real
  /// artwork (see extraction guards); OLED overrides this to true black.
  final Color surface;

  /// One tonal step away from [surface], for gradients and elevated cards.
  final Color surfaceVariant;

  /// The readable hero color (hero text, filled buttons, progress fill).
  final Color accent;

  /// Supporting accent (secondary highlights, waveform, glow).
  final Color secondaryAccent;

  /// Readable foreground for [surface] (and [surfaceVariant]).
  final Color onSurface;

  /// Readable foreground for [accent].
  final Color onAccent;

  /// Background gradient start for the player surface.
  final Color backgroundStart;

  /// Background gradient end for the player surface.
  final Color backgroundEnd;

  /// Cache identity of the artwork this palette was extracted from, or null
  /// when the palette came from a theme fallback.
  final String? sourceArtworkKey;

  /// Which extraction algorithm produced this palette.
  final int extractionVersion;

  /// True when this palette was derived from the active theme because no
  /// usable artwork (or extraction) existed.
  final bool wasFallback;

  bool get isFromArtwork => !wasFallback;

  ArtworkPalette copyWith({
    Color? dominant,
    Color? vibrant,
    Color? muted,
    Color? dark,
    Color? darkMuted,
    Color? light,
    Color? lightVibrant,
    Color? surface,
    Color? surfaceVariant,
    Color? accent,
    Color? secondaryAccent,
    Color? onSurface,
    Color? onAccent,
    Color? backgroundStart,
    Color? backgroundEnd,
    String? sourceArtworkKey,
    int? extractionVersion,
    bool? wasFallback,
  }) {
    return ArtworkPalette(
      dominant: dominant ?? this.dominant,
      vibrant: vibrant ?? this.vibrant,
      muted: muted ?? this.muted,
      dark: dark ?? this.dark,
      darkMuted: darkMuted ?? this.darkMuted,
      light: light ?? this.light,
      lightVibrant: lightVibrant ?? this.lightVibrant,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      accent: accent ?? this.accent,
      secondaryAccent: secondaryAccent ?? this.secondaryAccent,
      onSurface: onSurface ?? this.onSurface,
      onAccent: onAccent ?? this.onAccent,
      backgroundStart: backgroundStart ?? this.backgroundStart,
      backgroundEnd: backgroundEnd ?? this.backgroundEnd,
      sourceArtworkKey: sourceArtworkKey ?? this.sourceArtworkKey,
      extractionVersion: extractionVersion ?? this.extractionVersion,
      wasFallback: wasFallback ?? this.wasFallback,
    );
  }

  /// Interpolates between two palettes. Intended for future 500–900 ms song
  /// transition animations; both endpoints must come from the same theme
  /// context so the interpolated mid-values stay consistent.
  static ArtworkPalette lerp(ArtworkPalette a, ArtworkPalette b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    return ArtworkPalette(
      dominant: Color.lerp(a.dominant, b.dominant, t)!,
      vibrant: Color.lerp(a.vibrant, b.vibrant, t)!,
      muted: Color.lerp(a.muted, b.muted, t)!,
      dark: Color.lerp(a.dark, b.dark, t)!,
      darkMuted: Color.lerp(a.darkMuted, b.darkMuted, t)!,
      light: Color.lerp(a.light, b.light, t)!,
      lightVibrant: Color.lerp(a.lightVibrant, b.lightVibrant, t)!,
      surface: Color.lerp(a.surface, b.surface, t)!,
      surfaceVariant: Color.lerp(a.surfaceVariant, b.surfaceVariant, t)!,
      accent: Color.lerp(a.accent, b.accent, t)!,
      secondaryAccent: Color.lerp(a.secondaryAccent, b.secondaryAccent, t)!,
      onSurface: Color.lerp(a.onSurface, b.onSurface, t)!,
      onAccent: Color.lerp(a.onAccent, b.onAccent, t)!,
      backgroundStart: Color.lerp(a.backgroundStart, b.backgroundStart, t)!,
      backgroundEnd: Color.lerp(a.backgroundEnd, b.backgroundEnd, t)!,
      sourceArtworkKey: t < 0.5 ? a.sourceArtworkKey : b.sourceArtworkKey,
      extractionVersion: t < 0.5 ? a.extractionVersion : b.extractionVersion,
      wasFallback: t < 0.5 ? a.wasFallback : b.wasFallback,
    );
  }

  /// OLED-safe copy: true-black surfaces, artwork colors relegated to
  /// accents/highlights. Progress and glow colors survive.
  ArtworkPalette withTrueBlackSurfaces() {
    const black = Color(0xFF000000);
    const nearBlack = Color(0xFF0A0A0B);
    return ArtworkPalette(
      dominant: dominant,
      vibrant: vibrant,
      muted: muted,
      dark: black,
      darkMuted: nearBlack,
      light: light,
      lightVibrant: lightVibrant,
      surface: black,
      surfaceVariant: nearBlack,
      accent: accent,
      secondaryAccent: secondaryAccent,
      onSurface: const Color(0xFFFFFFFF),
      onAccent: onAccent,
      backgroundStart: black,
      backgroundEnd: nearBlack,
      sourceArtworkKey: sourceArtworkKey,
      extractionVersion: extractionVersion,
      wasFallback: wasFallback,
    );
  }

  /// Applies a user-chosen scalar intensity (0..1) to the accent family.
  /// Kept deliberately simple: consumers animate/blend how they will.
  ArtworkPalette withIntensity(double intensity) {
    final t = intensity.clamp(0.0, 1.0);
    final towardThemeAccent = Color.lerp(accent, dominant, (1 - t) * 0.5)!;
    return ArtworkPalette(
      dominant: dominant,
      vibrant: Color.lerp(vibrant, dominant, (1 - t) * 0.5)!,
      muted: muted,
      dark: dark,
      darkMuted: darkMuted,
      light: light,
      lightVibrant: lightVibrant,
      surface: surface,
      surfaceVariant: surfaceVariant,
      accent: towardThemeAccent,
      secondaryAccent: secondaryAccent,
      onSurface: onSurface,
      onAccent: ArtworkContrast.foregroundFor(towardThemeAccent),
      backgroundStart: backgroundStart,
      backgroundEnd: backgroundEnd,
      sourceArtworkKey: sourceArtworkKey,
      extractionVersion: extractionVersion,
      wasFallback: wasFallback,
    );
  }

  /// All 15 color slots; lets tests and debug surfaces iterate the palette.
  List<Color> get colorSlots => [
    dominant,
    vibrant,
    muted,
    dark,
    darkMuted,
    light,
    lightVibrant,
    surface,
    surfaceVariant,
    accent,
    secondaryAccent,
    onSurface,
    onAccent,
    backgroundStart,
    backgroundEnd,
  ];

  /// Compact payload for the persistent palette cache. Only ARGB ints are
  /// stored so an opaque one-file-per-artwork cache stays tiny.
  Map<String, Object> encodeCachePayload() {
    return <String, Object>{
      'v': extractionVersion,
      'k': sourceArtworkKey ?? '',
      'f': wasFallback ? 1 : 0,
      'dominant': dominant.toARGB32(),
      'vibrant': vibrant.toARGB32(),
      'muted': muted.toARGB32(),
      'dark': dark.toARGB32(),
      'darkMuted': darkMuted.toARGB32(),
      'light': light.toARGB32(),
      'lightVibrant': lightVibrant.toARGB32(),
      'surface': surface.toARGB32(),
      'surfaceVariant': surfaceVariant.toARGB32(),
      'accent': accent.toARGB32(),
      'secondaryAccent': secondaryAccent.toARGB32(),
      'onSurface': onSurface.toARGB32(),
      'onAccent': onAccent.toARGB32(),
      'backgroundStart': backgroundStart.toARGB32(),
      'backgroundEnd': backgroundEnd.toARGB32(),
    };
  }

  /// Rebuilds a palette from [encodeCachePayload], or null when the payload
  /// was produced by a different algorithm version or is malformed.
  static ArtworkPalette? decodeCachePayload(
    Map<String, Object?>? payload, {
    required int expectedVersion,
  }) {
    if (payload == null) return null;
    final version = payload['v'];
    if (version is! int || version != expectedVersion) return null;
    Color? slot(String key) {
      final raw = payload[key];
      if (raw is! int) return null;
      return Color(raw);
    }

    final dominant = slot('dominant');
    final vibrant = slot('vibrant');
    final muted = slot('muted');
    final dark = slot('dark');
    final darkMuted = slot('darkMuted');
    final light = slot('light');
    final lightVibrant = slot('lightVibrant');
    final surface = slot('surface');
    final surfaceVariant = slot('surfaceVariant');
    final accent = slot('accent');
    final secondaryAccent = slot('secondaryAccent');
    final onSurface = slot('onSurface');
    final onAccent = slot('onAccent');
    final backgroundStart = slot('backgroundStart');
    final backgroundEnd = slot('backgroundEnd');
    if (dominant == null ||
        vibrant == null ||
        muted == null ||
        dark == null ||
        darkMuted == null ||
        light == null ||
        lightVibrant == null ||
        surface == null ||
        surfaceVariant == null ||
        accent == null ||
        secondaryAccent == null ||
        onSurface == null ||
        onAccent == null ||
        backgroundStart == null ||
        backgroundEnd == null) {
      return null;
    }
    final key = payload['k'];
    return ArtworkPalette(
      dominant: dominant,
      vibrant: vibrant,
      muted: muted,
      dark: dark,
      darkMuted: darkMuted,
      light: light,
      lightVibrant: lightVibrant,
      surface: surface,
      surfaceVariant: surfaceVariant,
      accent: accent,
      secondaryAccent: secondaryAccent,
      onSurface: onSurface,
      onAccent: onAccent,
      backgroundStart: backgroundStart,
      backgroundEnd: backgroundEnd,
      sourceArtworkKey: key is String && key.isNotEmpty ? key : null,
      extractionVersion: version,
      wasFallback: payload['f'] == 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtworkPalette &&
          dominant == other.dominant &&
          vibrant == other.vibrant &&
          muted == other.muted &&
          dark == other.dark &&
          darkMuted == other.darkMuted &&
          light == other.light &&
          lightVibrant == other.lightVibrant &&
          surface == other.surface &&
          surfaceVariant == other.surfaceVariant &&
          accent == other.accent &&
          secondaryAccent == other.secondaryAccent &&
          onSurface == other.onSurface &&
          onAccent == other.onAccent &&
          backgroundStart == other.backgroundStart &&
          backgroundEnd == other.backgroundEnd &&
          sourceArtworkKey == other.sourceArtworkKey &&
          extractionVersion == other.extractionVersion &&
          wasFallback == other.wasFallback;

  @override
  int get hashCode => Object.hash(
    dominant,
    vibrant,
    muted,
    dark,
    darkMuted,
    light,
    lightVibrant,
    surface,
    surfaceVariant,
    accent,
    secondaryAccent,
    onSurface,
    onAccent,
    backgroundStart,
    backgroundEnd,
    sourceArtworkKey,
    extractionVersion,
    wasFallback,
  );
}

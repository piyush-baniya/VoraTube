import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Color;

import 'artwork_contrast.dart';
import 'artwork_palette.dart';

/// Extracts a complete, deterministic [ArtworkPalette] from artwork pixels.
///
/// Decoding happens through the Flutter image codec with a hard `targetWidth`
/// cap, so a multi-megapixel cover is never fully decoded: the engine asks the
/// codec for a ~64px analysis image and only iterates those pixels. File IO is
/// async and never happens on the widget tree.
///
/// The extractor is theme-independent — the same artwork yields the same
/// palette regardless of the active VoraTube theme. Theme fallback and OLED
/// surface overrides are applied *after* extraction by the palette factory /
/// provider, never baked into the cached artifact.
class ArtworkPaletteExtractor {
  const ArtworkPaletteExtractor();

  /// Hard cap on solid pixels actually analyzed (tall portrait artwork at the
  /// 64px analysis width still stays well under this).
  static const int maxAnalysisPixels = paletteAnalysisWidth * 128;

  /// Below this many solid pixels the artwork cannot describe a palette.
  static const int minSolidPixels = 48;

  /// Reads and analyzes [file]. Returns null when the artwork is unusable
  /// (missing, corrupt, effectively transparent, or too small).
  Future<ArtworkPalette?> extractFromFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return await extractFromBytes(bytes);
    } on FileSystemException {
      return null;
    }
  }

  /// Decodes [bytes] downscaled and analyzes the result.
  Future<ArtworkPalette?> extractFromBytes(
    Uint8List bytes, {
    int analysisWidth = paletteAnalysisWidth,
  }) async {
    if (bytes.isEmpty) return null;
    ui.Codec codec;
    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: analysisWidth,
        allowUpscaling: false,
      );
    } catch (_) {
      return null;
    }
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final width = image.width;
      final height = image.height;
      if (width <= 0 || height <= 0 || width * height > maxAnalysisPixels) {
        image.dispose();
        return null;
      }
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      if (data == null) return null;
      return analyzeRgba(
        data.buffer.asUint8List(),
        width: width,
        height: height,
      );
    } catch (_) {
      return null;
    } finally {
      codec.dispose();
    }
  }

  /// Pure-pixel analysis over an RGBA buffer. Exposed (and tested) directly
  /// so extraction semantics are verifiable without PNG fixtures.
  ArtworkPalette? analyzeRgba(
    Uint8List rgba, {
    required int width,
    required int height,
  }) {
    final total = width * height;
    if (total == 0 || rgba.length < total * 4) return null;

    final solid = <Color>[];
    // Histogram of the 4-bit-quantized RGB (12-bit keys).
    final hist = <int, int>{};
    for (var i = 0; i < total; i++) {
      final r = rgba[i * 4];
      final g = rgba[i * 4 + 1];
      final b = rgba[i * 4 + 2];
      final a = rgba[i * 4 + 3];
      if (a < 128) continue;
      solid.add(Color.fromARGB(255, r, g, b));
      final key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4);
      hist[key] = (hist[key] ?? 0) + 1;
    }
    if (solid.length < minSolidPixels) return null;

    final stats = _PixelStats.fromSamples(solid, hist);
    return _derivePalette(stats);
  }
}

/// Aggregated color statistics over a solid-pixel sample.
class _PixelStats {
  const _PixelStats({
    required this.dominant,
    required this.vibrant,
    required this.muted,
    required this.dark,
    required this.darkMuted,
    required this.light,
    required this.lightVibrant,
    required this.meanLuminance,
    required this.maxSaturation,
  });

  final Color dominant;
  final Color? vibrant;
  final Color? muted;
  final Color? dark;
  final Color? darkMuted;
  final Color? light;
  final Color? lightVibrant;

  /// Average HSL lightness of the sample (0..1).
  final double meanLuminance;
  final double maxSaturation;

  static Color _mean(List<Color> pixels) {
    var r = 0;
    var g = 0;
    var b = 0;
    for (final px in pixels) {
      r += (px.r * 255).round();
      g += (px.g * 255).round();
      b += (px.b * 255).round();
    }
    final n = pixels.length;
    return Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
  }

  factory _PixelStats.fromSamples(List<Color> solid, Map<int, int> hist) {
    // Dominant = mean RGB of the most populous quantized bucket.
    var dominant = _mean(solid);
    var bestCount = -1;
    var bestKey = -1;
    hist.forEach((key, count) {
      if (count > bestCount || (count == bestCount && key < bestKey)) {
        bestCount = count;
        bestKey = key;
      }
    });
    if (bestKey >= 0) {
      final wanted = <Color>[];
      final keyRb = bestKey >> 8;
      final keyGb = bestKey >> 4 & 0xF;
      final keyBb = bestKey & 0xF;
      for (final px in solid) {
        if ((px.r * 255).round() >> 4 == keyRb &&
            (px.g * 255).round() >> 4 == keyGb &&
            (px.b * 255).round() >> 4 == keyBb) {
          wanted.add(px);
        }
      }
      if (wanted.isNotEmpty) dominant = _mean(wanted);
    }

    // Categorical means defined on HSL ranges so grayscale/dark/bright
    // artwork still land in the right buckets.
    final vibrant = <Color>[];
    final muted = <Color>[];
    final dark = <Color>[];
    final darkMuted = <Color>[];
    final light = <Color>[];
    final lightVibrant = <Color>[];
    var lumSum = 0.0;
    var satMax = 0.0;
    for (final px in solid) {
      final s = ArtworkContrast.saturation(px);
      final l = ArtworkContrast.lightness(px);
      final hue = ArtworkContrast.hue(px);
      lumSum += l;
      if (s > satMax) satMax = s;
      if (s >= 0.42 && l >= 0.30 && l <= 0.72 && hue > 0.5) {
        vibrant.add(px);
      }
      if (s <= 0.20 && l >= 0.30 && l <= 0.68) {
        muted.add(px);
      }
      if (l <= 0.26) {
        dark.add(px);
      }
      if (l <= 0.34 && s <= 0.24) {
        darkMuted.add(px);
      }
      if (l >= 0.68) {
        light.add(px);
      }
      if (l >= 0.64 && s >= 0.38) {
        lightVibrant.add(px);
      }
    }
    final meanLum = lumSum / solid.length;
    return _PixelStats(
      dominant: dominant,
      vibrant: vibrant.isEmpty ? null : _mean(vibrant),
      muted: muted.isEmpty ? null : _mean(muted),
      dark: dark.isEmpty ? null : _mean(dark),
      darkMuted: darkMuted.isEmpty ? null : _mean(darkMuted),
      light: light.isEmpty ? null : _mean(light),
      lightVibrant: lightVibrant.isEmpty ? null : _mean(lightVibrant),
      meanLuminance: meanLum,
      maxSaturation: satMax,
    );
  }
}

/// Maps aggregated pixel statistics onto the semantic [ArtworkPalette] slots,
/// applying brightness/saturation guards so the result is always usable.
ArtworkPalette _derivePalette(_PixelStats s) {
  final darkArtwork = s.meanLuminance < 0.20;
  final brightArtwork = s.meanLuminance > 0.84;
  final colorful = s.maxSaturation >= 0.28;

  // Accent: prefer a real vibrant swatch; on low-chroma artwork fall back to
  // a tasteful, saturation-capped tint of the dominant color rather than
  // inventing an arbitrary hue.
  final accent = colorful
      ? (s.vibrant != null
            ? ArtworkContrast.clampTone(
                s.vibrant!,
                minLightness: 0.38,
                maxLightness: 0.62,
                minSaturation: 0.30,
                maxSaturation: 0.86,
              )
            : ArtworkContrast.clampTone(
                s.dominant,
                minLightness: 0.40,
                maxLightness: 0.60,
                minSaturation: 0.30,
                maxSaturation: 0.86,
              ))
      : ArtworkContrast.clampTone(
          s.dominant,
          maxSaturation: 0.24,
          minLightness: darkArtwork ? 0.58 : 0.40,
          maxLightness: darkArtwork ? 0.70 : 0.54,
        );

  final secondaryAccent = s.lightVibrant != null
      ? ArtworkContrast.clampTone(
          s.lightVibrant!,
          minLightness: 0.62,
          maxLightness: 0.82,
          minSaturation: 0.25,
          maxSaturation: 0.90,
        )
      : ArtworkContrast.clampTone(
          ArtworkContrast.lighten(accent, 0.22),
          maxLightness: 0.84,
        );

  final dominant = ArtworkContrast.clampTone(s.dominant, maxSaturation: 0.95);

  // Surface: the artwork's dominant color, heavily desaturated so it never
  // drowns UI, and brightness-clamped so a mostly-white cover can never
  // produce a pure white player (and a black cover stays a usable dark
  // surface). OLED replaces surfaces later by design.
  final surface = ArtworkContrast.clampTone(
    ArtworkContrast.desaturate(s.dominant, 0.40),
    minLightness: darkArtwork ? 0.09 : 0.14,
    maxLightness: brightArtwork ? 0.76 : 0.80,
    maxSaturation: 0.28,
  );
  final surfaceL = ArtworkContrast.lightness(surface);
  final surfaceVariant = ArtworkContrast.withLightness(
    surface,
    surfaceL < 0.5
        ? math.min(0.92, surfaceL + 0.10)
        : math.max(0.06, surfaceL - 0.08),
  );

  final dark = ArtworkContrast.withLightness(
    s.dark ?? s.dominant,
    math.min(0.16, ArtworkContrast.lightness(s.dark ?? s.dominant)),
  );
  final darkMuted = ArtworkContrast.clampTone(
    s.darkMuted ?? ArtworkContrast.desaturate(dark, 0.55),
    minLightness: 0.06,
    maxLightness: 0.20,
  );
  final light = ArtworkContrast.clampTone(
    s.light ?? ArtworkContrast.lighten(s.dominant, 0.35),
    maxLightness: 0.88,
    maxSaturation: 0.35,
  );
  final lightVibrant = s.lightVibrant != null
      ? ArtworkContrast.clampTone(
          s.lightVibrant!,
          minLightness: 0.66,
          maxLightness: 0.88,
          maxSaturation: 0.90,
        )
      : ArtworkContrast.clampTone(
          ArtworkContrast.lighten(accent, 0.30),
          maxLightness: 0.86,
        );
  final muted = ArtworkContrast.clampTone(
    s.muted ?? ArtworkContrast.desaturate(s.dominant, 0.5),
    minLightness: 0.30,
    maxLightness: 0.70,
  );

  // The vibrant slot must stay populated (it feeds glow/highlight roles), so
  // derive it from the accent family when the artwork had no vibrant region.
  final vibrant = ArtworkContrast.clampTone(
    s.vibrant ?? ArtworkContrast.lighten(accent, 0.10),
    minLightness: 0.36,
    maxLightness: 0.66,
    minSaturation: 0.20,
    maxSaturation: 0.88,
  );

  // Readable foregrounds decided with real WCAG math, never hardcoded names.
  final onSurface = _readableForeground(surface);
  final onAccent = _readableForeground(accent);

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
    backgroundStart: surface,
    backgroundEnd: surfaceVariant,
    sourceArtworkKey: null,
    extractionVersion: paletteAlgorithmVersion,
    wasFallback: false,
  );
}

/// Foreground that keeps a minimum WCAG contrast against [background]:
/// starts from the WCAG-best black/white and rescues it if the raw best choice
/// would sit below [minRatio] (mid-luminance surfaces/accents).
Color _readableForeground(Color background, {double minRatio = 3.0}) {
  final choice = ArtworkContrast.foregroundFor(background);
  if (ArtworkContrast.contrastRatio(choice, background) >= minRatio) {
    return choice;
  }
  return ArtworkContrast.ensureContrast(choice, background, minRatio: minRatio);
}

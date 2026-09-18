import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:vora_tube/core/artwork_palette/artwork_palette.dart';

ArtworkPalette buildPalette({int seed = 0, bool fallback = false}) {
  return ArtworkPalette(
    dominant: Color(0xFF100000 + seed),
    vibrant: Color(0xFF200000 + seed),
    muted: Color(0xFF300000 + seed),
    dark: Color(0xFF400000 + seed),
    darkMuted: Color(0xFF500000 + seed),
    light: Color(0xFF600000 + seed),
    lightVibrant: Color(0xFF700000 + seed),
    surface: Color(0xFF800000 + seed),
    surfaceVariant: Color(0xFF900000 + seed),
    accent: Color(0xFFA00000 + seed),
    secondaryAccent: Color(0xFFB00000 + seed),
    onSurface: Color(0xFFC00000 + seed),
    onAccent: Color(0xFFD00000 + seed),
    backgroundStart: Color(0xFFE00000 + seed),
    backgroundEnd: Color(0xFFF00000 + seed),
    sourceArtworkKey: 'key-$seed',
    extractionVersion: paletteAlgorithmVersion,
    wasFallback: fallback,
  );
}

void main() {
  group('ArtworkPalette equality + metadata', () {
    test('equal palettes compare equal and share hash', () {
      final a = buildPalette();
      final b = buildPalette();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('any differing slot breaks equality', () {
      final a = buildPalette();
      final b = a.copyWith(accent: const Color(0xFFFF00FF));
      expect(a == b, isFalse);
    });

    test('isFromArtwork reflects wasFallback', () {
      expect(buildPalette().isFromArtwork, isTrue);
      expect(buildPalette(fallback: true).isFromArtwork, isFalse);
    });
  });

  group('ArtworkPalette.lerp', () {
    test('endpoints are returned unchanged', () {
      final a = buildPalette();
      final b = buildPalette(seed: 0x40);
      expect(ArtworkPalette.lerp(a, b, 0), a);
      expect(ArtworkPalette.lerp(a, b, 1), b);
    });

    test('midpoint equals per-slot Color.lerp', () {
      final a = buildPalette();
      final b = buildPalette(seed: 0x40);
      final mid = ArtworkPalette.lerp(a, b, 0.5);
      for (var i = 0; i < 15; i++) {
        expect(
          mid.colorSlots[i],
          Color.lerp(a.colorSlots[i], b.colorSlots[i], 0.5),
        );
      }
    });

    test('metadata snaps to the near endpoint', () {
      final a = buildPalette();
      final b = buildPalette(seed: 0x40);
      expect(ArtworkPalette.lerp(a, b, 0.4).sourceArtworkKey, 'key-0');
      expect(ArtworkPalette.lerp(a, b, 0.6).sourceArtworkKey, 'key-64');
    });
  });

  group('withTrueBlackSurfaces (OLED)', () {
    test('surfaces become true black while accents survive', () {
      final base = buildPalette();
      final oled = base.withTrueBlackSurfaces();
      expect(oled.surface, const Color(0xFF000000));
      expect(oled.surfaceVariant, const Color(0xFF0A0A0B));
      expect(oled.dark, const Color(0xFF000000));
      expect(oled.darkMuted, const Color(0xFF0A0A0B));
      expect(oled.backgroundStart, const Color(0xFF000000));
      expect(oled.accent, base.accent);
      expect(oled.secondaryAccent, base.secondaryAccent);
      expect(oled.vibrant, base.vibrant);
      expect(oled.lightVibrant, base.lightVibrant);
    });

    test('onSurface becomes white for the black canvas', () {
      expect(
        buildPalette().withTrueBlackSurfaces().onSurface,
        const Color(0xFFFFFFFF),
      );
    });

    test('metadata is preserved', () {
      final oled = buildPalette().withTrueBlackSurfaces();
      expect(oled.sourceArtworkKey, 'key-0');
      expect(oled.extractionVersion, paletteAlgorithmVersion);
      expect(oled.wasFallback, isFalse);
    });
  });

  group('cache payload', () {
    test('round-trips through encode then decode', () {
      final original = buildPalette();
      final decoded = ArtworkPalette.decodeCachePayload(
        original.encodeCachePayload(),
        expectedVersion: paletteAlgorithmVersion,
      );
      expect(decoded, original);
    });

    test('rejects a payload from another algorithm version', () {
      final payload = buildPalette().encodeCachePayload()..['v'] = 999;
      expect(
        ArtworkPalette.decodeCachePayload(
          payload,
          expectedVersion: paletteAlgorithmVersion,
        ),
        isNull,
      );
    });

    test('rejects null and malformed payloads', () {
      expect(
        ArtworkPalette.decodeCachePayload(
          null,
          expectedVersion: paletteAlgorithmVersion,
        ),
        isNull,
      );
      expect(
        ArtworkPalette.decodeCachePayload(<String, Object?>{
          'v': paletteAlgorithmVersion,
        }, expectedVersion: paletteAlgorithmVersion),
        isNull,
      );
      expect(
        ArtworkPalette.decodeCachePayload(<String, Object?>{
          ...buildPalette().encodeCachePayload(),
          'accent': 'oops',
        }, expectedVersion: paletteAlgorithmVersion),
        isNull,
      );
    });

    test('payload stores only ARGB ints + tiny metadata', () {
      final payload = buildPalette().encodeCachePayload();
      for (final entry in payload.entries) {
        if (entry.key == 'k') {
          expect(entry.value, isA<String>(), reason: '${entry.key} metadata');
        } else {
          expect(entry.value, isA<int>(), reason: entry.key);
        }
      }
      expect(payload['v'], paletteAlgorithmVersion);
    });
  });

  test('paletteAlgorithmVersion is pinned at 1 for this release', () {
    expect(paletteAlgorithmVersion, 1);
  });
}

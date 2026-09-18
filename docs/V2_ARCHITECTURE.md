# VoraTube V2 Architecture

This document describes the architecture that ships in the `v2` branch. It is
split into two parts:

1. **Existing architecture** — the repository as it existed at `main`
   (`8df72dc ~0`), preserved unchanged.
2. **V2 additions** — the Dynamic Artwork Palette engine built on top of it.

The design goal is that the dynamic artwork palette is **purely additive**: it
wraps the existing theme/player stack, never re-plumbs it, and every path can
fall back to the exact pre-V2 look.

---

## 1. Existing architecture (main, unchanged)

### 1.1 App / theme layer

- `lib/app/theme/palettes.dart` defines material/Tonality-mode palettes.
- `lib/app/theme/app_theme.dart` defines the `AppThemePreset` enum of **9
  presets** (incl. `oled`) and the `AppPalette`/`AppSurfaceRamp` static lookup
  tables. `AppPalette.of(preset)` returns the static, constant palette for a
  preset. A palette exposes:
  - `darkRamp` / `lightRamp` → `AppSurfaceRamp` with `surface`, `surfaceLow`,
    `surfaceContainer`, `textPrimary`
  - `primary`, `lightDeep`, `highlight` accent colors
  - `preset` back-reference.
- Theme selection is driven from `lib/features/settings/presentation/providers/settings_providers.dart`:
  - `themePresetProvider` → `AppThemePreset`
  - `themeModeProvider` → `ThemeMode` (`system` / `light` / `dark`)
  - settings widgets (`settings_screen.dart`, `settings_tile.dart`) mutate
    these providers; the app root consumes them to build `ThemeData`.

### 1.2 Player layer

- `lib/core/player/player_controller.dart` is the play state holder.
  - `SongRef` is the "currently intended track" model with
    `identityKey` (the song's stable DB identity) and `artPath` (resolved
    artwork file path).
  - `currentTrackProvider` (`lib/features/player/presentation/providers/player_providers.dart`)
    watches the controller and exposes the current `SongRef` (or null when
    cleared/paused on nothing).
- Audio playback itself lives in `just_audio_controller.dart`; the controller
  also exposes the `songIdentityKey` of the loaded track.

### 1.3 Artwork ingest

- `lib/core/ingest/artwork/artwork_file_cache.dart` resolves a song's
  `artPath` to an on-disk `File`, with memoized existence resolution
  (`resolve(String?) → File?`). This is the same path rendering widgets already
  use for artwork images.
- Artwork is currently consumed visually through the default Flutter `Image`
  widget stack (e.g. `song_tile.dart`, full/mini player).

### 1.4 Conventions carried into V2

- Riverpod 2 providers (`overrideWithValue` / `updateOverrides` in tests).
- `FakePlayerController` + `ProviderContainer` in tests
  (`test/fakes/fake_player.dart`).
- Controllers constructed with private library callbacks (flags `_service`, etc.)
  — a deliberate repo-wide style that `prefer_initializing_formals` flags but
  that keeps wiring explicit (same in `just_audio_controller.dart`).

---

## 2. V2 additions — Dynamic Artwork Palette engine

```
                +---------------------------------------------------+
                | provider: artworkPaletteProvider                  |
                |   ArtworkPaletteController               (Riverpod)|
                +-------------------------------------------+-------+
                                                            ^
                watches currentTrackProvider                |
                        (SongRef)            refreshForThemeOrBrightness
                                                            |
                +-------------------------------------------+-------+
                | ArtworkPaletteService   (race-protected, cache-first)|
                |   monotonic generation  /  cancelPending()          |
                +------------------------------------------+--------+
                                                            ^
                                            resolve(ArtworkDescriptor)
                +-------------------------------------------+-------+
                | ArtworkPaletteCache (memory LRU 96 + disk JSON)    |
                +------------------------------------------+--------+
                ^
                | extract (64x64 downscale, cache key sha256)
                +--------------------------+
                | ArtworkPaletteExtractor  |
                +--------------------------+
                |
                v
        theme bridging
        ArtworkPaletteTheme.resolveForTheme / buildThemeFallback
        ArtworkContrast (WCAG 2.x relative luminance, min 3.0)
```

### 2.1 Data model — `lib/core/artwork_palette/artwork_palette.dart`

`ArtworkPalette` is an immutable DTO with 16 color slots:

- `dominant`, `vibrant`, `muted`, `dark`, `darkMuted`, `light`,
  `lightVibrant`, `surface`, `surfaceVariant`, `accent`,
  `secondaryAccent`, `onSurface`, `onAccent`, `backgroundStart`,
  `backgroundEnd`
- plus `sourceArtworkKey` (cache key of the artwork that produced it, or null
  for theme fallbacks), `extractionVersion` (pinned `paletteAlgorithmVersion`,
  currently `1`), and `wasFallback`.

It is JSON-serializable (versioned wrapper with `v` and `payload`) for the disk
cache and self-describing for future algorithm bumps.

### 2.2 Extraction — `artwork_palette_extractor.dart`

- Uses only `dart:ui` → no new dependencies.
- `ArtworkFileCache.resolve()` → `File` → bytes → PNG decode via
  `ui.instantiateImageCodec(bytes, targetWidth: paletteAnalysisWidth (
  64), allowUpscaling: false)`.
- Downscales to a 64x64 RGBA matrix and quantizes into a 16-slot color ramp
  (`analyzeRgba`) using a deterministic pixel-hash / popularity bucket pass.
- The analysis is **theme-independent**: extraction never consults a theme.
- `ArtworkPaletteExtractor` is a plain const class (testable with a file path
  or, in tests, `tiny_png.dart` hand-encoded PNGs).

### 2.3 Contrast / accessibility — `artwork_contrast.dart`

Static utilities implementing WCAG 2.x relative luminance and contrast ratio:

- `relativeLuminance`, `contrastRatio` (4:4:4 sRGB with the standard channel
  curves), `foregroundFor`, `ensureContrast(foreground, background, minRatio)`
  (monotonic darken/lighten to the target ratio), plus `desaturate`,
  `brightness`, `blend`, `darken`, `lighten`.

Both `onSurface` and `onAccent` in extracted palettes are computed with
`_readableForeground`, guaranteeing **≥ 3:1 contrast** against their
background — text on dynamic colors stays legible.

### 2.4 Cache — `artwork_palette_cache.dart`

Two layers, applied in order (in-memory prevents disk entirely on the hot path):

- **Memory**: fixed-capacity LRU (`memoryCap = 96`). `getSync` is sync so the
  common repeated-track case never awaits disk.
- **Disk**: JSON files under `<support>/palettes/`, named
  `palette_{paletteAlgorithmVersion}_{key}.json`.

Cache key = SHA-256 (from `package:crypto`, already a repo dependency) of
`path|size|mtimeMillis`, truncated to 24 hex chars. Corruption/version change →
re-extract; partial/bad JSON is dropped rather than thrown.

### 2.5 Service — `artwork_palette_service.dart`

`ArtworkPaletteService.resolve(ArtworkDescriptor)` orchestrates:

1. Bump the **monotonic generation** (synchronously, before any await) and
   snapshot its token.
2. If no artwork (`hasArtwork == false`) or the file doesn't exist → `null` (the
   controller then falls back immediately).
3. Compute cache key → `getSync` (memory) → `get` (disk) → extract → `put`.
4. Return `ArtworkPaletteResult { palette, generation, fromCache }`.
5. `isCurrent(token)` is checked by the caller *after* awaiting; a stale token
   means the palette is dropped.

`cancelPending()` bumps the generation so in-flight work can never publish
after the track was cleared or replaced. Extraction is fully asynchronous and
never touches playback.

### 2.6 Theme bridging — `artwork_palette_factory.dart`

```
Base Theme + Optional Dynamic Artwork Palette = Effective player styling
```

`ArtworkPaletteTheme.resolveForTheme(extracted, {palette, isDark, oled})`:

- `extracted == null` → `buildThemeFallback(palette, ...)`: a complete,
  deterministic `ArtworkPalette` derived from the theme ramp (accent =
  `primary` in dark, `lightDeep` in light; OLED uses `surfaceLow` for
  `surfaceVariant`). `onAccent` = white when its contrast vs `accent` ≥ 3.0,
  otherwise `ensureContrast(foregroundFor(accent), accent, 3.0)`.
- `oled` + extracted palette → `extracted.withTrueBlackSurfaces()`: surfaces /
  background become pure black while artwork accents are kept. Dynamic colors
  never trample the OLED true-black canvas.
- otherwise → the extracted palette is used as-is (theme-independent).

### 2.7 Provider / controller — `artwork_palette_provider.dart`

Riverpod integration under `lib/features/player/presentation/providers/`.

- `artworkPaletteProvider` watches `currentTrackProvider` and
  `refreshForThemeOrBrightnessSelector`; whenever the current `SongRef` (or
  theme / brightness) changes it re-resolves.
- `ArtworkPaletteController` holds the async state model:
  - state: `status (extracting | ready)`, `palette`, `basePalette`
    (theme-independent extracted palette), `previousPalette`, the descriptor's
    `songIdentityKey`, the artwork cache key, and `isFallback`.
  - `setCurrentArtwork(...)` / `_extract(...)` implement the stale guard: the
    controller captures `final pending = _service.resolve(...)` and
    `final token = _service.generation` **before** awaiting, then after the
    await only applies the result when `_service.isCurrent(token)` and the
    descriptor still matches.
  - `cancelPending()` on track-clear / no-artwork paths.
  - `refreshForThemeOrBrightness` re-applies theme fallback / OLED rules on an
    already-extracted `basePalette` without a re-extract.
- Fallbacks are never painted as "loading": no artwork / extraction failure →
  immediate `buildThemeFallback`.

### 2.8 Files added (V2)

| Path | Purpose |
| --- | --- |
| `lib/core/artwork_palette/artwork_palette.dart` | DTO + JSON + `withTrueBlackSurfaces` |
| `lib/core/artwork_palette/artwork_contrast.dart` | WCAG contrast utilities |
| `lib/core/artwork_palette/artwork_palette_extractor.dart` | 64x64 downscale + ramp analysis |
| `lib/core/artwork_palette/artwork_palette_cache.dart` | memory LRU + disk JSON |
| `lib/core/artwork_palette/artwork_palette_service.dart` | orchestration + race guard |
| `lib/core/artwork_palette/artwork_palette_factory.dart` | theme / OLED fallback bridge |
| `lib/features/player/presentation/providers/artwork_palette_provider.dart` | Riverpod wiring |
| `test/artwork_*_test.dart` + `test/fakes/tiny_png.dart` | 107 palette tests |

---

## 3. Performance & safety invariants

1. **Cache-first**: a repeated track costs one sync map lookup. Disk is only
   reached on memory miss; extraction only on cold cache.
2. **64x64 analysis** (`paletteAnalysisWidth = 64`): extraction is bounded and
   cheap even for full-res artwork; already-decoded artwork is upscaled
   down, never up.
3. **Race-safe**: generation tokens make late song-A results inert after a
   skip to song B. Null results carry no token and can only fall back once.
4. **Never touches playback**: extraction runs on the isolate/async path, off
   the audio loop and off the UI frame.
5. **No new external dependencies**: uses `crypto` (already present), `dart:ui`,
   and `path_provider` (already present).

## 4. Test coverage summary (V2)

- `artwork_contrast_test.dart` — luminance, ratio, ensureContrast monotonicity
  and min-3.0 guarantees, blend/darken/lighten.
- `artwork_palette_model_test.dart` — JSON round-trip, version pinning
  (`paletteAlgorithmVersion == 1`), `withTrueBlackSurfaces` true-black for OLED.
- `artwork_palette_cache_test.dart` — key stability/change on content vs size,
  memory-hit avoids disk, disk round-trip, corrupt JSON dropped, LRU eviction.
- `artwork_palette_extractor_test.dart` — real 64x64 decoding from
  hand-encoded `tiny_png` fixtures, deterministic slots, onAccent/onSurface
  ≥ 3:1.
- `artwork_palette_service_test.dart` — cache fast-paths, extraction path with
  `sourceArtworkKey`, no-artwork → null, generation bump on `cancelPending`.
- `artwork_palette_provider_test.dart` — scripted-service races (stale Song A
  after Song B, track-cleared drops in-flight), immediate fallback for
  no-artwork, extraction-failure fallback, theme-switch rebuild, dark/light
  ramp derivation, OLED true-black preservation; provider wiring with a real
  temp PNG and descriptor change via `container.updateOverrides`.
- `artwork_palette_factory_test.dart` — all 9 presets × dark/light fallback
  determinism, accent identity, OLED rules, `resolveForTheme` behavior.

Full suite: **874 tests pass** (107 palette + 767 pre-existing).

## 5. Validation (V2)

- `flutter analyze`: **0 errors, 0 warnings** in new code. Remaining issues are
  pre-existing info-level lints (repo-wide style) and one pre-existing
  `unused_import` in `smart_mixes_screen.dart`.
- `flutter test`: all green (874).
- `flutter build apk --debug` succeeds (no new dependencies surfaced at build
  time).

## 6. Privacy

Palette analysis is carried out **on-device only**: image bytes are decoded and
analyzed locally; nothing (artwork, extracted data, or cache contents) leaves
the device; no analytics or network calls are added.
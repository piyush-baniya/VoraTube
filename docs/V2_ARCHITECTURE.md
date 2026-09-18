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
                | ArtworkPaletteCache (memory LRU 96 + bounded disk)  |
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
        ArtworkContrast (WCAG 2.x relative luminance, AA 4.5 / graphs 3.0)
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

**Where the work actually runs (audit result).** Image *decode* is async and is
performed by the Flutter engine on its own raster/decode worker threads — it is
never pure Dart on the app isolate. The *pixel analysis* (`analyzeRgba`) is pure
Dart CPU that runs on the app (root) isolate after `toByteData` resolves. It is
deliberately tiny: `maxAnalysisPixels = 64 * 128 = 8192` with
`minSolidPixels = 48`, so the synchronous pass is microseconds and bounded even
for full-resolution covers. This is accurate but nuanced: "async" ≠ "background
isolate". No `Isolate.spawn`/`compute` worker is used (copying an up-to-8k-pixel
buffer across an isolate would cost more than the analysis itself); the engine-side
decode already moves the heavy work off the Dart thread.

**Resource disposal.** Every exit path of `extractFromBytes` disposes both the
`ui.Codec` and the decoded `ui.Image` in a `finally` (image is released even when
`toByteData` throws or geometry checks reject the frame), so repeated extraction
never leaks native image handles.

### 2.3 Contrast / accessibility — `artwork_contrast.dart`

Static utilities implementing WCAG 2.x relative luminance and contrast ratio:

- `relativeLuminance`, `contrastRatio` (4:4:4 sRGB with the standard channel
  curves), `foregroundFor`, `ensureContrast(foreground, background, minRatio)`
  (monotonic darken/lighten to the target ratio), plus `desaturate`,
  `lightness`, `hue`, `saturation`, `blend`, `darken`, `lighten`.

Semantic contrast goals (`ArtworkContrast.readableForeground`) use a two-tier
model so the palette never guesses:

- `normalTextMinRatio = 4.5` — WCAG AA normal-text bar; `onSurface` is always
  resolved against this with no relaxation.
- `largeTextAndUiMinRatio = 3.0` — WCAG AA large-text / graphical-object bar;
  `onAccent` targets 4.5 as a *preferred* ratio and relaxes to 3.0 only when the
  accent color cast physically cannot reach 4.5 (a mid-luminance saturated hue
  where even pure black/white cannot clear 4.5).

`readableForeground` always rescues toward black/white (the maximum-contrast hue
family) and never returns a mid-luminance compromise that fails both goals. The
theme fallback (`buildThemeFallback`) uses the same helper for `onAccent`, so
production themes and OLED surfaces share the guarantee. The factory fallback's
`onSurface` is `ramp.textPrimary`, which theme curation keeps ≥ 4.5:1.

### 2.4 Cache — `artwork_palette_cache.dart`

Two layers, applied in order (in-memory prevents disk entirely on the hot path):

- **Memory**: fixed-capacity LRU (`memoryCap = 96`). `getSync` is sync so the
  common repeated-track case never awaits disk.
- **Disk**: versioned JSON files under `<support>/palettes/`, named
  `palette_{paletteAlgorithmVersion}_{key}.json`. The disk layer is **bounded**:
  after every `diskSweepInterval` (32) disk writes it lazily enforces a
  `diskCap` (384 files) by deleting the oldest files first — side-effect-batched
  during normal writes, never a full-directory scan on every startup.

**Why the cache key is sufficient (audit result).** The key is SHA-256 of
`path|size|mtimeMillis` (truncated 24 hex). All artwork actually reaches this
engine through content-addressed or write-once paths, so `path|size|mtime` is a
faithful content identity:

- Imported/embedded/custom artwork goes through `LocalArtworkStore`, which stores
  files *keyed by the SHA-256 of their bytes* (`sha256(bytes)[:24]`), unique per
  content. Two different covers always have different paths; identical covers
  reuse one palette entry.
- Android MediaStore artwork is materialized by the native bridge under
  `<filesDir>/art/` as `$safeKey$<SMALL|LARGE>_SUFFIX.webp`; `resolveSingleArtwork`
  short-circuits when those files already exist, so a path never silently holds
  different content over time — a changed cover produces a new key/path.

A same-size, same-path in-place cover rewrite that also preserves mtime is not an
organic production scenario given both writers above; the key keeps
`path` so a genuine file replacement with a bumped mtime still invalidates.
Song/album names are deliberately excluded (they can collide and are not what
the artwork *is*).

Corruption/version change → re-extract; partial/bad JSON (truncated, non-map,
wrong slot types) is dropped rather than thrown, and only the offending file is
removed — a neighbour entry is never invalidated. A bump of
`paletteAlgorithmVersion` makes every old file a miss; `pruneStaleVersions()`
reclaims the space.

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
after the track was cleared or replaced. Extraction is fully asynchronous: it
never blocks the widget tree or playback; the bounded analysis pass is detailed
above in section 2.2.

### 2.6 Theme bridging — `artwork_palette_factory.dart`

```
Base Theme + Optional Dynamic Artwork Palette = Effective player styling
```

`ArtworkPaletteTheme.resolveForTheme(extracted, {palette, isDark, oled})`:

- `extracted == null` → `buildThemeFallback(palette, ...)`: a complete,
  deterministic `ArtworkPalette` derived from the theme ramp (accent =
  `primary` in dark, `lightDeep` in light; OLED uses `surfaceLow` for
  `surfaceVariant`). `onAccent` prefers white ≥ 4.5; when that is unreachable
  it uses `readableForeground(accent, min: 3.0, preferred: 4.5)`.
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

**Lifecycle (audit result).** `currentArtworkPaletteProvider` is a non-autoDispose
`StateNotifierProvider`: the controller (and the cache-backed service) lives for
the whole `ProviderContainer`/app lifetime, so shared Full Player, Mini Player
and queue consumers all see one consistent palette and a track change never
recreates the engine. `currentArtworkDescriptorProvider` is a narrow derived
provider (SongRef → `ArtworkDescriptor`) so it reacts to the artwork identity
only — never play/pause/position. `_extract` fires only when the descriptor
actually changes (`ref.listen` equality), so a theme switch does not re-extract.
Late writes after any `await` are double-guarded by `_service.isCurrent(token)`
(stale track) and `mounted` (provider disposed while the future was in flight),
so a mid-extraction container teardown can never publish to a disposed state.

### 2.8 Files added (V2)

| Path | Purpose |
| --- | --- |
| `lib/core/artwork_palette/artwork_palette.dart` | DTO + JSON + `withTrueBlackSurfaces` |
| `lib/core/artwork_palette/artwork_contrast.dart` | WCAG contrast utilities |
| `lib/core/artwork_palette/artwork_palette_extractor.dart` | 64x64 downscale + ramp analysis |
| `lib/core/artwork_palette/artwork_palette_cache.dart` | memory LRU + bounded disk JSON |
| `lib/core/artwork_palette/artwork_palette_service.dart` | orchestration + race guard |
| `lib/core/artwork_palette/artwork_palette_factory.dart` | theme / OLED fallback bridge |
| `lib/features/player/presentation/providers/artwork_palette_provider.dart` | Riverpod wiring |
| `test/artwork_*_test.dart` + `test/fakes/tiny_png.dart` | 107 palette tests |

---

## 3. Performance & safety invariants

1. **Cache-first**: a repeated track costs one sync map lookup. Disk is only
   reached on memory miss; extraction only on cold cache.
2. **Bounded 64x64 analysis** (`paletteAnalysisWidth = 64`, hard
   `maxAnalysisPixels = 8192`): extraction is bounded and cheap even for
   full-res artwork; artwork is downscaled, never upscaled. Decode happens on
   the engine's decode workers; the pure-Dart analysis pass is a few
   microseconds on the app isolate.
3. **Race-safe**: generation tokens make late song-A results inert after a
   skip to song B. Null results carry no token and can only fall back once.
4. **Lifecycle-safe**: `_extract` post-await writes are guarded by both the
   service generation token and a `mounted` check, so a disposed container can
   never receive a state write.
5. **Never touches playback**: extraction never blocks the widget tree or the
   audio loop (see 2.2 for the accurate worker picture).
6. **No new external dependencies**: uses `crypto` (already present), `dart:ui`,
   and `path_provider` (already present).
7. **Bounded disk cache**: at most `diskCap` (384) palette files, swept
   oldest-first on a lazy schedule during writes — the cache cannot grow without
   bound over months of playback.

## 4. Test coverage summary (V2)

- `artwork_contrast_test.dart` — luminance, ratio, ensureContrast monotonicity,
  semantic-ratio constants, two-tier `readableForeground` (AA 4.5 map on
  `onSurface`, 4.5-preferred / 3.0-min on `onAccent`), blend/darken/lighten.
- `artwork_palette_model_test.dart` — JSON round-trip, version pinning
  (`paletteAlgorithmVersion == 1`), `withTrueBlackSurfaces` true-black for OLED.
- `artwork_palette_cache_test.dart` — key stability/change on content vs size,
  memory-hit avoids disk, disk round-trip, corrupt/truncated/non-map/wrong-typed
  JSON dropped without affecting neighbours, LRU eviction, disk-cap sweeps
  (oldest-first, lazy while-writing, no-op under cap).
- `artwork_palette_extractor_test.dart` — real 64x64 decoding from
  hand-encoded `tiny_png` fixtures, deterministic slots, onSurface ≥ 4.5,
  onAccent ≥ 3.0 (4.5-preferred), and color-quality edge cases: near-black,
  near-white, white/black canvas with a tiny saturated object, saturated red,
  neon green, pale pastel, transparent-with-tiny-opaque rejection, single-color.
- `artwork_palette_service_test.dart` — cache fast-paths, extraction path with
  `sourceArtworkKey`, no-artwork → null, generation bump on `cancelPending`.
- `artwork_palette_provider_test.dart` — scripted-service races (stale Song A
  after Song B, track-cleared drops in-flight), immediate fallback for
  no-artwork, extraction-failure fallback, theme-switch rebuild, dark/light
  ramp derivation, OLED true-black preservation; provider wiring with a real
  temp PNG and descriptor change via `container.updateOverrides`.
- `artwork_palette_factory_test.dart` — all 9 presets × dark/light fallback
  determinism, accent identity, OLED rules, `resolveForTheme` behavior.

Full suite: **874+ tests pass** (107+ palette + 767 pre-existing).

## 5. Android release signing (V2)

The V2 branch keeps the production signing posture of `main` and adds a hard
failure guard:

- **Debug / dev builds** never require the upload keystore: no
  `key.properties`, no `upload-keystore.jks` → `signingConfigs.release` is not
  created at all, `buildTypes.release` has no `signingConfig`, and debug builds
  build normally.
- **Production release** uses the real VoraTube upload keystore exactly as before.
- **Missing-config release offset**: a `gradle.taskGraph.whenReady` guard fails
  the build with a clear message ("Release signing configuration is missing.
  Configure key.properties and the upload keystore before building a production
  release.") whenever any release packaging task (`bundleRelease`,
  `assembleRelease`, `packageRelease*`, `bundleRelease*`) is scheduled without a
  valid `hasReleaseKeystore`. A release can never silently fall back to the
  debug key.
- `key.properties` and `*.jks` stay gitignored; credentials never enter the repo.

**Validating release from a second worktree.** The V2 worktree deliberately has
no signing credentials checked out. To do a production-signing validation build
there, copy the gitignored files from a checkout that holds them (they are not
committed anywhere):

```
copy android\key.properties        <v2-worktree>\android\
copy android\upload-keystore.jks   <v2-worktree>\android\
```

then run `flutter build appbundle --release`. Both files are gitignored in the
worktree, so the validation never pollutes the diff. Remove them afterwards if
desired.

## 6. Side-by-side V2 development install

V2 can be installed next to the Play (production) build for on-device testing.

**Strategy — debug build type, not product flavors.** `flutter run` and
`flutter build apk --debug` target the `debug` build type by default, so a
single `applicationIdSuffix` on `debug` gives a side-by-side install with no
`--flavor` flag and no change to the production package, namespace or release
signing. A flavor would force every command to opt in and would multiply the
release variant matrix.

| Property        | Debug (V2 Dev)                     | Release (production)          |
| --------------- | ---------------------------------- | ----------------------------- |
| `applicationId` | `com.piyushbaniya.vora_tube.v2dev` | `com.piyushbaniya.vora_tube`  |
| versionName     | `1.2.3-v2dev` (Flutter versionName + `-v2dev`) | `1.2.3` (unchanged) |
| versionCode     | 24 (same as production)            | 24 (unchanged)                |
| App label       | `VoraTube V2 Dev`                  | `VoraTube`                    |
| AdMob app ID    | Google sample test ID              | VoraTube production app ID    |

- **App label** comes from the `appLabel` manifest placeholder
  (`AndroidManifest.xml` uses `android:label="${appLabel}"`): `defaultConfig`
  sets `VoraTube`, `debug` overrides it with `VoraTube V2 Dev`.
- **Data isolation** is automatic: a distinct `applicationId` gives V2 Dev its
  own support directory, Drift database, SharedPreferences, artwork/palette
  caches, notification settings and premium/rewarded state. Uninstalling V2 Dev
  never touches production data, and vice versa.
- **Launcher icon** is reused from production; the visible app name is the
  on-device disambiguator. A DEV badge is an optional, non-blocking polish.
- **AdMob** needs no per-build-type wiring: every unit ID is centralized in
  `lib/features/ads/ads_config.dart`, where `VoraTubeAds.useTestAds` is
  `kDebugMode` — debug resolves to Google's official test units and the manifest
  `admobAppId` defaults to the sample test App ID, while release resolves to the
  production units and app ID.

**Firebase.** `google-services.json` and `firebase_options.dart` register only
the production package, and no `com.piyushbaniya.vora_tube.v2dev` client
exists yet. Rather than fabricate credentials, both layers skip Firebase for the
dev variant:

- Gradle: `tasks.matching { it.name == "processDebugGoogleServices" }` is
  disabled, so the plugin does not fail the debug build with "no matching
  client". Release and profile variants keep the production client.
- Dart: `lib/main.dart` skips `Firebase.initializeApp` when the runtime package
  name matches `com.piyushbaniya.vora_tube.v2dev` (`lib/core/app_variant.dart`),
  so development activity is never attributed to the production Firebase app.
  Failures resolve to production (analytics enabled), the safe default.

To enable analytics for V2 Dev later: register `com.piyushbaniya.vora_tube.v2dev`
as a second Android app in the Firebase project, download the updated
`google-services.json` (with both clients), add the dev `FirebaseOptions` to
`firebase_options.dart`, then remove the `processDebugGoogleServices` guard.

**Native audit (no collisions).**

- No `FileProvider`, `<provider>` or custom authority is declared, so there is
  nothing to suffix.
- Method channels (`VoraTube*Bridge`) and the audio-service notification channel
  (`voratube.playback`) are app-internal names; Android scopes channels and media
  sessions per package, so both installs stay isolated. Channel names are not
  renamed.
- The only intent filters are `MAIN/LAUNCHER`, `MediaBrowserService` and
  `MEDIA_BUTTON`; there are no deep-link `<data>` schemes or hosts.
- `android:taskAffinity=""` on `MainActivity` is unchanged.

**Build commands.**

```
flutter run                          # debug → installs VoraTube V2 Dev
flutter build apk --debug            # side-by-side dev artifact
flutter build appbundle --release    # production (requires upload keystore)
```

## 7. Validation (V2)

- `flutter analyze`: **0 errors, 0 warnings** in new code. Remaining issues are
  pre-existing info-level lints (repo-wide style) and one pre-existing
  `unused_import` in `smart_mixes_screen.dart`.
- `flutter test`: all green.
- `flutter build apk --debug` succeeds and produces
  `applicationId=com.piyushbaniya.vora_tube.v2dev`, `versionName=1.2.3-v2dev`,
  label `VoraTube V2 Dev`.
- Release: builds only with the upload keystore present; fails fast otherwise.
  Verified `applicationId=com.piyushbaniya.vora_tube`, `versionName=1.2.3`,
  label `VoraTube`, production AdMob app ID, signed by the VoraTube upload cert.

## 8. Privacy

Palette analysis is carried out **on-device only**: image bytes are decoded and
analyzed locally; nothing (artwork, extracted data, or cache contents) leaves
the device; no analytics or network calls are added.
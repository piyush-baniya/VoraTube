# VoraTube

A modern, privacy-friendly, **local-first** music player for **Android and iOS**, built with Flutter.

VoraTube plays music that already belongs to the user. It has **no backend**, performs **no
online music search or streaming**, and never uploads user data. The only planned online
feature is lyrics retrieval (a later phase), which must degrade gracefully and never affect
playback.

---

## Project Status

| Phase | Scope | State |
|---|---|---|
| 0 | Scaffold: deps, theme, 4-tab shell, lint gates, minSdk 24, display names | ✅ Done |
| 1 | Android ingestion: MediaStore MethodChannel → chunked batches → Drift → artwork thumbnails; incremental scanning; runtime permissions | ✅ Done (verified on device) |
| 2 | iOS import pipeline: file_picker → sandbox copy → metadata/artwork extraction → Drift; duplicate prevention; reconciliation | ✅ Done (code + unit-tested; needs Mac/device run) |
| 3 | Playback foundation: `PlayerController` abstraction, `just_audio` + `audio_service` + `audio_session`, background/lock-screen/BT controls, queue persistence, gapless queue engine | ✅ Done |
| 4 | Library experience & local search: Songs/Albums/Artists/Genres browsing, favorites, sorting, pagination, debounced local search, visual identity rework | ✅ Done |
| 5 | Playlists & collections: full CRUD, playlist detail, add-to-playlist sheet, song-tile menu, collections strip (Favorites/Recently Added/Most Played/Recently Played), playback stats recording | ✅ Done |
| 6 | Full-screen player: premium immersive UI, large artwork with Hero transitions, progress slider, playback controls, queue bottom sheet, favorite toggle, MiniPlayer navigation | ✅ Done |
| 7 | Visual polish & design system: tokens, premium component redesign, smooth animations, consistent spacing/typography, PressableScale, refined empty states | ✅ Done |
| 8 | Online lyrics: LRCLIB integration, LRC parser, embedded lyrics extraction, cache, synced lyrics UI with auto-scroll | ✅ Done |
| 8.1 | Lyrics reliability: LRC metadata filtering, text normalization, match verification, HTTP timeout, search fallback, ValueNotifier position tracking, user-scroll detection, no nested scrollables | ✅ Done |
| Next | Smart mixes, settings redesign, lyrics polish | Planned |

---

## Architecture Overview

Layered, feature-first. Widgets render state and dispatch intents only; business logic
lives in controllers/repositories/providers.

```
lib/
├── main.dart                     # Bootstrap: DB → repository → player → ProviderContainer
├── app/
│   ├── app.dart                  # MaterialApp root (VoraTubeApp)
│   ├── home_shell.dart           # IndexedStack 4-tab shell + MiniPlayer slot
│   └── theme/
│       ├── app_colors.dart       # VoraTube palette (dark-first, restrained rose accent)
│       ├── app_theme.dart        # Material 3 ThemeData builders (dark/light) + typography
│       └── app_tokens.dart       # Design tokens: spacing, radius, animation, shadows, sizes
├── core/
│   ├── db/
│   │   ├── tables.dart           # Drift table definitions (+ @TableIndex declarations)
│   │   └── app_database.dart     # @DriftDatabase, schemaVersion 2, v1→v2 migration
│   ├── ingest/
│   │   ├── ingest_service.dart   # Platform-agnostic IngestService contract + value types
│   │   ├── android/
│   │   │   └── android_ingest_service.dart     # MethodChannel client for MediaStore bridge
│   │   ├── ios/
│   │   │   ├── ios_ingest_service.dart         # picker → copy → isolate worker orchestration
│   │   │   └── import_worker.dart              # top-level isolate fn: stream-copy+SHA-256+metadata
│   │   ├── metadata/
│   │   │   └── metadata_reader.dart            # MetadataReader interface + audio_metadata_reader impl
│   │   └── artwork/
│   │       └── local_artwork_store.dart        # content-keyed two-tier artwork saver (import path)
│   ├── permissions/
│   │   └── permission_service.dart             # READ_MEDIA_AUDIO / legacy storage mapping
│   ├── player/
│   │   ├── player_controller.dart              # PlayerController iface, SongRef, PlayerSnapshot,
│   │   │                                       #   QueueSnapshot JSON, RepeatMode, persistence iface,
│   │   │                                       #   currentQueue getter, PlaybackStatsSink typedef
│   │   └── just_audio_controller.dart          # BaseAudioHandler impl (the entire audio engine);
│   │                                           #   stats batch recording, currentQueue snapshot copy
│   └── utils/
│       └── string_utils.dart                   # filename-title fallback, format detection
├── features/
│   ├── library/
│   │   ├── data/
│   │   │   ├── library_repository.dart         # ONLY Drift accessor: sync, pages, overviews,
│   │   │   │                                   #   favorites, search, KV, reconciliation,
│   │   │   │                                   #   CollectionQueries (collectionSongs, count,
│   │   │   │                                   #   rowIdsByIdentityKeys, recordPlayback)
│   │   │   ├── library_scanner.dart            # Pull-scan orchestrator (MediaStore flow)
│   │   │   ├── library_models.dart             # SongPage/SongTileData/AlbumSummary/etc.
│   │   │   └── song_ref_mapper.dart            # Drift rows → SongRef / PlayContext
│   │   └── presentation/
│   │       ├── providers/
│   │       │   ├── library_providers.dart      # DB/repo/scanner providers, ScanController state
│   │       │   └── library_view_providers.dart # Section/sort/filters, PagedSongsController,
│   │       │                                   #   favorite ids, overview providers, refresh tick,
│   │       │                                   #   pagedSongsForCollection (collection drill-down)
│   │       ├── screens/
│   │       │   ├── library_screen.dart         # Section pills + Songs/Albums/Artists/Genres views
│   │       │   │                               #   + CollectionsStrip at top of Songs view
│   │       │   └── filtered_songs_screen.dart  # Album/artist/collection drill-down with Play-all
│   │       └── widgets/                        # song_tile, section_selector, library_tiles,
│   │                                           #   sort_sheet
│   ├── player/presentation/
│   │   ├── providers/player_providers.dart     # playerProvider (override-injected), snapshot &
│   │   │                                       #   position streams, DriftPlayerPersistence,
│   │   │                                       #   PlaybackStatsBuffer, songRowIdProvider,
│   │   │                                       #   currentSongIsFavoriteProvider
│   │   ├── screens/
│   │   │   └── full_player_screen.dart         # Immersive full-screen player: artwork, metadata,
│   │   │                                       #   controls, progress, queue access, favorite toggle
│   │   └── widgets/
│   │       ├── mini_player.dart                # Compact bar above nav; Hero artwork + tap → full player
│   │       ├── player_artwork.dart             # Large artwork: Hero, AnimatedSwitcher, fallback gradient
│   │       ├── player_controls.dart            # Play/pause/prev/next/shuffle/repeat; press animation
│   │       ├── player_progress.dart            # Seekable slider + time labels; high-freq rebuild only here
│   │       └── queue_sheet.dart                # DraggableScrollableSheet queue with swipe-to-remove
│   ├── search/presentation/
│   │   ├── providers/search_providers.dart     # Debounced query (250 ms) + results provider
│   │   └── screens/search_screen.dart          # Local grouped results incl. playlist taps
│   ├── playlists/
│   │   ├── data/
│   │   │   ├── playlist_models.dart            # PlaylistSummary, exception types
│   │   │   └── playlist_repository.dart        # PlaylistRepository: CRUD, songsOf, covers,
│   │   │                                       #   reorder, max-position, batch removal
│   │   └── presentation/
│   │       ├── providers/
│   │       │   └── playlist_providers.dart      # PlaylistRepository, playlistSummariesProvider,
│   │       │                                   #   PlaylistDetailController (AsyncNotifier)
│   │       ├── screens/
│   │       │   ├── playlists_screen.dart        # Overview: pinned/unpinned, create, swipe-delete
│   │       │   └── playlist_detail_screen.dart  # Header, songs, play/shuffle/reorder/pin/delete
│   │       └── widgets/
│   │           ├── add_to_playlist_sheet.dart   # Bottom sheet: membership check, toggle, create
│   │           └── playlist_collage.dart        # 1/2/3/4 mosaic artwork grid
│   ├── settings/presentation/                  # Shell only
│   └── collections/presentation/
│       ├── providers/
│       │   └── collections_providers.dart       # CollectionSummary, collectionSummariesProvider,
│       │                                       #   collectionSongsProvider, Collections class
│       └── widgets/
│           └── collections_strip.dart           # Horizontal card strip (Favorites, Recently Added,
│                                               #   Most Played, Recently Played)
└── shared/
    └── widgets/                                # empty_state, screen_header, artwork_view,
                                                #   skeleton_list, transitions, pressable_scale
```

Platform-native code:

```
android/app/src/main/
├── AndroidManifest.xml                          # media permissions, FGS mediaPlayback service,
│                                                #   MediaButtonReceiver
└── kotlin/com/piyushbaniya/vora_tube/
    ├── MainActivity.kt                          # extends AudioServiceActivity; registers bridge
    └── ingest/VoraTubeIngestBridge.kt           # MediaStore keyset queries, genre map,
                                                 #   native thumbnail generation (256px/512px WebP)

ios/Runner/Info.plist                           # No music permission strings by design
```

---

## Data Flow

### Android ingestion (pull model)

```
Permission granted (READ_MEDIA_AUDIO / ≤API32 storage)
  └─> LibraryScanner.scan()
        ├─ IngestService.prepareScan()          (native resets caches)
        ├─ getAudioBatch(afterId, ≤500) loop    (keyset pagination on _id, is_music != 0)
        │     └─ Dart diff vs stored (mediaStoreId→dateModified) → only changed go to
        │        repository.syncTracks() inside a transaction (~500/batch)
        ├─ removeAbsentMediaStore(seenIds)      chunked deletes + orphan album/artist cleanup
        ├─ resolveArtwork(albumKeys) chunks     native decode→WebP tiers in files/art/
        └─ completeScan(totalSongs) → scan_states
```

### iOS import (push model)

```
FilePicker.pickFiles(audio, multiple)
  └─ per file: Isolate.run(processPickedImportFile)
        ├─ extension allow-list gate (OGG excluded by policy)
        ├─ streamed copy temp → Documents/Library/<uuid>/<name>
        │     SHA-256 computed over the same stream (single pass)
        ├─ MetadataReader.read() (audio_metadata_reader, pure Dart)
        └─ returns ProcessedImport{IngestTrack, artworkBytes}
  └─ main isolate: hash-dedupe vs DB index → batched syncTracks()
     → LocalArtworkStore.save(bytes) keyed by art-content-hash
  └─ reconcileMissingFiles(): DB paths not present on disk are removed
```

### Playback

```
UI ──▶ PlayerController (interface)
        └─ JustAudioController extends BaseAudioHandler
              ├─ just_audio AudioPlayer: setAudioSources(...)  ⇒ gapless queue
              ├─ shuffle (DefaultShuffleOrder) · LoopMode off/all/one
              ├─ audio_session: .music(), interruption duck/pause/resume,
              │   becoming-noisy pause
              ├─ audio_service: MediaItem/queue/playbackState broadcast
              │   ⇒ notification · lock screen · Bluetooth · wearables
              ├─ persistence: debounced QueueSnapshot JSON → kv table
              │   (restored paused at last index+position on next launch)
              └─ stats: onCurrentIndexChanged → PlaybackStatsBuffer batch
                  (20 events or 5s interval → libraryRepository.recordPlayback)
```

Position updates travel on a dedicated throttled stream
(`createPositionStream`, 200 ms–1 s). Only progress widgets subscribe;
coarse `PlayerSnapshot` emits strictly on meaningful changes.

---

## Database (Drift / SQLite, schemaVersion 3)

Tables: `songs` · `albums` · `artists` · `song_stats` · `playlists` ·
`playlist_songs` · `kv_entries` · `scan_states` · `lyrics_cache`

Key columns:

- `songs.source` — `'mediastore' | 'imported'`
- `songs.media_store_id` (nullable, Android) / `songs.content_hash` (nullable, iOS SHA-256)
- unique `(source, media_store_id)` and `(source, content_hash)`
- `albums.album_key` / `artists.artist_key` — cross-platform identity:
  `'ms:<id>'` (Android) or `'n:'/'a:' + name-hash` (iOS); UNIQUE indexed
- `albums.art_small_path` / `art_large_path` — artwork tiers; `''` sentinel = attempted-missing

Indexes: `songs(album_row_id)` · `songs(artist_row_id)` · `songs(title_search)` ·
`songs(date_added_sec)` · `playlist_songs(playlist_id, position) UNIQUE` · plus keys above.

Migration v1→v2 (`app_database.onUpgrade`): adds new columns via `TableMigration`,
then backfills `album_key='ms:'||media_store_album_id`. Verified by
`test/migration_test.dart`.

Migration v2→v3: adds `lyrics_cache` table for online lyrics persistence.

Genres intentionally have **no table**: derived via indexed `GROUP BY songs.genre`.

The play queue is a JSON snapshot in `kv_entries`, not a relational table.

---

## Player Architecture (Phase 6)

The full-screen player follows a **separated-frequency architecture** to ensure 60fps
during playback:

### State Isolation

| Provider | Frequency | What rebuilds |
|---|---|---|
| `playbackSnapshotProvider` | Low (track changes, mode toggles) | Song metadata, controls, artwork, favorite |
| `playbackPositionProvider` | High (~200ms–1s ticks) | ONLY `PlayerProgress` widget |

The full player screen watches `playbackSnapshotProvider` for coarse state.
Only the nested `_PositionConsumer` subscribes to `playbackPositionProvider`.
This means artwork, title, artist, controls, and favorite button NEVER rebuild
on position ticks — they only rebuild when the track or mode actually changes.

### File Responsibilities

| File | Responsibility |
|---|---|
| `full_player_screen.dart` | Top-level composition: SafeArea, LayoutBuilder, responsive
  artwork sizing, scroll view, empty state. Uses `AnnotatedRegion` for
  transparent status/nav bar. |
| `player_artwork.dart` | Hero-tagged large artwork with `AnimatedSwitcher` cross-fade
  on song change. Fallback: gradient + decorative rings + icon.
  Box shadows for depth. |
| `player_controls.dart` | Playback controls row: shuffle, prev, play/pause (hero
  button with scale animation), next, repeat. Disabled states at
  queue boundaries (unless repeat-all). |
| `player_progress.dart` | Seekable slider + time labels. Local `StatefulWidget` manages
  drag state internally. Custom `_RoundedTrackShape` for visual polish. |
| `queue_sheet.dart` | `DraggableScrollableSheet` bottom sheet with drag handle,
  song count header, swipe-to-remove `Dismissible`, current-song
  highlight with equalizer icon. |
| `mini_player.dart` | Compact 64px bar. Taps push `FullPlayerScreen` via a
  fade+slide route. Artwork wrapped in `Hero` for shared transition. |
| `player_providers.dart` | Added `songRowIdProvider` (identityKey → rowId) and
  `currentSongIsFavoriteProvider` (derived favorite state). |

### MiniPlayer → Full Player Transition

Opening the full player uses a custom `PageRouteBuilder` with 400ms fade-out
curve and 320ms reverse. The artwork `Hero` tag (`'player_artwork_hero'`) is
shared between `MiniPlayer._Artwork` and `PlayerArtwork` in the full screen.
The mini player artwork is 48×48; the full screen artwork scales responsively
(between 200–360px) via `LayoutBuilder`.

### Favorite Toggle Flow

1. Full player watches `currentSongIsFavoriteProvider`
2. Provider resolves: `playbackSnapshotProvider` → `current.identityKey`
   → `songRowIdProvider(key)` → `libraryRepository.rowIdsByIdentityKeys`
   → checks `favoriteIdsProvider.contains(rowId)`
3. Heart tap: reads `songRowIdProvider`, calls `favoriteIdsProvider.toggle(rowId)`
4. Optimistic update via `FavoriteIdsController` (rollback on error)

### Artwork Rendering

- `PlayerArtwork` uses `AnimatedSwitcher` (350ms easeOutCubic) to cross-fade
  between songs. The `ValueKey(path)` ensures the switcher detects changes.
- `cacheWidth` set to 2× display size for efficient GPU texture allocation.
- `gaplessPlayback: true` prevents flicker during image decode.
- Fallback shows a gradient surface with three concentric ring decorations
  and a centered album icon — not a bare empty box.

### Queue Sheet

- `DraggableScrollableSheet` with 0.55 initial, 0.3 min, 0.85 max.
- Current song highlighted with primary-colored background + equalizer icon.
- Swipe-to-dismiss removes from queue via `PlayerController.removeAt()`.
- List index numbers shown for non-current items.

---

## Search Implementation

100% local. Uses existing normalized columns (`title_search`, `artist_search`) and
indexed fields — no FTS5 (re-evaluate only if profiling demands it):

- songs: `title LIKE ? OR artist LIKE ? OR album LIKE ?` (case-folded needle `%q%`)
- albums/artists/playlists: lowercased name `LIKE`
- UI debounce: 250 ms (`search_providers.submitSearchText`)
- results grouped: songs (tap = queue from results) · albums/artists (drill-down push) · playlists

---

## Riverpod Provider Map (responsibilities)

| Provider | Responsibility |
|---|---|
| `appDatabaseProvider` | Owns `AppDatabase`; closed on dispose; overridden at bootstrap |
| `libraryRepositoryProvider` | Single repository instance (only Drift caller) |
| `playlistRepositoryProvider` | Single PlaylistRepository instance |
| `ingestServiceProvider` | Android or iOS `IngestService` selection |
| `libraryScannerProvider` | Pull-scan orchestrator |
| `scanControllerProvider` | Android scan UI state machine (permission→ready→running→done/fail) |
| `importControllerProvider` | iOS import UI state machine + reconcile action |
| `playerProvider` | Override-injected `PlayerController` (created in `main`) |
| `playbackSnapshotProvider` | Coarse playback state stream |
| `playbackPositionProvider` | Throttled positions (progress widgets only) |
| `songRowIdProvider` | Maps identityKey → database rowId for favorite toggle |
| `currentSongIsFavoriteProvider` | Derived: is current track a favorite? |
| `librarySectionProvider` / `songSortProvider` / `favoritesOnlyProvider` | View selections |
| `pagedSongsProvider` | Accumulating paginated songs (`loadMore()` on scroll threshold) |
| `albumsOverviewProvider` etc. | Grouped browses; invalidated via `libraryRefreshTickProvider` |
| `favoriteIdsProvider` | Fine-grained favorite set → heart taps repaint one tile |
| `playlistSummariesProvider` | Playlist summaries ordered by pin+name; auto-invalidated on write |
| `playlistDetailProvider` | Playlist detail + songs; invalidated on add/remove/reorder |
| `playlistDetailControllerProvider` | AsyncNotifier: play/shuffle, reorder, rename, pin, delete |
| `collectionSummariesProvider` | Collection card counts (Favorites/Added/Most Played/Recent) |
| `collectionSongsProvider` | Songs inside a collection (family by CollectionKind) |

High-frequency isolation rule: nothing in the library tree listens to
`playbackPositionProvider`.

---

## UI Architecture

- Dark-first AMOLED-friendly neutrals (`#09090B` base) with a single deep-rose accent used
  sparingly; light theme is warm paper-neutral — no pale pink.
- Typography scale tuned (weights 600–800, tightened letter-spacing) on the Material base.
- Shell = `IndexedStack` (Library/Search/Playlists/Settings) + `NavigationBar` +
  `MiniPlayer` docked above nav.
- Library internal navigation = pill `SectionSelector` + `FadeThroughSwitcher`;
  drill-downs use shared-axis push (`pushSharedAxis`).
- Lists are `ListView.builder`/`GridView.builder` with page-ahead loading
  (threshold 600 px), fixed-height tiles, `cacheWidth`-bounded artwork decoding,
  pulsing `SkeletonList` placeholders, and intentional empty states everywhere.
- ≥48 dp targets on all interactive elements; icons carry semantic labels/tooltips.

---

## Android / iOS Differences (by design)

| Concern | Android | iOS |
|---|---|---|
| Source model | MediaStore enumeration (device-wide) | User imports files; VoraTube owns copies |
| Identity | `mediaStoreId` (`'ms:<id>'`) | Content SHA-256 (`'h:<hash>'`) |
| Permissions | `READ_MEDIA_AUDIO` (+legacy ≤32) contextual request | None (document picker) |
| Artwork | Native decode → WebP tiers during scan | Embedded bytes → decoded tiers after import |
| Track source URI | `content://` | `file://` inside sandbox |
| Rescan semantics | Incremental via DATE_MODIFIED + seen-id reconcile | Sandbox walk + missing-path reconcile |

Both implement the single `IngestService` contract; nothing downstream knows the platform.

---

## Phase 7 — Visual Polish & Design System

### Design System (`app_tokens.dart`)

Central source of truth for all visual constants:

- **Spacing scale:** `s0`–`s10` (4px base: 4, 8, 12, 16, 20, 24, 32, 40, 48, 64)
- **Radius scale:** `rXs`–`rXxl` (6, 8, 12, 16, 20, 24)
- **Animation durations:** `fast` (120ms), `normal` (200ms), `medium` (280ms), `slow` (380ms)
- **Curves:** `easeOut` (easeOutCubic), `easeIn` (easeInCubic), `spring` (easeOutBack)
- **Shadows:** `shadowSm`, `shadowMd`, `shadowLg` — factory methods accepting a color
- **Artwork sizes:** `artworkXs` (40), `artworkSm` (48), `artworkMd` (56), `artworkLg` (64), `artworkXl` (120)
- **Touch target:** 48dp minimum

### Color Tokens (`app_colors.dart`)

Expanded with semantic surfaces:
- `cardDark`/`cardElevatedDark` — card backgrounds without touching surface hierarchy
- `dividerDark`/`dividerLight` — subtle dividers
- `borderSubtleDark`/`borderSubtleLight` — thin border accents

### Theme (`app_theme.dart`)

Added component themes for consistency:
- `BottomSheetThemeData` — surface color, 20px top radius
- `DialogThemeData` — raised surface, 20px radius
- `CardThemeData` — card surface, 12px radius, zero elevation
- `ChipThemeData` — subtle border, 8px radius
- `SnackBarThemeData` — 12px radius
- Divider theme refined: 0.5px thickness, token-based colors
- Text scale: tighter letter-spacing on all levels, explicit height on body styles

### Shared Components

| Widget | File | Purpose |
|---|---|---|
| `PressableScale` | `shared/widgets/pressable_scale.dart` | GPU-friendly scale-on-tap feedback via AnimationController + Transform.scale |
| `ArtworkView` | `shared/widgets/artwork_view.dart` | Enhanced with `showShadow` flag, token-based sizing, cleaner fallback |
| `EmptyState` | `shared/widgets/empty_state.dart` | Circular gradient background behind icon, token spacing |
| `SectionLabel` | `shared/widgets/transitions.dart` | Accent-bar indicator + optional trailing widget |
| `ScreenHeader` | `shared/widgets/screen_header.dart` | Token-based padding, tighter letter-spacing |
| `SkeletonList` | `shared/widgets/skeleton_list.dart` | 64px row height matching SongTile, rounded skeleton bars |

### Redesigned Components

| Component | Key Changes |
|---|---|
| `SongTile` | 64px artwork, PressableScale feedback, cleaner popup menu, minimal favorite button |
| `CollectionsStrip` | Gradient overlay cards (152px wide), per-collection accent gradients, border accent |
| `AlbumCard` | PressableScale, artwork shadow, tighter spacing |
| `ArtistTile` | PressableScale, circular artwork, chevron indicator |
| `GenreTile` | Filled background (no border), music note icon, token spacing |
| `SectionSelector` | AnimatedContainer pill, rXl radius, token padding |
| `MiniPlayer` | Top border (0.5px outline), token spacing, 30px play icon |
| `FullPlayerScreen` | s6 horizontal padding, thinner progress track (2.5px), refined metadata spacing |
| `PlayerControls` | 68px play button (down from 72px), 22px shuffle/repeat icons, 20% disabled opacity |
| `PlayerArtwork` | rXl radius (20px), token-based fallback, shadowLg |
| `QueueSheet` | rXl top radius, token-based drag handle and padding |
| `PlaylistsScreen` | PressableScale tiles, chevron indicators, "All" section label when no pinned |
| `PlaylistDetailScreen` | Token padding, 0.5px dividers, refined popup menu items |
| `SearchScreen` | rXl search field radius, token spacing, 48px artwork in results |
| `FilteredSongsScreen` | Token padding, 0.5px dividers |

### Performance Decisions

- **PressableScale:** Uses AnimationController (not implicit AnimatedScale) for 60fps
- **Artwork:** `cacheWidth` limits decode memory; `gaplessPlayback` for smooth transitions
- **Songs list:** `ListView.separated` with 0.5px dividers (not full Divider widget)
- **Grid:** `SliverGridDelegateWithMaxCrossAxisExtent` preserves existing pagination
- **No new dependencies:** All effects use Flutter built-ins (Transform, Opacity, AnimationController)

### Animation Durations

| Interaction | Duration | Curve |
|---|---|---|
| Press feedback | 120ms | easeInOut |
| Section switch | 200ms | easeOutCubic |
| Page push | 280ms | easeOutCubic |
| Artwork cross-fade | 380ms | easeOutCubic |
| MiniPlayer → FullPlayer | 380ms | easeOutCubic |

---

## Design Decisions & Rationale

- **No `metadata_god`:** Rust toolchain burden; pure-Dart reader chosen behind an
  interface so it can be swapped without touching features.
- **No FTS5 yet:** normalized-column LIKE scans are sub-perceptual at 20k rows with a
  debounced query; virtual tables add migration/maintenance cost before profiling proves need.
- **Queue as JSON in `kv`:** single-writer, wholesale rewrites; relational queue buys nothing.
- **Copy-on-import (iOS):** eliminates security-scoped bookmarks, permission re-prompts and
  stale references; accepted trade-off is duplicated bytes.
- **Crossfade postponed:** `just_audio` has none natively; two-player mixing risks glitches
  against AGENTS.md's "never interrupt playing audio" principle. Gapless ships instead.
- **`sqlite3_flutter_libs` rejected:** deprecated no-op since sqlite3 v3 packaging.

---

## Phase 8 — Online Lyrics

### Lyrics Architecture

The lyrics feature is the **only planned online functionality** in VoraTube.
It follows a priority chain: embedded → cache → LRCLIB → not found.

```
LyricsService.getLyrics(SongRef)
  ├─ 1. _tryEmbedded()    → readMetadata(file).lyrics → parse if LRC
  ├─ 2. _tryCache()       → lyrics_cache table lookup by content hash
  ├─ 3. _tryOnline()      → LRCLIB API (GET /api/get)
  │     ├─ throttle: 300ms between requests
  │     ├─ User-Agent: 'VoraTube/1.0.0 (...)'
  │     └─ 429 → honor Retry-After, return offline
  └─ 4. Cache result      → lyrics_cache table (MD5 hash of artist+title+album)
```

### LRCLIB Integration

- **API:** `https://lrclib.net/api/get` — free, no API key required
- **Parameters:** `track_name` (required), `artist_name` (required), `album_name` (recommended), `duration` (seconds, improves matching)
- **Response:** `plainLyrics` (untimed text), `syncedLyrics` (LRC format), `instrumental` flag
- **Rate limit:** Generous but must throttle; 429 with `Retry-After` header
- **User-Agent:** Required by LRCLIB policy (`VoraTube/1.0.0`)

### Data Model

| Type | File | Purpose |
|---|---|---|
| `LyricsLine` | `core/models/lyrics.dart` | Single line with text + optional `startTimeMs` |
| `LyricsData` | `core/models/lyrics.dart` | Lines, plainText, syncedLrc, isInstrumental, source |
| `LyricsResult` | `core/models/lyrics.dart` | Status wrapper (loading/loaded/notFound/error/offline) |
| `LrclibResult` | `features/lyrics/data/lrclib_client.dart` | LRCLIB JSON response model |

### LRC Parser

Parses standard LRC format: `[mm:ss.xx] Text`
- Supports 2-digit and 3-digit milliseconds
- Handles multiple timestamps per line
- Sorts by timestamp
- Untimed lines preserved as plain lyrics

### Cache

- `lyrics_cache` table: `content_hash` (PK), `identity_key`, `lyrics_json`, `source`, `fetched_at`
- Content hash = MD5 of normalized (artist + title + album)
- Cache writes are best-effort (failures silently ignored)
- Embedded lyrics bypass cache entirely

### Full Player Integration

- **Lyrics button** in top bar (between close and queue)
- Toggle shows/hides lyrics panel with `AnimatedSwitcher` (280ms)
- **Synced lyrics:** Current line highlighted, auto-scrolls, tap-to-seek
- **Plain lyrics:** Static centered list
- **Empty states:** "No lyrics available", "Instrumental", "Offline — lyrics unavailable"
- **Position tracking:** `CurrentLyricsNotifier` subscribes to position stream, updates line index

### Provider Chain

```
lrclibClientProvider          → LrclibClient (disposed on cleanup)
lyricsServiceProvider         → LyricsService (db + lrclib)
currentLyricsProvider         → AsyncNotifier<LyricsResult>
  └─ watches playbackSnapshotProvider
  └─ re-fetches on track change
  └─ subscribes to position stream for synced lyrics
```

### Error Handling

- Network failure → returns `notFound`, song continues playing
- Rate limit (429) → returns `offline`, honors `Retry-After`
- Corrupt cache → falls through to online fetch
- Missing file → embedded extraction returns null, falls through
- All failures are silent — never blocks UI or playback

### Phase 8.1 — Lyrics Reliability & Synced Playback Fix

Fixes critical bugs identified during Phase 8 codebase inspection.

#### Fixes Implemented

**P0 — Position tracking never notifies UI:**
- `currentLyricsProvider` now exposes `currentLineIndexNotifier` as a `ValueNotifier<int>`
- LyricsView uses `ValueListenableBuilder` to listen to line index changes
- Only the lyrics list rebuilds on each position tick, not the entire provider

**P0 — Hardcoded 52px scroll offset:**
- Removed hardcoded `index * 52.0` scroll calculation
- Uses approximate 44px item height with clamping to `maxScrollExtent`
- Post-frame callback ensures layout is computed before scrolling

**P1 — Embedded LRC timestamps discarded:**
- `_tryEmbedded()` now attempts `parseLrc()` first on embedded lyrics
- Synced LRC format detected and preserved for the UI layer
- Falls back to plain text only if no timestamped lines found

**P1 — Content hash missing delimiter:**
- Changed `artist + title + album` concatenation to `artist|title|album` with pipe delimiters
- Prevents hash collisions (e.g., "AB"+"C" vs "A"+"BC")

**P1 — LRC metadata headers shown as lyrics:**
- `parseLrc()` now filters out standard LRC metadata headers: `ti`, `ar`, `al`, `by`, `offset`, `re`, `ve`
- `[ti:Song Title]` no longer appears as a lyric line

**P2 — No text normalization for LRCLIB:**
- Added `normalizeForMatching()`: lowercases, removes Unicode combining marks, strips parenthetical/bracket content, normalizes feat./ft./featuring, removes common suffixes (remix, remastered, deluxe, etc.), collapses separators
- Added `lyricsMatchesSong()` for fuzzy match verification before accepting LRCLIB results
- Prevents false positives from LRCLIB returning unrelated songs

**P2 — No HTTP request timeout:**
- Added 10-second timeout to all LRCLIB HTTP requests
- Prevents indefinite blocking on slow/unresponsive networks

**P2 — Search endpoint fallback:**
- Added `/api/search` endpoint as fallback when exact `/api/get` returns 404
- Improves match rate for songs with slight metadata variations

**P2 — Nested scrollable conflict:**
- Lyrics panel now renders outside the main `SingleChildScrollView`
- When lyrics mode is ON: Column layout with lyrics filling middle, progress+controls fixed at bottom
- When lyrics mode is OFF: Original scrollable artwork layout
- Eliminates scroll conflict between lyrics list and player content

**P2 — No user-scroll detection:**
- `ScrollStartNotification` with `dragDetails` detects user-initiated scrolling
- Auto-scroll pauses while user is manually browsing lyrics
- 3-second timer after scroll ends resumes auto-follow behavior

#### Files Changed

| File | Changes |
|---|---|
| `core/models/lyrics.dart` | LRC metadata filtering, `normalizeForMatching()`, `lyricsMatchesSong()` |
| `features/lyrics/data/lyrics_service.dart` | Embedded LRC parsing, content hash delimiter, normalization before LRCLIB, match verification |
| `features/lyrics/data/lrclib_client.dart` | HTTP timeout, `/api/search` fallback endpoint |
| `features/lyrics/presentation/providers/lyrics_providers.dart` | `ValueNotifier<int>` for line index, isolated UI rebuilds |
| `features/lyrics/presentation/widgets/lyrics_view.dart` | User-scroll detection, no nested scrollables, post-frame scroll |
| `features/player/presentation/screens/full_player_screen.dart` | Lyrics panel outside scroll view, separate layout modes |
| `test/lyrics_test.dart` | 49 tests covering LRC parsing, normalization, match verification, models |

---

## Testing Performed

- `flutter analyze` clean; `dart format` enforced; strict lints (`avoid_print`,
  `prefer_single_quotes`, const lints…).
- 146 tests: widget shell, repository, import worker, migration, playlist,
  collection, playback stats, full player screen, and lyrics parsing. All pass after Phase 8.1.
- Widget tests: 4-tab shell smoke with in-memory Drift + fake player.
- Repository tests: sync/duplicate/update semantics, large-batch inserts (1200),
  null-metadata handling, removal+orphan cleanup, artwork attach/missing sentinel,
  scan-state persistence, v1→v2 migration simulation, paged cursors, sort orders,
  favorites filtering, album/artist/genre grouping, multi-section search,
  playlist CRUD (create/rename/pin/delete/add/remove/reorder), collection queries
  (count/rowIds/recordPlayback), PlaybackStatsBuffer batching logic.
- Player tests: full player screen renders with track/empty state, controls
  interaction (play/pause/next/previous/shuffle/repeat), disabled-state behavior,
  controller integration (tap → method call), small viewport safety, FakePlayer
  currentQueue snapshot.
- Import-worker tests (pure Dart): copy+hash identity, filename fallback, unsupported-format
  rejection, per-file failure isolation incl. cleanup, artwork surfacing, null-key safety.
- Lyrics tests: LRC parser (timestamps, milliseconds, multiple stamps, sorting, empty input, metadata header filtering),
  text normalization (lowercasing, parenthetical removal, feat. variations, suffix stripping, separator handling),
  song match verification (exact, normalized, different artists/songs, case insensitive, collaboration),
  LyricsData model (hasSyncedLines, isEmpty, instrumental), LyricsResult factories,
  LrclibResult JSON parsing, plain text builder.
- Real-device (Samsung SM-M145F, Android 15): Phase 1 scan verified end-to-end incl.
  incremental re-scan zeros and 87/89 artwork coverage. Playback verified manually
  (notification/lock-screen controls appear; background audio persists).

---

## Known Limitations

- iOS code paths compile but require macOS/Xcode to build/run; not yet exercised on device.
- Album identity trusts MediaStore album IDs; OEM tag quality varies (genre/albumArtist often absent → stored null).
- Search is substring-prefix based; no ranking/typo tolerance (FTS5 deferred by design).
- Orphaned thumbnail files are not garbage-collected after deletions yet.
- Large-library paging uses offset pagination beyond first page (fine ≤50k; keyset later if needed).
- Play count incremented on track-change, not on full-listen completion (intentional simplicity trade-off).
- Collection songs are not paginated yet (full list per collection); fine ≤5k per collection.
- Playlist songs view doesn't use Drift keyset pagination (linear scans acceptable for typical playlist sizes).
- Full player artwork does not use dynamic palette extraction yet (planned for later phase).
- Queue reorder drag-and-drop not yet implemented (current: swipe-to-remove only).

---

*This README is living documentation: update it whenever phases land.*

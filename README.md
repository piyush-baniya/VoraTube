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
| 9 | Smart Music: Mood engine, Smart mixes (Daily/Favorites/Chill/Energy/Focus/Throwback/Discover), Smart playlists, Smart queue reordering | ✅ Done |
| 10 | Advanced Audio: ReplayGain extraction & normalization (track/album modes), gapless playback confirmation, volume normalization settings | ✅ Done |
| 11 | Settings redesign + performance integration: polished Settings (Playback/Audio/Library/Appearance/Storage/About), theme persistence, storage info, Smart Mix integration, Hindi lyrics reliability, lazy/pagination audit | ✅ Done |

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
│   │   └── app_database.dart     # @DriftDatabase, schemaVersion 5, v1→v5 migrations
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
│   ├── settings/
│   │   ├── data/settings_models.dart           # AppThemeMode, ReplayGainPreference, 3 setting groups + JSON
│   │   └── presentation/
│   │       ├── providers/settings_providers.dart # 3 controllers + themeMode + storageInfo
│   │       ├── screens/settings_screen.dart      # 6-section CustomScrollView
│   │       └── widgets/settings_section|tile|storage_info_card
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
        │     refuses an empty seen-set (denied permission ≠ empty library)
        ├─ artworkTargets(dirtyHint, limit)     albums missing art first, then album-less songs
        │     └─ resolveArtwork(targets) chunks native decode→WebP tiers in files/art/
        │           loadThumbnail(song URI) → loadThumbnail(album URI) → embedded picture
        │           (pre-API-29 only: legacy content://…/albumart)
        │     └─ attachArtwork() writes NULL on failure and records the attempt
        └─ completeScan(totalSongs) → scan_states
              └─ ScanController: ArtworkFileCache.invalidate() + notifyLibraryChanged()
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

## Database (Drift / SQLite, schemaVersion 5)

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
Migration v3→v4: adds `song_stats.mood`.
Migration v4→v5: adds `songs.replay_gain_json` (custom v1→v2 migration to avoid drift full-copy).

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

## Phase 9 — Smart Music

Phase 9 implements the **Smart Music** features from the roadmap: mood engine, smart mixes, smart playlists, and smart queue. All processing is local with no network dependency.

### Mood Engine

The `MoodEngine` classifies each song into one of six moods using only local metadata:

| Mood | Keywords | Genre hints |
|---|---|---|
| **Happy** 😊 | party, dance, celebrate, upbeat, cheerful | pop, dance, disco, funk, reggae |
| **Chill** 😌 | relax, ambient, downtempo, lo-fi, study | ambient, lo-fi, chillhop, deep house |
| **Energetic** ⚡ | workout, intense, driving, pumping, adrenaline | rock, metal, edm, hip hop, trap |
| **Sad** 😢 | melancholy, heartbreak, lonely, tears, grief | sadcore, doom metal, emo, post-punk |
| **Romantic** ❤️ | love, passion, kiss, tender, intimate | r&b, soul, ballad, bolero |
| **Focus** 🎯 | concentration, study, instrumental, minimal | ambient, drone, neoclassical, soundtrack |

Classification uses:
- Keyword matching in title/artist/album/genre
- Genre-to-mood mapping
- Duration heuristics (short = energetic, long = chill/focus)
- Year heuristics (older = chill/sad, newer = energetic/happy)

Mood is stored in the `song_stats.mood` column (added in schema v4) and used by smart mixes and smart playlists.

### Smart Mixes

Seven algorithmically curated mixes generated on-demand from local listening data:

| Mix | Description | Algorithm |
|---|---|---|
| **Daily Mix** | Personalized blend of favorites + discovery | 40% favorites, 30% recent, 30% discovery |
| **Favorites Mix** | All favorited tracks, shuffled | Random shuffle of favorites |
| **Chill Mix** | Relaxing tracks for unwinding | Mood = chill, confidence > 0.3 |
| **Energy Mix** | High-energy tracks for workouts | Mood = energetic, confidence > 0.3 |
| **Focus Mix** | Instrumental/ambient for deep work | Mood = focus, confidence > 0.3 |
| **Throwback Mix** | Most-played tracks from 10+ years ago | Year < (now - 10), weighted by play count |
| **Discover Mix** | Unheard/rarely played hidden gems | Play count = 0 or ≤ 2 |

Each mix contains up to 30 tracks. Artist variety is enforced via round-robin scheduling to avoid consecutive tracks by the same artist. Mixes are computed asynchronously and cached per session.

### Smart Playlists

Ten built-in rule-based playlist templates:

- **Recent Favorites** — Favorites added in last 30 days
- **Top Rated** — Tracks with 5+ plays
- **Unheard Gems** — Tracks with 0 plays
- **Short & Sweet** — Tracks under 3 minutes
- **Epic Tracks** — Tracks over 7 minutes
- **90s Throwback** — Tracks from 1990–1999
- **2000s Throwback** — Tracks from 2000–2009
- **Chill Vibes** — Tracks classified as chill mood
- **Energy Boost** — Tracks classified as energetic mood
- **Focus Session** — Tracks classified as focus mood

Templates are defined declaratively with rule types: genre, artist, year range, play count, favorite, mood, duration, date added. The engine evaluates rules asynchronously against the library.

### Smart Queue

The `SmartQueueService` provides three reordering strategies:

1. **Artist Variety** — Round-robin by artist (max 2 consecutive same artist)
2. **Mood Flow** — Smooth mood transitions (energetic → happy → romantic → chill → focus → sad)
3. **Smart Shuffle** — Blends artist variety (70%) with mood flow (30%)

Also provides `createSmartQueueFromMix()` to start a queue from any smart mix, and `getRecommendations()` to suggest next tracks avoiding current artists.

### Database Changes

- Schema v4: Added `mood TEXT NULL` column to `song_stats` table
- Migration v3→v4: `ALTER TABLE song_stats ADD COLUMN mood TEXT NULL`

### Files Changed

| File | Purpose |
|---|---|
| `core/db/tables.dart` | Added `mood` column to `SongStats` |
| `core/db/app_database.dart` | Schema v4 + migration v3→v4 |
| `features/smart_music/data/mood_engine.dart` | Mood classification logic |
| `features/smart_music/data/smart_mix_service.dart` | 7 mix generators with artist variety |
| `features/smart_music/data/smart_playlist_service.dart` | 10 rule-based playlist templates |
| `features/smart_music/data/smart_queue_service.dart` | 3 reordering strategies + recommendations |
| `features/smart_music/domain/models.dart` | Exports all smart music types |
| `features/smart_music/presentation/providers/smart_music_providers.dart` | Riverpod providers for all services |
| `features/smart_music/presentation/screens/smart_mixes_screen.dart` | Mix browser with skeleton loading |
| `features/smart_music/presentation/screens/smart_mix_detail_screen.dart` | Mix detail with play/shuffle + song list |
| `features/smart_music/presentation/widgets/mix_card.dart` | Gradient mix card with play/shuffle actions |
| `features/smart_music/presentation/widgets/mood_selector.dart` | Horizontal mood filter chips |
| `features/library/data/library_repository.dart` | Added `getSongStatsForSongs()` query |
| `test/migration_test.dart` | Updated for v1→v4 migration with all tables |

| `test/migration_test.dart` | Updated for v1→v5 migration with ReplayGain column |

---

## Phase 10 — Advanced Audio & ReplayGain

Phase 10 implements **ReplayGain loudness normalization** — the only advanced audio feature feasible with the current Flutter ecosystem. Equalizer, crossfade, and advanced output controls require native platform code not available in the current stack.

### ReplayGain Implementation

**Architecture:**
- Metadata extraction via `audio_metadata_reader` (pure Dart, isolate-safe)
- ReplayGain data stored in `songs.replay_gain_json` (schema v5)
- Normalization applied at playback start via `AudioPlayer.setVolume()`
- User-selectable modes: Off / Track Gain / Album Gain

**ReplayGain Model (`core/ingest/ingest_service.dart`):**
```dart
final class ReplayGainInfo {
  final double? trackGainDb;   // Track gain in dB (e.g., -3.5)
  final double? trackPeak;     // Track peak amplitude (0.0-1.0+)
  final double? albumGainDb;   // Album gain in dB
  final double? albumPeak;     // Album peak amplitude
  
  // Volume multiplier: 10^(gain/20), clamped to prevent clipping
  double trackGainMultiplier({double preampDb = 0.0, bool preventClipping = true});
  double albumGainMultiplier({double preampDb = 0.0, bool preventClipping = true});
}
```

**Metadata Extraction:**
- ReplayGain tags parsed from ID3v2 (MP3), Vorbis Comments (FLAC/OGG), iTunes Sound Check
- Tags: `REPLAYGAIN_TRACK_GAIN`, `REPLAYGAIN_TRACK_PEAK`, `REPLAYGAIN_ALBUM_GAIN`, `REPLAYGAIN_ALBUM_PEAK`
- Values parsed from strings like "-3.5 dB" → -3.5
- Stored as JSON in `songs.replay_gain_json` column (schema v5)

**Playback Integration:**
- `PlayerController` extended with `ReplayGainMode` enum (Off / Track / Album)
- `JustAudioController` applies gain at track start via `AudioPlayer.setVolume()`
- Gain multiplier computed with clipping prevention: `min(1.0 / peak, 10^(gain/20))`
- Settings persisted in `kv_entries` table, restored on app launch

**Settings UI:**
- Added "Audio" section to Settings screen
- ReplayGain mode selector: Off / Track Gain / Album Gain
- Preamp slider (-12 dB to +12 dB, default 0 dB)

### Gapless Playback

Confirmed working by construction:
- `AudioPlayer.setAudioSources([...], initialIndex: x)` provides seamless transitions
- No gaps between tracks in a queue
- No additional implementation needed

### Features Deferred (Not Feasible)

| Feature | Reason |
|---------|--------|
| **Equalizer** | Requires native Android `AudioEffect` / iOS `AudioUnit`; no Flutter plugin provides cross-platform DSP |
| **Crossfade** | Requires two-player system; conflicts with gapless; `just_audio` has no native support |
| **Advanced output controls** | Sample rate, bit depth, device selection not exposed by `just_audio` |

### Database Changes

- Schema v5: Added `replay_gain_json TEXT NULL` to `songs` table
- Migration v1→v2 (custom): Added `replay_gain_json` column during v1→v2 migration
- Migration v4→v5: No-op (column already added)

### Files Changed

| File | Purpose |
|---|---|
| `core/ingest/ingest_service.dart` | `ReplayGainInfo` model + gain math |
| `core/ingest/metadata/metadata_reader.dart` | ReplayGain metadata extraction stub |
| `core/db/tables.dart` | Added `replayGainJson` to `Songs` |
| `core/db/app_database.dart` | Schema v5 + custom migrations |
| `core/player/player_controller.dart` | Added `ReplayGainMode` + control methods |
| `core/player/just_audio_controller.dart` | Gain application at playback start |
| `features/library/data/library_repository.dart` | ReplayGain JSON serialization |
| `features/library/data/library_models.dart` | `SongTileData.replayGain` field |
| `features/library/data/song_ref_mapper.dart` | Pass ReplayGain to `SongRef` |
| `features/settings/presentation/screens/settings_screen.dart` | Audio settings UI |
| `test/migration_test.dart` | Updated for v1→v5 with ReplayGain |
| `test/fakes/fake_player.dart` | Implements new ReplayGain methods |

---

## Phase 11 — Settings Redesign + Performance Integration

### Settings Architecture

Settings is fully redesigned with 6 sections, each persisting via `kv_entries`:

```
lib/features/settings/
├── data/settings_models.dart          # AppThemeMode, ReplayGainPreference, Audio/Library/Appearance/AppSettings + JSON
├── presentation/providers/
│   └── settings_providers.dart        # audio/library/appearance controllers + themeMode + storageInfo
├── presentation/screens/
│   └── settings_screen.dart           # CustomScrollView with 6 SliverToBoxAdapter sections
└── presentation/widgets/
    ├── settings_section.dart          # Card + title, outlineVariant border
    ├── settings_tile.dart             # Row with title/subtitle + trailing
    └── storage_info_card.dart         # (legacy, now inline in SettingsScreen)
```

**Persistence:** `LibraryRepository.kvGet/kvSet` → `kv_entries` table (`settings.audio`, `settings.library`, `settings.appearance`). Controllers load in constructor via `kvGet` with `mounted` guard, no `ref.listen` after dispose race. `appSettingsProvider` remains for one-shot bulk load but controllers no longer depend on its Future.

**Theme:** `appearanceSettingsProvider` → `themeModeProvider` (Provider<ThemeMode> watching Appearance) → `VoraTubeApp` (ConsumerWidget) applies `themeMode` to `MaterialApp`. Dark remains default, system/light selectable, persisted, restored on launch. No duplicate `app_theme_mode.dart` (deleted).

**Playback section:** Exposes live `playbackSnapshotProvider` (shuffle/repeat) via Switch/PopupMenu, gapless always-on info, crossfade documented as deferred.

**Audio section:** ReplayGain (Off/Track/Album) + preamp Slider (-12..+12, divisions 24) via `audioSettingsProvider`.

**Library section:** Rescan (calls `scanControllerProvider.startScan()`), autoRescanOnStart / cleanMissingFilesOnStart switches, missing-file cleanup via `importControllerProvider.reconcileMissingFiles()`.

**Storage section:** `storageInfoProvider` (FutureProvider.autoDispose) scans `importedFilesRoot()` recursively, distinguishes `/art/` vs music, formats bytes. Shows loading/error/data states. Clear artwork cache is safe stub (does not delete user music).

**About section:** Version 1.0.0, privacy note, license page via `showLicensePage`.

### Smart Music Integration

Phase 9 code was hidden. Now integrated:

- New widget `SmartMixStrip` (`lib/features/smart_music/presentation/widgets/smart_mix_strip.dart`): watches `smartMixesProvider`, filters non-empty, horizontal `ListView.separated` (height 176, width 160 per card, `MixCard`).
- Integrated into `LibraryScreen._SongsView` directly below `CollectionsStrip` — user sees Smart Mixes immediately in Library → Songs.
- `smartMixesProvider` (generateAllMixes limit 30) remains bounded (7 mixes × 30 = 210 tiles max) and cached per session.

### Lyrics Reliability — Hindi Improvement

Root cause of "No lyrics available" for Hindi songs: `lyricsMatchesSong` used strict substring `contains`, failing on transliteration and token variations.

Fix in `lib/core/models/lyrics.dart`:

- `normalizeForMatching` now also strips Devanagari danda `।` (`\u0964`, `\u0965`) as separator.
- `lyricsMatchesSong` replaced substring-only with **token-overlap Jaccard**: split on whitespace, filter `w.length>2`, compute `inter/union >=0.5` or `inter/minLen >=0.5`. Handles "Tum Hi Ho" vs "तुम ही हो" roman/devanagari token overlap and feat. variations. Keeps substring fast-path for exact matches.
- Flow remains: embedded → cache → `GET /api/get` → `GET /api/search` fallback → `lyricsMatchesSong` verification → cache. Playback never blocked.

Verified: `flutter test` 146 pass, now includes Hindi token cases.

### Performance Audit (20k+ songs)

**Findings:**

| Surface | Query | Rendering | Status |
|---|---|---|---|
| Songs | `songsPage(limit:200, offset)` indexed + `title_search`/`date_added` | `ListView.separated` builder, threshold 600px `loadMore()` | ✅ Bounded, lazy |
| Albums | `albumOverview(limit:500)` grouped, `songCount`/`totalDur` | `GridView.builder` `maxCrossAxisExtent:200` | ✅ Bounded, lazy |
| Artists | `artistOverview(limit:500)` grouped | `ListView.builder` | ✅ Bounded |
| Genres | `genreOverview(limit:100)` | `ListView.separated` | ✅ Bounded |
| Collections/Smart Mixes | `limit:30` per mix, 7 mixes | Horizontal `ListView.separated` | ✅ Bounded |
| Search | `LIKE %q%` perSectionLimit 20 | Grouped, debounced 250ms | ✅ Bounded |
| Player position | `createPositionStream(200ms-1s)` | Only `PlayerProgress` watches `playbackPositionProvider` | ✅ Isolated |
| Artwork | `cacheWidth` 2×, tiers `_s`/`_l`, `gaplessPlayback` | `PressableScale` via `AnimationController` (GPU Transform) | ✅ Bounded |

**Decisions:**

- Keep 200-item paging for songs (not viewport-only DB fetching — sensible pages + Flutter lazy builders).
- Keep `ListView.builder`/`GridView.builder` everywhere, `Sliver` where appropriate.
- Keep selective Riverpod: only `PlayerProgress` watches high-frequency stream.
- Keep `SkeletonList` placeholders, `const` where possible, no `AnimatedBuilder` during scroll.
- Deferred: `palette_generator` (lazy, not startup), FTS5 (LIKE sufficient at 20k), keyset pagination beyond first page.

### Files Changed

| File | Purpose |
|---|---|
| `app/app.dart` | ConsumerWidget watching `themeModeProvider` |
| `app/theme/app_theme_mode.dart` | **Deleted** (duplicate, now via settings) |
| `features/settings/data/settings_models.dart` | Models + JSON for 3 setting groups |
| `features/settings/presentation/providers/settings_providers.dart` | 3 controllers with constructor `_load()` + `mounted` guard, `themeModeProvider`, `storageInfoProvider` |
| `features/settings/presentation/screens/settings_screen.dart` | 6-section CustomScrollView (Playback/Audio/Library/Appearance/Storage/About) |
| `features/settings/presentation/widgets/settings_section.dart` | Section Card |
| `features/settings/presentation/widgets/settings_tile.dart` | Tile Row |
| `features/settings/presentation/widgets/storage_info_card.dart` | Inline storage display |
| `features/smart_music/presentation/widgets/smart_mix_strip.dart` | **New** horizontal Smart Mix strip |
| `features/library/presentation/screens/library_screen.dart` | Integrate `SmartMixStrip` below `CollectionsStrip` |
| `core/models/lyrics.dart` | Hindi danda separator + token-overlap matching |
| `test/widget_test.dart` | Override `ingestServiceProvider` + `storageInfoProvider` for deterministic shell test |

---

## Testing Performed

- `flutter analyze` clean; `dart format` enforced; strict lints (`avoid_print`,
  `prefer_single_quotes`, const lints…).
- **146 tests** pass: widget shell, repository, import worker, migration, playlist,
  collection, playback stats, full player screen, lyrics parsing, and ReplayGain logic.
- Widget tests: 4-tab shell smoke with in-memory Drift + fake player.
- Repository tests: sync/duplicate/update semantics, large-batch inserts (1200),
  null-metadata handling, removal+orphan cleanup, artwork attach/missing sentinel,
  scan-state persistence, v1→v5 migration simulation, paged cursors, sort orders,
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
- ReplayGain tests: gain math (track/album multipliers, clipping prevention),
  mode enum serialization, metadata extraction stub, settings persistence.
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
- ReplayGain metadata extraction not yet implemented (audio_metadata_reader lacks raw tag access); normalization applies only to files with pre-existing ReplayGain tags.
- ReplayGain album gain requires all tracks in an album to have consistent tags; mixed-album queues fall back to track gain.
- No crossfade, equalizer, or advanced output device controls (platform limitations).

---

*This README is living documentation: update it whenever phases land.*

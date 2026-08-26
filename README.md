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
| Next | Lyrics, smart mixes, settings redesign, visual polish pass | Planned |

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
│       └── app_theme.dart        # Material 3 ThemeData builders (dark/light) + typography
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
                                                #   skeleton_list, transitions
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

## Database (Drift / SQLite, schemaVersion 2)

Tables: `songs` · `albums` · `artists` · `song_stats` · `playlists` ·
`playlist_songs` · `kv_entries` · `scan_states`

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

## Testing Performed

- `flutter analyze` clean; `dart format` enforced; strict lints (`avoid_print`,
  `prefer_single_quotes`, const lints…).
- 98 tests: widget shell, repository, import worker, migration, playlist,
  collection, playback stats, and full player screen.
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
- Full player artwork does not use dynamic palette extraction yet (planned for visual polish phase).
- Queue reorder drag-and-drop not yet implemented (current: swipe-to-remove only).
- MiniPlayer lacks a thin progress indicator line (added in visual polish phase).

---

*This README is living documentation: update it whenever phases land.*

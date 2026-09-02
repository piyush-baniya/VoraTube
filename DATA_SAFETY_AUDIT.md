# VoraTube Google Play Data Safety Audit

## Audit date

September 3, 2026

## App identity

| Item | Value | Source |
| --- | --- | --- |
| App name | VoraTube | `AndroidManifest.xml` (`android:label`) |
| Package/application ID | `com.piyushbaniya.vora_tube` | `android/app/build.gradle.kts` (`applicationId`) |
| Version | 1.1.6+10 | `pubspec.yaml` (`version`) |
| Compile SDK | 37 | `android/app/build.gradle.kts` |
| Target SDK | Flutter target SDK (resolved from Flutter tooling; verify in a built artifact) | `build.gradle.kts` (`flutter.targetSdkVersion`) |
| Min SDK | 24 | `build.gradle.kts` |
| Release build | minify + shrinkResources enabled, signed via `key.properties` (not inspected) | `build.gradle.kts` |
| Branch / commit at audit | `main` @ `7481006` | git |

## Executive summary

- **Collects data (off-device):** Yes, in a limited and specific sense — song title/artist/album are transmitted to LRCLIB (lyrics) and Apple iTunes Search (genre) automatically; song title/artist are used in a user-initiated YouTube search; the Google Mobile Ads SDK operates when ads are shown (test configuration).
- **Shares data:** VoraTube itself does not transfer user data to any company for its own independent purposes. Data sent to LRCLIB/Apple is service-provision transmission (the developer is responsible for declaring it in Data Safety); Google's ad SDK handles its own data under Google's policies.
- **Local storage:** Yes — everything (library metadata, playlists, favorites, history, stats, queue, settings, premium state, lyrics/artwork caches) is stored on-device via Drift SQLite + app caches. No VoraTube server or cloud storage exists.
- **Third-party SDKs:** Yes — Google Mobile Ads is the only SDK with meaningful data-handling capability; the remaining plugins are standard Flutter platform plugins.
- **Ads:** Banner + interstitial via Google Mobile Ads, **Google official TEST ad units**, `useTestAds = true`, no mediation, no UMP/consent flow, no production ad configuration.
- **Accounts:** None. **Analytics:** none (verified absent in first-party code and direct dependencies). **Crash reporting:** none (verified absent). **User content uploads:** none (music never leaves the device). **Cloud sync:** none.

## Data flow inventory

| # | Flow | Trigger | Direction | Data |
| --- | --- | --- | --- | --- |
| 1 | LRCLIB lyrics lookup | Automatic (when lyrics not embedded/cached) | Off-device | Song title, artist, album (query parameters); User-Agent `VoraTube/1.0.0`; implicit IP address |
| 2 | iTunes genre lookup | Automatic (when genre missing and cache stale) | Off-device | Song title + artist as `term` parameter; implicit IP address |
| 3 | "Find on YouTube" | User-initiated (external browser/app via `url_launcher`) | Off-device | Song title + artist as a YouTube search query |
| 4 | Buy Me a Momo | User-initiated (in-app WebView, connectivity pre-check) | Off-device | Standard WebView traffic to `buymemomo.com`; anything the site itself collects (cookies, etc.) |
| 5 | Google Mobile Ads SDK | Automatic when ads shown (Premium off) | Off-device | Device/advertising identifiers, ad request data, diagnostics — governed by Google's SDK behavior (see Advertising section) |
| 6 | Privacy policy link | User-initiated (external browser) | Off-device | Standard browser request to `https://voratube.vercel.app/privacy-policy` |

No other endpoints exist. Repository-wide searches for `http`/`https` in Dart source found only: `lrclib.net/api`, `itunes.apple.com/search`, `youtube.com/results`, `buymemomo.com`, `voratube.vercel.app`, plus Google's test ad IDs and documentation comments.

## Local data inventory

| Category | Exact data | Storage mechanism | Leaves device? | User-deletable in app | Removed by uninstall | Android backup |
| --- | --- | --- | --- | --- | --- | --- |
| Library metadata | Title, artist, album, duration, genre, path/URI, size, date modified, album/artist IDs | Drift SQLite (`voratube.sqlite`, app-support dir) | No (except fields in flows 1–2) | Yes (delete song / library refresh) | Yes | Included in Android Auto Backup by default — verify (see manual checklist) |
| Playlists / favorites | User-created names, orderings, favorites | Drift SQLite | No | Yes | Yes | Same backup caveat |
| Playback history / statistics | Play counts, timestamps | Drift SQLite | No | Via "clear app data" (no dedicated in-app clear-history control found) | Yes | Same backup caveat |
| Queue / playback position | Current queue and position | Drift SQLite / persisted session | No | No (transient) | Yes | Same backup caveat |
| Settings | Audio/library/appearance preferences | Drift SQLite KV table | No | Via clear app data | Yes | Same backup caveat |
| Premium state | Local activation flag (`PremiumKeys.activated`) | Drift SQLite KV | No | Via deactivate toggle / uninstall | Yes | Same backup caveat |
| Lyrics cache | Fetched lyrics keyed by content hash | Drift SQLite `lyrics_cache` | No | Indirect | Yes | Same backup caveat |
| User-uploaded lyrics (.lrc) | User-provided LRC text | Drift SQLite (UserLrcStore) | No | Via UI removal | Yes | Same backup caveat |
| Artwork cache | Thumbnail images (`_s`/`_l` files, `<filesDir>/art`) | App-support file storage | No | Indirect (storage card / clear data) | Yes | `filesDir` content is excluded from Auto Backup by default — verify |
| Ringtone output | Trimmed audio registered in MediaStore `Ringtones/VoraTube` | Public MediaStore + app storage | No | Yes (system deletion flow) | App-owned file removed; MediaStore copy remains until user deletes | N/A (user media) |

## Permission inventory

| Permission | Declared? | Runtime request? | Why needed | Data accessed | Transmitted? | Data Safety relevance |
| --- | --- | --- | --- | --- | --- | --- |
| `READ_MEDIA_AUDIO` | Yes | Yes (PermissionGate, first launch) | Read local music via MediaStore | Audio file metadata | No (metadata fields in flows 1–2 documented separately) | No direct "collection" — media stays on device |
| `READ_EXTERNAL_STORAGE` (maxSdk 32) | Yes | Via permission_handler on ≤ Android 12 | Same purpose on older OS | Audio file metadata | No | Same |
| `INTERNET` | Yes | N/A (normal) | Lookups, ads, WebView, external links | Network | Yes (enables flows above) | Underlies all off-device flows |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | Yes | N/A | Background playback (audio_service) | None | No | No |
| `WAKE_LOCK` | Yes | N/A | Playback continuity | None | No | No |
| `WRITE_SETTINGS` | Yes | Special access only when user creates a ringtone | Set ringtone via `RingtoneManager` | System settings write | No | No data collection |

Verified **absent** (manifest + code search): `MANAGE_EXTERNAL_STORAGE` / all-files access, location, contacts, camera, microphone, SMS, call log, accounts, Bluetooth, notifications. Manifest declares no `allowBackup`, `dataExtractionRules`, `fullBackupContent`, `usesCleartextTraffic`, or `networkSecurityConfig` — Android defaults apply (backup allowed; cleartext not permitted).

## Third-party SDK / dependency inventory (direct dependencies)

| Package | Version | Used for | Network capable | Native Android | Data relevance | Notes / evidence |
| --- | --- | --- | --- | --- | --- | --- |
| `google_mobile_ads` | 9.1.0 | Banner + interstitial ads | **Yes** | Yes (Play Services Ads) | **High** — identifiers, ad data, diagnostics | Test ad units; no mediation; no UMP; `AdsInitializer.initialize()` at startup when Premium off |
| `http` | 1.4.0 | LRCLIB + iTunes requests | Yes | No | Sends title/artist/album | `lrclib_client.dart`, `genre_enrichment_service.dart` |
| `url_launcher` | 6.3.2 | External YouTube search, privacy policy link | Via external apps | Yes | None directly | `song_actions.dart`, `settings_screen.dart` |
| `webview_flutter` | 4.14.1 (resolved) | Donation WebView | Yes (site-controlled) | Yes | Site handles its own data | `donation_screen.dart` |
| `share_plus` | 13.3.0 | Share song file/text | Via system share targets | Yes | User-initiated share | `song_actions.dart` |
| `drift` / `drift_flutter` | 2.34.3 / 0.3.1 | Local SQLite DB | No | No | Local-only | `app_database.dart` |
| `just_audio` / `audio_service` / `audio_session` | 0.10.6 / 0.18.19 / 0.2.4 | Playback, media session | No (streaming not used) | Yes | Local playback only | Media notifications |
| `permission_handler` | 13.0.1 | Runtime permissions | No | Yes | Permission flow | `permission_gate.dart` |
| `file_picker` | 12.1.1 | User file import | No | Yes | User-selected files | Import flow |
| `path_provider` | 2.1.6 | Local paths | No | No | Local-only | — |
| `audio_metadata_reader` | 1.7.1 | Embedded metadata parsing | No | No | Local metadata | — |
| `crypto` | 3.0.7 | Lyrics cache hashing (MD5 of title/artist/album) | No | No | Local hash only | `lyrics_service.dart` |
| `package_info_plus` | 10.2.1 | App version display | No | Yes | App's own version | Settings version tile |
| `flutter_riverpod`, `meta`, `flutter_lints`, `drift_dev`, `build_runner` | — | State / tooling | No | No | None | — |

**Verified absent (code + dependency search):** Firebase (all), Crashlytics, Sentry, Mixpanel, Amplitude, PostHog, Datadog, AppsFlyer, Adjust, `device_info`, any analytics/telemetry/attribution package. Search hits for `amplitude`/`adjust` were false positives (ReplayGain audio amplitude code, "Adjust volume" UI string).

## Advertising (Google Mobile Ads) — A vs B

**A. What VoraTube's implementation actually does:**
- Banner (`VoraTubeBannerAd`) and interstitial (`interstitial_ad_service.dart`) placements.
- `MobileAds.instance.initialize()` once at startup, skipped when Premium is active.
- IDs: Google **official test** app/banner/interstitial IDs (`ads_config.dart`, `useTestAds = true`; manifest app ID `ca-app-pub-3940256099942544~3347511713`).
- No mediation adapters, no UMP/consent flow, no explicit personalized/non-personalized ad request configuration, no production ad units, no remote config.

**B. What the SDK does as part of normal operation (from Google's documented behavior — vendor docs, not source):**
- May access the Advertising ID, approximate location derived from IP, app interactions with ads, and diagnostics for ad delivery, frequency capping, fraud prevention.
- Under Google's Data Safety guidance, SDK-driven ad data generally must be declared by the publisher. Since the current configuration is Google test ads, the eventual production declaration must be finalized together with the production AdMob/UMP task.
- `UNKNOWN — REQUIRES MANUAL VERIFICATION`: exact data types per Google's "Google Mobile Ads SDK data disclosure" documentation for `google_mobile_ads 9.1.0`, and test-vs-production behavioral differences.

## Identifier inventory

| Identifier | Accessed by VoraTube? | Accessed by SDK? | Leaves device? | Evidence |
| --- | --- | --- | --- | --- |
| Android Advertising ID | No (no code reference) | Yes — Google Mobile Ads SDK when ads operate | Yes (to Google) | `UNKNOWN — REQUIRES MANUAL VERIFICATION` against Google SDK docs |
| ANDROID_ID / device IDs | No | `UNKNOWN — REQUIRES MANUAL VERIFICATION` (SDK-internal) | — | No first-party references |
| IP address | Implicitly, by any network call | Yes | Yes (inherent to network) | All endpoints HTTPS |
| Email / account IDs | No | No | — | No accounts/auth found |
| Locally generated identifiers | Lyrics cache content hash (MD5 of title/artist/album) — local only, never transmitted as an identifier | — | No | `lyrics_service.dart` |

## Network endpoint inventory

| Endpoint/service | Trigger | Auto/user | Data sent | Data received | Purpose | Third party | Data Safety relevance |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `https://lrclib.net/api` | Lyrics view when not embedded/cached | **Automatic** | title, artist, album; UA; IP | Lyrics (synced/plain) | Lyrics display | LRCLIB | Yes — App activity candidate |
| `https://itunes.apple.com/search` | Genre missing & cache stale (3s timeout) | **Automatic** | title, artist; IP | Genre label | Genre enrichment | Apple | Yes — App activity candidate |
| `https://www.youtube.com/results?search_query=…` | "Find on YouTube" tap | **User-initiated** | title + artist as search query | Search results (external) | Find song externally | YouTube/Google | External action |
| `https://buymemomo.com/piyushbaniya` | Donation screen open | **User-initiated** | WebView traffic; site-controlled cookies/analytics possible | Donation page | Donations | Buy Me a Momo | Site processes data under its own policy |
| Google Ads endpoints | Ad load/show (Premium off) | **Automatic** | SDK-controlled | Ads | Advertising | Google | Yes — production declaration pending |
| `https://voratube.vercel.app/privacy-policy` | Privacy Policy tile tap | User-initiated | Browser request | Policy page | Legal disclosure | Self-hosted Vercel site | No |

## Encryption in transit

- All VoraTube-controlled endpoints use **HTTPS** (`Uri.https` / `https://` constants); no cleartext endpoints; `usesCleartextTraffic` not enabled and no network security config overrides defaults (cleartext blocked by default on API 28+).
- LRCLIB, iTunes, Vercel: developer-controlled HTTPS — "encrypted in transit" = **Yes** for data sent there.
- Google Mobile Ads SDK and WebView traffic: transport controlled by SDK/site; Google's SDK uses TLS per its documentation — `UNKNOWN — REQUIRES MANUAL VERIFICATION` (vendor docs).

## Collected vs shared classification

- **LRCLIB / iTunes (automatic):** App-driven transmission to a third party that processes data as a service provider for the developer's feature. Under Google's definition this is **collection** (transmission off-device by the app) and must be declared by the developer; it is **not "sharing"** (no independent-purpose transfer by VoraTube; Apple/LRCLIB act on the request).
- **Google Mobile Ads:** SDK transmits data to Google for Google's independent purposes (ad delivery, measurement). This is generally both **collection** and **sharing** under Google's guidance once production ads run. With the current TEST configuration, ad traffic does not serve real end users in production; final declaration is deferred to the production AdMob/UMP task.
- **YouTube / Buy Me a Momo:** User-initiated handoff to an external service/browser. Not app-driven collection of user data by VoraTube; document as user-initiated external action.
- **Local-only data (library, playlists, history, etc.):** **Not collected** — never leaves the device (other than the specific metadata fields listed above).

## Data Safety proposed mapping (draft for Play Console)

| Data type | Collected? | Shared? | Local only? | Required/Optional | Purpose | Evidence | Confidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| App activity — App interactions (song title/artist/album metadata sent for lookups) | Yes (automatic) | No | — | Optional feature (app functions without network) | App functionality (lyrics, genre) | `lrclib_client.dart`, `genre_enrichment_service.dart` | High |
| App activity — In-app search history / user content | No (stays on device) | No | Yes | — | Local features | Drift DB audit | High |
| Audio files | No (never transmitted) | No | Yes | Required for core function | Playback | MediaStore audit | High |
| Files and docs | No | No | Yes | — | Local import | file_picker usage | High |
| Device or other identifiers (Advertising ID etc.) | `UNKNOWN — REQUIRES MANUAL VERIFICATION` (Google Mobile Ads SDK; test config today) | `UNKNOWN — REQUIRES MANUAL VERIFICATION` | — | — | Advertising | SDK docs | Low — vendor docs |
| App info and performance — Diagnostics/crash logs | No first-party collection | No | — | — | — | Verified absent | High (first-party) |
| Location | No | No | — | — | — | No location code/permissions | High |
| Personal info (name, email, user IDs) | No | No | — | — | — | No accounts | High |
| Financial info (payment info) | No | No | — | — | — | No payment code; donations external | High |
| Photos and videos / Contacts / Calendar / SMS | No | No | — | — | — | No code/permissions | High |
| Web browsing | Not collected by VoraTube; WebView/YouTube handled by external sites | No | — | — | — | `donation_screen.dart`, `song_actions.dart` | High |

## Retention / deletion

- Local app data: retained until in-app deletion (songs, playlists, user LRC), "clear app data", or uninstall. Uninstall removes all app-private data (DB, caches, preferences).
- No server-side user data exists → no server-side deletion workflow and no account deletion requirement.
- Third-party retention (LRCLIB, Apple, YouTube, Buy Me a Momo, Google ads) is governed by those parties' policies — outside VoraTube's control.
- Android Auto Backup may retain an encrypted copy of app data on Google's backup infrastructure (default `allowBackup=true`) — `UNKNOWN — REQUIRES MANUAL VERIFICATION`; note as "data deletion mechanisms" when completing the form.

## Accounts / cloud

- `No account creation/authentication found.` No OAuth, Sign-In, email collection, profiles, or backends.
- No Firebase/Supabase/Appwrite/S3/Drive/Dropbox/sync code (verified absent by search).
- Music files, playlists, favorites, history, settings, lyrics, artwork are **not uploaded** anywhere.

## Privacy policy consistency check

| Practice | Disclosed in `PRIVACY_POLICY.md`? | Verdict |
| --- | --- | --- |
| Local storage of library/playlists/history/settings/premium/caches | §2 | Accurate |
| No uploads of music/audio files | §2, §3, §9 | Accurate |
| LRCLIB automatic lookup (title/artist/album) | §4 | Accurate |
| iTunes automatic lookup (title/artist) | §4 | Accurate |
| YouTube user-initiated search | §4 | Accurate |
| Buy Me a Momo WebView, third-party policy | §4, §12 | Accurate |
| Test-only advertising; production later; Premium disables ads | §5 | Accurate |
| No analytics / crash reporting / accounts | §6, §7 | Accurate |
| HTTPS, no absolute security claims | §9 | Accurate |
| Retention/deletion incl. Android consent flow; third-party retention | §10 | Accurate |
| **Android Auto Backup of local data** | **Not mentioned** | **Minor gap** — recommended one-sentence addition to §2/§10 noting Android may include app data in device backups governed by Android/Google policies |
| Ringtone MediaStore registration | §2 | Accurate |

No policy statement was found to be false or misleading. The recommended backup-sentence correction is optional and was **NOT** applied in this audit-only task.

## Manual verification required (checklist)

1. Google Mobile Ads SDK data types for `google_mobile_ads 9.1.0` — check Google's SDK "Data disclosure" documentation (Advertising ID, approximate location, app interactions, diagnostics) and whether test-config traffic is exempt from declaration.
2. Finalize Data Safety answers **after** the production AdMob/UMP task if production advertising will be enabled before submission.
3. Confirm resolved `targetSdk` in a built artifact (`flutter.targetSdkVersion`).
4. Confirm Android Auto Backup behavior on a real device (does a restore bring back history/playlists?) and decide later whether `dataExtractionRules`/`allowBackup=false` is wanted.
5. Donation WebView third-party behavior (cookies/analytics on `buymemomo.com`) — site-side, not verifiable from this repository.
6. LRCLIB/Apple retention practices for received metadata (their policies).
7. Re-run this audit after any dependency change.

## Play Console preparation notes (not answers — inputs)

- "Does your app collect or share any of the required data types?" → **Yes** (App activity via automatic metadata lookups; plus ad SDK data once production ads are live — see checklist).
- Data deletion mechanism → local: uninstall/clear-data/in-app deletion; no server-side mechanism to declare.
- Privacy policy URL → `https://voratube.vercel.app/privacy-policy`.
- Encryption in transit → Yes for all developer-controlled flows.
- Do not answer advertising-identifier questions until the AdMob/UMP task is complete.






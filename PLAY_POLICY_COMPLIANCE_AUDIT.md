# VoraTube Google Play Policy & Technical Compliance Audit

## Audit date

September 3, 2026

## Executive summary

**READY WITH WARNINGS.**

No policy BLOCKER was found. VoraTube is a local-first music player with narrowly scoped permissions, a legitimate media-playback foreground service, no accounts/analytics/cloud, an accurate published privacy policy, and a compliant target API. Remaining items before submission: (1) the WRITE_SETTINGS flow should route users to the special-access settings screen instead of only showing an error, (2) production AdMob/UMP decisions must be made before enabling real ads (current build is test-ads-only), (3) standard Play Console declarations (Data Safety, content rating, listing assets) still need to be completed, (4) a few verification-only items.

## Severity definitions

- **BLOCKER** — likely prevents submission, violates a requirement, or creates serious policy risk.
- **FIX REQUIRED** — should be addressed before submission.
- **WARNING** — not necessarily blocking but should be reviewed.
- **MANUAL VERIFICATION** — cannot be established conclusively from repository inspection.
- **PASS** — no issue found.

## Repository baseline

| Item | Value | Source |
| --- | --- | --- |
| Branch / commit | `main` @ `76c656e` | git |
| Working tree | 4 pre-existing modified files + untracked `shot1.png` (unrelated, preserved) | `git status` |
| App version | 1.1.6+10 | `pubspec.yaml` |
| Application ID | `com.piyushbaniya.vora_tube` | `build.gradle.kts` |
| Flutter | 3.47.1 stable (2026-08-19) | `flutter --version` |
| Java | 17 (source/target compatibility) | `build.gradle.kts` |
| compileSdk | 37 (explicit) | `build.gradle.kts` |
| targetSdk | 36 — Flutter 3.47.1 default (`FlutterExtension.kt`), not overridden | Flutter toolchain source |
| minSdk | 24 (explicit) | `build.gradle.kts` |
| Release build | minify + shrinkResources on, R8 optimize rules, signed via `key.properties` | `build.gradle.kts` |

## Target API

**PASS.** Google Play requires new apps and app updates to target API level 36 (Android 16) as of August 31, 2026 (source: https://developer.android.com/google/play/requirements/target-sdk, last updated 2026-08-14). VoraTube resolves to targetSdk 36 (Flutter 3.47.1 default) with compileSdk 37 — compliant. Confirm the resolved value in a built AAB manifest (`MANUAL VERIFICATION`).

## Permissions

| Manifest item | Current state | Why it exists | Play policy relevance | Status |
| --- | --- | --- | --- | --- |
| `READ_MEDIA_AUDIO` | Declared; runtime-requested on first launch via PermissionGate | Read user's local music via MediaStore | Photo/video/audio permission policy — core, justified use | PASS |
| `READ_EXTERNAL_STORAGE` (maxSdk 32) | Declared, capped to Android ≤12 | Same purpose on older OS | Correctly version-capped | PASS |
| `INTERNET` | Declared | Lyrics/genre lookups, ads, WebView, links | Normal | PASS |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | Declared; `AudioService` with `foregroundServiceType="mediaPlayback"` | Background playback | Correct type for media playback | PASS |
| `WAKE_LOCK` | Declared | Playback continuity | Normal | PASS |
| `WRITE_SETTINGS` | Declared; special access checked at use time | Ringtone assignment via `RingtoneManager` | Narrowly scoped special access — see WRITE_SETTINGS | WARNING |
| Restricted/sensitive permissions (MANAGE_EXTERNAL_STORAGE, location, contacts, camera, microphone, SMS, call log, phone, calendar, Bluetooth, POST_NOTIFICATIONS, accessibility, VPN, device admin, REQUEST_INSTALL_PACKAGES, SYSTEM_ALERT_WINDOW, SCHEDULE_EXACT_ALARM, QUERY_ALL_PACKAGES) | **Absent** (manifest inspection + code search; only `queries` entry is Flutter's PROCESS_TEXT) | — | None present | PASS |
| Components | `MainActivity` (exported launcher), `AudioService` (exported, mediaPlayback, MediaBrowserService), `MediaButtonReceiver` (exported, MEDIA_BUTTON) — standard audio_service architecture | Playback | Standard, expected | PASS |
| Backup/network config | No `allowBackup`/`dataExtractionRules`/`usesCleartextTraffic`/`networkSecurityConfig` → Android defaults (backup enabled, cleartext blocked) | — | Backup disclosure consideration | MANUAL VERIFICATION |

## Storage/media access

**PASS.** The app scans MediaStore (audio rows with a MIME whitelist and minimum-duration filter), reads title/artist/album/duration/genre/date-modified/size/path/IDs plus artwork, plays local audio, imports user-selected files via `file_picker`, and deletes media through Android's consent mechanisms (`MediaStore.createDeleteRequest` on API 30+, direct delete below). `READ_MEDIA_AUDIO` is requested only when needed (first-launch gate), with an in-app purpose explanation, and is genuinely required for core functionality. `MANAGE_EXTERNAL_STORAGE` is absent.

## WRITE_SETTINGS

**FIX REQUIRED (pre-submission recommendation).**
- Exact feature: ringtone cutter (`VoraTubeAudioUtilBridge.kt`). After cutting, it checks `Settings.System.canWrite(context)`; if denied it throws `CutFailed("write_settings_denied", ...)`, surfaced in Dart (`audio_util_service.dart:48-50`) as an error message naming the "Modify system settings" permission.
- User-initiated: yes — only when the user creates a ringtone.
- Necessity: `RingtoneManager.setActualDefaultRingtoneUri` requires it; the design deliberately avoids the system picker.
- Narrow scope: only the default ringtone is changed; no unrelated system settings are touched.
- **Gap:** when the permission is missing, the app only reports an error — it does **not** send the user to the special-access settings screen (`ACTION_MANAGE_WRITE_SETTINGS`). A user who has not pre-granted the setting cannot complete the flow. Recommended fix (separate task): route the user to the special-access settings when `canWrite` is false, then continue. No change made in this audit.

## Foreground services

**PASS.** `com.ryanheise.audioservice.AudioService` is declared with `android:foregroundServiceType="mediaPlayback"` plus `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_MEDIA_PLAYBACK` — the exact configuration Android 14+ requires for media playback. `MainActivity` extends `AudioServiceActivity`. The service exists solely for playback with media notifications and controls; it stops when playback ends; no unrelated work is performed in it. Android 15/16 impose no additional requirements beyond the correct type/permission for this case (per Android foreground-service documentation).

## Background playback

**PASS.** audio_session configures audio focus; the foreground service + notification run only during playback; wake locks are plugin-managed; no persistent services unrelated to playback; the only background network activity is the app's own automatic metadata lookups (LRCLIB genre enrichment is TTL/suppression-capped with a 3s timeout; lyrics fetch occurs only in the lyrics UI when lyrics are missing).

## Advertising

- **Current test-ad state (code-verified):** Google Mobile Ads `9.1.0`; banner (`VoraTubeBannerAd`) + interstitial; `MobileAds.instance.initialize()` once at startup, skipped when Premium is active; Google official **test** IDs in `ads_config.dart` (`useTestAds = true`) and the manifest; no mediation; no UMP; no personalized/non-personalized request configuration; no remote config; Premium disables all ad placements and no ad requests are made.
- **Placement review:** the banner sits at the top of Settings (not over playback controls); interstitials are gated by the premium state and are not shown during active music playback; no ads over critical UI, no deceptive ad UIs; ads are SDK-rendered and distinguishable from app controls.
- **Future production-ad requirements:** set real AdMob app/banner/interstitial IDs (`ads_config.dart` + manifest), set `useTestAds = false`, and complete Data Safety advertising declarations.
- **UMP/consent requirements:** required before serving ads to EEA/UK users (Google's EU user consent policy); must be added in a dedicated task before production ads.
- **Data Safety implications:** ad-SDK data types must be declared once production advertising is enabled; until then the app ships test ads only.
- Source: Google Play Developer Program Policies — Ads; Google Mobile Ads SDK documentation.

## Privacy Policy

**PASS.** `PRIVACY_POLICY.md` and the live page `https://voratube.vercel.app/privacy-policy` (verified reachable on Sept 3, 2026; public HTML, no login) match the code: local storage, no uploads, LRCLIB/iTunes automatic lookups vs user-initiated YouTube/Buy Me a Momo, test-only advertising, no analytics/crash/accounts, retention/deletion, children's privacy, contact (Piyush Das / baniyapiyushwork@gmail.com). The app links the policy centrally via `kPrivacyPolicyUrl` (single constant), opening externally with failure handling. One minor gap (not a false claim): Android Auto Backup of local data is not mentioned in the policy — see Data Safety.

## Data Safety

**PASS (with the existing open checklist).** `DATA_SAFETY_AUDIT.md` conclusions re-verified against the source: LRCLIB, iTunes, YouTube, Buy Me a Momo, AdMob, identifiers, absence of analytics/crash reporting/accounts/cloud all still match. Open items remain the ad-SDK vendor-doc verification and backup behavior — already tracked in that document's manual checklist. Nothing needed correction.

## External services

**PASS.** All external endpoints inventoried: `lrclib.net/api` (auto), `itunes.apple.com/search` (auto), `youtube.com/results` (user-initiated external browser), `buymemomo.com` (user-initiated WebView), `voratube.vercel.app/privacy-policy` (user-initiated), Google Ads endpoints (SDK). Repository-wide `http`/`https` search found no additional domains. The app does not claim ownership of third-party content ("Find on YouTube" opens YouTube's own search; the donation page is labeled "Buy Me a Momo donation").

## Copyright/IP risk

**PASS with one WARNING.** VoraTube hosts nothing: no server, no uploads, no downloads, no audio extraction from third-party platforms, no DRM circumvention, no embedded third-party music. All playback is of files already on the user's device (MediaStore) or files the user imports. "Find on YouTube" merely opens YouTube's own search in the user's browser — it does not stream, download, or extract content. No YouTube/Spotify/Google branding is used to imply official status. **WARNING:** the app name "VoraTube" ends in "-Tube" and is visually reminiscent of "YouTube"; it is a distinct name for a distinct local player and uses no YouTube logo/colors/branding, but the similarity could attract a metadata/trademark review question. Recommend keeping store descriptions explicit that VoraTube is a local music player and is not affiliated with YouTube (listing-copy task).

## Deceptive behavior

**PASS.** The app describes itself as a local-first music player (pubspec description, in-app headers); all features are functional (verified via 505 passing tests); no fake buttons/system dialogs; Premium is an honest local ad-removal entitlement with clear activation/disable flows; the donation destination is labeled; external links are labeled; no impersonation of other apps/services.

## Children's / Families

**PASS (general audience).** No child-directed content, branding, or marketing exists in the repository; functionality (local music, ringtone cutter, stats) targets general audiences. Target audience should be declared as general (not child-directed) in Play Console; if advertising is later enabled, the Families/ads requirements only apply if targeting children — not the case here. No target-audience settings were changed.

## User-generated content

**PASS.** Users create playlists, favorites, and can upload local .lrc lyrics — all stored **privately on-device only**; there is no sharing, posting, or publicly accessible content of any kind, so UGC moderation/reporting requirements for public UGC do not apply.

## App access / reviewer access

**PASS.** No login, account, credentials, subscription, or special hardware is required. A reviewer only needs to grant the "Music and audio" permission (with a clear in-app explanation) to use the core app; lyrics/genre lookups need internet; the ringtone feature needs the "Modify system settings" special access (currently shows an explanatory error if not granted — see WRITE_SETTINGS). `No special reviewer account appears required.`

## Security

**PASS (one note).**
- `SECRET FOUND — DO NOT EXPOSE` — signing credentials exist locally in `android/key.properties` and `android/upload-keystore.jks`; both are listed in `.gitignore` and are **not** tracked by git (verified via `git ls-files`). Contents not inspected. This is the correct handling.
- No hardcoded API keys or tokens in Dart/Kotlin (test AdMob IDs are Google's public test IDs by design).
- No cleartext traffic configuration; all developer endpoints HTTPS.
- Exported components are only the standard launcher activity, media browser service, and media button receiver (required for playback control); `MainActivity` registers 5 local method-channel bridges (ingest, storage, audio-util, volume booster, media-delete) — no network, no arbitrary intents, no WebView in native code.
- No JavaScript interfaces registered on the WebView; file access APIs not enabled.
- No sensitive-information logging found in first-party code.

## Release build

**PASS (with verification item).** Release build type: minify + resource shrinking enabled with `proguard-android-optimize.txt` plus project rules (documented as covering Flutter/just_audio/audio_service); signing config loaded from `key.properties` (present locally, untracked); `debuggable` not set (defaults false); version 1.1.6+10 from pubspec; test ad IDs intentionally used until production config. No manifest placeholders. Nothing found that would block Play upload; a real signed-AAB build test remains (future task).

## Dependencies/SDKs

**PASS (no action required now).** 17 direct dependencies inventoried in `DATA_SAFETY_AUDIT.md`; all current major versions from pub.dev with no known Play-policy issues. `google_mobile_ads 9.1.0` is the only SDK with policy implications (advertising — handled via future UMP/production task). No abandoned libraries, hidden analytics, tracking, or extra ad SDKs found. No upgrades performed or required for this audit.

## WebViews

**WARNING (accept as-is or harden later).** One WebView: donation screen loads `https://buymemomo.com/piyushbaniya` after a connectivity pre-check, with a labeled header and retry/error states — the user understands they are viewing the donation site. JavaScript is unrestricted (needed for the payment page); the navigation delegate only tracks progress/errors — **navigation is not domain-restricted** (links followed inside the WebView load in-app); no JavaScript interfaces are registered; no file-access APIs enabled; cookies/storage are the site's own. Recommended (optional, later task): open external-site links in the browser or restrict navigation to the donation domain. Not a policy blocker because the site is clearly identified and user-initiated.

## Permission disclosures

**PASS.** `PermissionGate` shows a first-launch screen explaining that VoraTube needs "access to your music and audio files to build your local library. Your music stays on this device." with an affirmative "Allow access to music" button, a permanently-denied variant directing to system settings, and denial handled gracefully (permission-gate cases are covered by tests). WRITE_SETTINGS disclosure exists but lacks a route to the special-access screen (see WRITE_SETTINGS).

## Accessibility/basic quality

**PASS (basic level).** 505 tests pass covering core flows; permission-denied paths are handled without crashes; error states exist for offline lyrics, failed deletes, and WebView failures; URL launches are failure-safe. Full accessibility/screen-reader and visual QA remain manual (`MANUAL VERIFICATION`).

## Store listing readiness

Missing items for a future listing (nothing created in this task):
- App name final decision + 30-char short description + full description
- Feature graphic (1024×500), phone screenshots (min 2), 512×512 icon (launcher icon exists in repo)
- Content rating questionnaire answers (IARC)
- Data safety form completion
- Target audience declaration
- App category selection
- Support email (baniyapiyushwork@gmail.com available) and optional website link (`https://voratube.vercel.app/`)
- App access instructions for reviewers (only: grant music permission)

## Blockers

`None found.`

## Fixes required

1. **WRITE_SETTINGS flow** — when `Settings.System.canWrite` is false, route the user to the "Modify system settings" special-access screen (e.g. an `ACTION_MANAGE_WRITE_SETTINGS` intent through the existing native bridge) instead of only showing an error. Recommended before submission; small, isolated change.

## Warnings

1. App name "VoraTube" similarity to "YouTube" — keep store copy explicit about being a local, unaffiliated player.
2. Donation WebView allows unrestricted in-app navigation — consider restricting to the donation domain or opening external links externally (later task).
3. Android Auto Backup includes app data by default (no `allowBackup`/`dataExtractionRules` override) — verify on-device and consider an explicit backup policy in a later task; also add a one-sentence backup mention to the privacy policy.
4. Interstitial ad UX should be re-reviewed when production ads are enabled.

## Manual verification

1. Resolved targetSdk in a built AAB manifest (`flutter.targetSdkVersion` = 36 from toolchain source, but confirm in the artifact).
2. Android Auto Backup restore behavior on a real device.
3. `buymemomo.com` third-party behavior inside the WebView.
4. Google Mobile Ads SDK 9.1.0 data-disclosure documentation (for the future Data Safety submission).
5. Full accessibility pass and visual QA on devices.
6. AGP/Gradle/Kotlin plugin versions as resolved at build time (managed by the Flutter template).

## Already compliant

- Target API level (36) and compileSdk (37)
- Photo/video/audio permission scope and runtime disclosure
- Foreground-service media playback architecture
- Version-capped legacy storage permission; no dangerous permissions
- Media deletion with Android consent flow
- Privacy policy: content, hosting, and in-app linking
- Local-first architecture: no accounts, analytics, crash reporting, cloud, uploads
- Security posture: no exposed secrets, no cleartext, no dangerous exported components
- Honest functionality and labeling (no deceptive behavior)
- UGC confined to private local storage

## Recommended order of future work

1. Fix the WRITE_SETTINGS special-access routing (small, isolated).
2. Production AdMob setup + UMP consent (dedicated task), then update the advertising section of the privacy policy and Data Safety.
3. Decide on backup policy (`allowBackup`/`dataExtractionRules`) and add the backup sentence to the privacy policy.
4. Complete the Data Safety form using `DATA_SAFETY_AUDIT.md` + this audit.
5. Prepare store listing assets and copy (including explicit "local player, not affiliated with YouTube" wording).
6. Content rating questionnaire and target audience declaration.
7. Build the final signed AAB and run a full device test pass.





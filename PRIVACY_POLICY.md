# VoraTube Privacy Policy

**Effective date:** September 3, 2026

VoraTube is an Android music player application ("the App") developed by Piyush Das ("we", "us", "our"). This Privacy Policy explains what information the App accesses, what it stores on your device, what it transmits over the internet, and which third-party services are involved.

The short version: **your music files and your listening data stay on your device.** VoraTube has no user accounts, no cloud music storage, and no server-side user profiles. The App does send small, non-identifying song details (such as a song title and artist name) to third-party lookup services so it can show lyrics and genres, and it displays ads unless you activate Premium. Everything else is described below.

## 1. Information VoraTube accesses

VoraTube accesses only what it needs to work as a local music player:

- **Audio files already on your device.** VoraTube reads music that already exists in your device's music library (through Android's MediaStore) or files you explicitly import yourself using the file picker.
- **Audio file metadata.** Song title, artist, album, duration, genre, and embedded artwork read from your own files, used to build and display your library.
- **Playback state.** Which song is playing, your queue, your playback position, your playlists, your favorites, and your play history — all created by your own use of the App.
- **Settings you choose in the App** (for example appearance and playback preferences).

VoraTube does **not** access your contacts, location, camera, microphone, photos, messages, or any other information unrelated to music playback.

## 2. Information stored locally on your device

VoraTube keeps a local database and cache on your device. This may include:

- your local library metadata (songs, albums, artists, genres)
- playlists and favorites
- playback history and playback statistics
- queue state and playback position
- your in-app settings
- your Premium activation state
- a cache of lyrics you have viewed
- cached artwork thumbnails
- any ringtone you create with the ringtone cutter (stored in app storage and registered in your device's media library under "Ringtones/VoraTube")

All of this information stays on your device. **VoraTube does not operate a server, cloud storage, or cloud backup for your music, playlists, history, or any other personal data.** VoraTube does not upload your audio files anywhere.

## 3. Music and media permissions

- On Android 13 and newer, VoraTube requests the **"Music and audio"** permission (`READ_MEDIA_AUDIO`) so it can find and play the music on your device.
- On older Android versions it may request **storage access** (`READ_EXTERNAL_STORAGE`) for the same purpose.
- Your music files are **not uploaded** to VoraTube or to VoraTube's servers. There are no VoraTube servers holding your music.
- If you use the ringtone cutter, VoraTube uses the **"Modify system settings"** permission (`WRITE_SETTINGS`) only at your request, to set the cut audio as your ringtone. VoraTube does not change any other system settings.

## 4. Network communications

VoraTube needs an internet connection for a small number of features. It never transmits your audio files over the network. The network features fall into two groups:

**Automatic, background lookups (small song metadata only):**

- **Lyrics — LRCLIB.** When lyrics for a song are not already embedded in the file or cached on your device, VoraTube may send that song's **title, artist, and album** to the public LRCLIB lyrics service (`https://lrclib.net/api`) to fetch matching lyrics. Results are cached on your device. If the request fails, playback continues normally without lyrics. VoraTube never uploads your music files to LRCLIB.
- **Genre enrichment — Apple iTunes Search API.** For songs that have no genre information, VoraTube may send the song's **title and artist** to Apple's iTunes Search API (`https://itunes.apple.com/search`) to look up a genre label. Results are cached locally with a short timeout. VoraTube never uploads your music files to Apple.

**User-initiated actions (only when you tap them):**

- **"Find on YouTube."** When you choose this action for a song, VoraTube opens a YouTube search in your browser or the YouTube app, using that song's title and artist as the search terms. No search happens automatically.
- **Donation page ("Buy Me a Momo").** When you open the donation screen, VoraTube loads the Buy Me a Momo page (`https://buymemomo.com/piyushbaniya`) inside an in-app browser view. VoraTube does not control that website and is not responsible for data it collects; when you interact with it, that service handles your information under its own privacy policy.

## 5. Advertising (current status)

VoraTube integrates the **Google Mobile Ads SDK** to show banner and interstitial advertisements.

- **Current status:** the App is still using Google's **official test advertisements** in its development configuration. Production advertising, including any consent-management flow, is not yet configured and will be introduced in a future update, at which point this policy will be updated accordingly.
- When ads are shown, Google and its partners may collect and process information (such as device identifiers and advertising identifiers) under **Google's own Privacy Policy**: https://policies.google.com/technologies/ads
- If you activate **Premium**, all ad placements in VoraTube are disabled and no ad requests are made. Premium is a local entitlement activated within the App; it involves no payment processing by or account system in VoraTube itself.

## 6. Analytics and crash reporting

VoraTube does **not** include its own analytics service and does **not** include its own crash-reporting service. VoraTube does not build user profiles and does not track you across apps or websites.

Note that the advertising SDK described in Section 5 is a third-party component and may perform its own measurement as described by Google's policies.

## 7. Accounts

VoraTube has **no user accounts, no login system, and no cloud account**. There is no account deletion workflow because there are no accounts. If you uninstall the App, there is no VoraTube-side data left behind, because VoraTube holds no data outside your device.

## 8. Data sharing

VoraTube itself does not sell, rent, or share your personal data, because it does not collect personal data on any server. Information leaves your device only in the limited ways described above:

- song title/artist/album sent to LRCLIB for lyrics;
- song title/artist sent to Apple's iTunes Search API for genre lookup;
- a YouTube search you explicitly trigger;
- the donation webpage you explicitly open;
- data processed by Google's advertising SDK when ads are displayed (test ads in the current configuration).

Each of those third parties processes information under its own privacy policy. VoraTube does not control their practices.

## 9. Data security

- Your VoraTube data is stored locally on your device under Android's standard app sandboxing, which prevents other apps from reading it without your device's permissions.
- Communications with the lookup services and web pages described in this policy use HTTPS.
- VoraTube does not upload your music library or audio files to any server, and does not operate cloud storage for user music.
- No method of transmission or storage is perfectly secure. VoraTube does not claim that its security measures, or those of your device or of third-party services, are infallible.

## 10. Data retention and deletion

**Local data.** Your local VoraTube data (library metadata, playlists, history, queue, settings, caches) remains on your device until you:

- delete it through the App's available functionality (for example deleting songs, playlists, or hidden tracks),
- clear the App's data in your device settings, or
- uninstall the App (which removes all VoraTube app data from your device).

Where VoraTube deletes media on your behalf (such as deleting a song), it follows Android's standard storage and media deletion mechanisms, including Android's own user-consent confirmation where required.

**Third-party data.** VoraTube cannot delete data retained by third parties such as LRCLIB, Apple, YouTube, Buy Me a Momo, or Google's advertising infrastructure. Their retention practices are governed by their respective privacy policies.

## 11. Children's privacy

VoraTube is a general-audience local music player. It does not knowingly collect personal information from anyone, including children under 13, because it does not operate accounts or servers. If you are a parent or guardian and believe a child has provided information to one of the third-party services described above, please contact that service directly, or contact us using the details below.

## 12. Third-party services summary

| Service | Purpose | When | What is sent |
| --- | --- | --- | --- |
| LRCLIB (lrclib.net) | Lyrics lookup | Automatic, best-effort | Song title, artist, album |
| Apple iTunes Search (itunes.apple.com) | Genre lookup | Automatic, best-effort | Song title, artist |
| YouTube | "Find on YouTube" action | Only when you tap it | Song title and artist as a search query |
| Buy Me a Momo (buymemomo.com) | Donations | Only when you open it | Whatever the website itself processes |
| Google Mobile Ads | Advertising | When ads are shown (Premium off) | As described by Google's ad policies |

These services are governed by their own privacy policies; VoraTube is not responsible for their content or practices.

## 13. Changes to this privacy policy

We may update this privacy policy as VoraTube evolves (for example when production advertising is introduced). The "Effective date" at the top will be updated, and the current version will always be available at the policy URL linked from the App and from the Google Play listing.

## 14. Contact information

If you have questions about this privacy policy or about VoraTube's data practices, contact:

- **App:** VoraTube
- **Developer:** Piyush Das
- **Privacy contact:** baniyapiyushwork@gmail.com

---

*This policy describes the current version of VoraTube. The published version is available at https://voratube.vercel.app/privacy-policy.*


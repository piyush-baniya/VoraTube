import 'package:firebase_analytics/firebase_analytics.dart';

/// VoraTube's single, centralized Firebase Analytics facade.
///
/// Every analytics event in the app flows through this class — no feature
/// sends raw [FirebaseAnalytics] calls directly.
///
/// Analytics is strictly best-effort and **never critical**: it must not
/// block startup, playback, library scanning, database work, UI or ads. If
/// Firebase is unavailable or a call fails, the service degrades to a no-op
/// and the music player keeps working exactly as before.
///
/// ## Privacy
/// Events carry only small categorical parameters (booleans, repeat-mode
/// strings, ad outcome). Personal or local-music data is intentionally never
/// logged: no song/artist/album names, no filenames, no file paths, no
/// MediaStore URIs, no playlist names, no lyrics text, no search queries,
/// no emails and no location.
class AnalyticsService {
  AnalyticsService._();

  /// Process-wide singleton.
  static final AnalyticsService instance = AnalyticsService._();

  /// The analytics handle; null when initialization failed or Firebase is
  /// unavailable, which makes every event a silent no-op.
  FirebaseAnalytics? _analytics;

  bool _initialized = false;

  /// Wires up Firebase Analytics (after [Firebase.initializeApp] has been
  /// attempted). Failures are swallowed: Analytics never blocks the app.
  void initialize() {
    if (_initialized) return;
    _initialized = true;
    try {
      _analytics = FirebaseAnalytics.instance;
    } catch (_) {
      _analytics = null;
    }
  }

  /// Fires a named event with optional categorical parameters.
  ///
  /// Callers must only pass small, non-personal categorical values. Any
  /// failure (native channel error, plugin missing, uninitialized Firebase)
  /// is swallowed so a telemetry problem can never surface to the app.
  Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      await analytics.logEvent(name: name, parameters: parameters);
    } catch (_) {
      // Analytics is non-critical.
    }
  }

  /// A distinct song actually started playing.
  void trackPlayed() => logEvent('track_played');

  /// The user (or a system media control) moved to the next track.
  void trackNext() => logEvent('track_next');

  /// The user (or a system media control) moved to the previous track.
  void trackPrevious() => logEvent('track_previous');

  /// The shuffle toggle changed state.
  void shuffleChanged(bool enabled) =>
      logEvent('shuffle_enabled', parameters: {'enabled': enabled});

  /// The repeat mode changed. [mode] is one of `off`, `all`, `one`.
  void repeatChanged(String mode) =>
      logEvent('repeat_changed', parameters: {'mode': mode});

  /// The lyrics surface was opened for the current song.
  void lyricsOpened() => logEvent('lyrics_opened');

  /// A user-supplied `.lrc` file was stored as the song's lyrics.
  void lyricsUploaded() => logEvent('lyrics_uploaded');

  /// A new playlist was created.
  void playlistCreated() => logEvent('playlist_created');

  /// One or more songs were added to a playlist.
  void playlistSongAdded() => logEvent('playlist_song_added');

  /// One or more songs were removed from a playlist.
  void playlistSongRemoved() => logEvent('playlist_song_removed');

  /// A non-empty search was submitted.
  void searchUsed() => logEvent('search_used');

  /// The user started the "set as ringtone" flow.
  void setRingtoneStarted() => logEvent('set_ringtone_started');

  /// A ringtone was successfully assigned.
  void setRingtoneCompleted() => logEvent('set_ringtone_completed');

  /// An interstitial ad was actually shown.
  void adInterstitialShown() => logEvent('ad_interstitial_shown');

  /// An interstitial ad failed to load or to show.
  void adInterstitialFailed() => logEvent('ad_interstitial_failed');

  /// A banner ad finished loading.
  void adBannerLoaded() => logEvent('ad_banner_loaded');

  /// A banner ad failed to load.
  void adBannerFailed() => logEvent('ad_banner_failed');
}
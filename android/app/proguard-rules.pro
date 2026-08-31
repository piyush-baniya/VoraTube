# VoraTube R8 rules. Flutter's Gradle plugin injects its own default rules;
# plugins used here (just_audio, audio_service, webview_flutter, share_plus,
# url_launcher, file_picker, permission_handler, drift) keep their
# Manifest-referenced entry points automatically via AAPT keep rules.

# ── AdMob / google_mobile_ads ────────────────────────────────────────────
# The Mobile Ads SDK uses reflection. Keep all of its classes and their
# metadata in release builds.
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# ── AndroidX WorkManager / Room / SQLite ─────────────────────────────────
# google_mobile_ads pulls in androidx.lifecycle:lifecycle-process, which
# transitively depends on androidx.work. WorkManager builds its internal
# androidx.work.impl.WorkDatabase via Room, and R8 minification strips the
# generated Room schema/entity classes used through reflection, causing a
# startup crash ("Failed to create an instance of
# androidx.work.impl.WorkDatabase"). Keep those classes so the database can
# be created on release builds.
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-keep class androidx.sqlite.** { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
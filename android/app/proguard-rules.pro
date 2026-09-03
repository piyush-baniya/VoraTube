# ── audio_service / just_audio / ExoPlayer ───────────────────────────────
# The media notification + background playback path reaches these classes
# through the manifest-declared AudioService/MediaButtonReceiver and through
# platform channels, not through direct Dart references R8 can trace. Release
# minification (isMinifyEnabled = true) must not strip or rename them, or the
# release build loses its playback notification/service while debug keeps
# working. The string-referenced notification drawables are additionally
# pinned in res/values/keep.xml so resource shrinking keeps them too.
-keep class com.ryanheise.** { *; }
-dontwarn com.ryanheise.**
-keep class androidx.media.** { *; }
-dontwarn androidx.media.**
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

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
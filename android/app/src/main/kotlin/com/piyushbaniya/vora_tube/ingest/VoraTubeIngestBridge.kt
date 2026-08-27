package com.piyushbaniya.vora_tube.ingest

import android.content.Context
import android.content.ContentUris
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class VoraTubeIngestBridge(context: Context) {

    private val appContext = context.applicationContext
    private val resolver = appContext.contentResolver
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()

    @Volatile
    private var genreByAudioId: Map<Long, String>? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            executor.execute {
                try {
                    when (call.method) {
                        "prepareScan" -> {
                            genreByAudioId = null
                            succeed(result, null)
                        }
                        "getAudioBatch" -> {
                            val afterId =
                                (call.argument<Number>("afterId") ?: 0L).toLong()
                            val limit = (call.argument<Number>("limit") ?: 500)
                                .toInt()
                                .coerceIn(1, MAX_BATCH)
                            succeed(result, getAudioBatch(afterId, limit))
                        }
                        "resolveArtwork" -> {
                            val targets = call.argument<List<Map<String, Any?>>>("targets")
                                ?: emptyList()
                            succeed(result, resolveArtwork(targets))
                        }
                        else -> fail(result, "unsupported_method", call.method)
                    }
                } catch (e: Exception) {
                    fail(result, "ingest_error", e.message ?: "unknown")
                }
            }
        }
    }

    private fun getAudioBatch(afterId: Long, limit: Int): List<Map<String, Any?>> {
        val projection = mutableListOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.TRACK,
            MediaStore.Audio.Media.YEAR,
            MediaStore.Audio.Media.DATE_MODIFIED,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.ARTIST_ID,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.SIZE,
        )
        val optionalColumns = listOf(
            "album_artist",
            MediaStore.Audio.Media.DATE_ADDED,
        )
        val optionalIndices = mutableMapOf<String, Int>()
        for (column in optionalColumns) {
            if (!projection.contains(column)) {
                projection.add(column)
            }
        }

        val rows = ArrayList<Map<String, Any?>>(limit)
        resolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection.toTypedArray(),
            "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND ${MediaStore.Audio.Media._ID} > ?",
            arrayOf(afterId.toString()),
            "${MediaStore.Audio.Media._ID} ASC",
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val durationIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val trackIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TRACK)
            val yearIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.YEAR)
            val modifiedIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_MODIFIED)
            val albumIdIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val artistIdIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST_ID)
            val pathIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val sizeIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
            for (column in optionalColumns) {
                optionalIndices[column] = cursor.getColumnIndex(column)
            }

            while (cursor.moveToNext() && rows.size < limit) {
                val audioId = cursor.getLong(idIdx)
                val row = HashMap<String, Any?>(16)
                row["id"] = audioId
                row["title"] = cursor.getString(titleIdx)?.trim()
                row["artist"] = normalize(cursor.getString(artistIdx))
                row["album"] = normalize(cursor.getString(albumIdx))
                row["durationMs"] = cursor.getLong(durationIdx)
                row["year"] = nullableInt(cursor, yearIdx)
                row["track"] = normalizeTrack(cursor.getInt(trackIdx))
                row["dateModifiedSec"] = cursor.getLong(modifiedIdx)
                row["albumId"] = cursor.getLong(albumIdIdx)
                row["artistId"] = cursor.getLong(artistIdIdx)
                row["path"] = cursor.getString(pathIdx)?.trim()
                row["sizeBytes"] = cursor.getLong(sizeIdx)
                optionalIndices["album_artist"]?.takeIf { it >= 0 }?.let {
                    row["albumArtist"] = normalize(cursor.getString(it))
                }
                optionalIndices[MediaStore.Audio.Media.DATE_ADDED]?.takeIf { it >= 0 }?.let {
                    row["dateAddedSec"] = nullableLong(cursor, it)
                }
                row["genre"] = genres()[audioId]
                row["contentUri"] = ContentUris.withAppendedId(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    audioId,
                ).toString()
                rows.add(row)
            }
        }
        return rows
    }

    private fun genres(): Map<Long, String> {
        genreByAudioId?.let { return it }
        val out = HashMap<Long, String>()
        try {
            resolver.query(
                MediaStore.Audio.Genres.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.Audio.Genres._ID, MediaStore.Audio.Genres.NAME),
                null,
                null,
                null,
            )?.use { genreCursor ->
                while (genreCursor.moveToNext()) {
                    val genreId = genreCursor.getLong(0)
                    val name = normalize(genreCursor.getString(1)) ?: continue
                    val membersUri = MediaStore.Audio.Genres.Members.getContentUri(
                        "external",
                        genreId,
                    )
                    resolver.query(
                        membersUri,
                        arrayOf(MediaStore.Audio.Genres.Members.AUDIO_ID),
                        null,
                        null,
                        null,
                    )?.use { memberCursor ->
                        while (memberCursor.moveToNext()) {
                            out.putIfAbsent(memberCursor.getLong(0), name)
                        }
                    }
                }
            }
        } catch (_: Exception) {
            return emptyMap()
        }
        genreByAudioId = out
        return out
    }

    /**
     * One artwork request: a cache key plus every handle we might resolve it
     * through. `audioId`/`path` let us fall back to per-song artwork, which is
     * the only option for tracks whose MediaStore `album_id` is 0.
     */
    private data class ArtworkTarget(
        val key: String,
        val albumId: Long?,
        val audioId: Long?,
        val path: String?,
    )

    private fun resolveArtwork(
        rawTargets: List<Map<String, Any?>>,
    ): Map<String, Map<String, String?>> {
        val artDir = File(appContext.filesDir, ART_DIR).apply { mkdirs() }
        val out = HashMap<String, Map<String, String?>>(rawTargets.size)
        for (raw in rawTargets.take(MAX_ART_BATCH)) {
            val key = raw["key"] as? String ?: continue
            val target = ArtworkTarget(
                key = key,
                albumId = (raw["albumId"] as? Number)?.toLong()?.takeIf { it > 0 },
                audioId = (raw["audioId"] as? Number)?.toLong()?.takeIf { it > 0 },
                path = (raw["path"] as? String)?.takeIf { it.isNotBlank() },
            )
            out[key] = resolveSingleArtwork(target, artDir)
        }
        return out
    }

    /**
     * Resolves one artwork target, trying every strategy the running platform
     * supports before giving up.
     *
     * The ordering matters. `content://media/external/audio/albumart/<id>` was
     * removed in Android 10 (API 29) — on any newer device it throws, which is
     * why artwork silently never appeared. [ContentResolver.loadThumbnail] is
     * the supported replacement, and querying it against the *song* URI also
     * covers tracks with no album (`album_id == 0`). Embedded artwork read via
     * [MediaMetadataRetriever] is the final fallback and works on every API
     * level, including for files MediaStore has no thumbnail for.
     */
    private fun resolveSingleArtwork(
        target: ArtworkTarget,
        artDir: File,
    ): Map<String, String?> {
        val safeKey = sanitizeKey(target.key)
        val smallFile = File(artDir, "$safeKey$SMALL_SUFFIX.webp")
        val largeFile = File(artDir, "$safeKey$LARGE_SUFFIX.webp")
        if (smallFile.isFile && smallFile.length() > 0 &&
            largeFile.isFile && largeFile.length() > 0
        ) {
            return mapOf(SMALL to smallFile.absolutePath, LARGE to largeFile.absolutePath)
        }

        val bitmap = loadArtworkBitmap(target) ?: return NO_ART
        return try {
            writeWebp(bitmap, largeFile, LARGE_PX)
            writeWebp(bitmap, smallFile, SMALL_PX)
            mapOf(SMALL to smallFile.absolutePath, LARGE to largeFile.absolutePath)
        } catch (_: Exception) {
            NO_ART
        } finally {
            bitmap.recycle()
        }
    }

    private fun loadArtworkBitmap(target: ArtworkTarget): Bitmap? {
        val thumbSize = Size(LARGE_PX, LARGE_PX)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Song thumbnail first: it exists for album-less tracks too.
            target.audioId?.let { audioId ->
                val uri = ContentUris.withAppendedId(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    audioId,
                )
                loadThumbnailOrNull(uri, thumbSize)?.let { return it }
            }
            target.albumId?.let { albumId ->
                val uri = ContentUris.withAppendedId(
                    MediaStore.Audio.Albums.EXTERNAL_CONTENT_URI,
                    albumId,
                )
                loadThumbnailOrNull(uri, thumbSize)?.let { return it }
            }
        } else {
            target.albumId?.let { albumId ->
                legacyAlbumArt(albumId)?.let { return it }
            }
        }

        return embeddedArtwork(target)
    }

    private fun loadThumbnailOrNull(uri: Uri, size: Size): Bitmap? {
        // The version check is repeated here rather than relied upon from the
        // caller so that lint can see it: `loadThumbnail` is API 29+, and a
        // guard in a different function does not satisfy the NewApi check.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return try {
            resolver.loadThumbnail(uri, size, null)
        } catch (_: Exception) {
            // Missing thumbnail, revoked permission, or an unsupported
            // provider: all mean "try the next strategy".
            null
        }
    }

    /** Pre-API-29 album art. Unavailable on Android 10 and newer. */
    private fun legacyAlbumArt(albumId: Long): Bitmap? {
        return try {
            val artUri = Uri.parse(LEGACY_ALBUM_ART_BASE).buildUpon()
                .appendPath(albumId.toString())
                .build()
            resolver.openFileDescriptor(artUri, "r")?.use { pfd ->
                decodeSampled { opts ->
                    BitmapFactory.decodeFileDescriptor(pfd.fileDescriptor, null, opts)
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    /** Artwork embedded in the media file itself. Works on every API level. */
    private fun embeddedArtwork(target: ArtworkTarget): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            val attached = when {
                target.audioId != null -> {
                    val uri = ContentUris.withAppendedId(
                        MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                        target.audioId,
                    )
                    retriever.setDataSource(appContext, uri)
                    true
                }
                target.path != null && File(target.path).isFile -> {
                    retriever.setDataSource(target.path)
                    true
                }
                else -> false
            }
            if (!attached) return null
            val picture = retriever.embeddedPicture ?: return null
            decodeSampled { opts ->
                BitmapFactory.decodeByteArray(picture, 0, picture.size, opts)
            }
        } catch (_: Exception) {
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
                // Releasing a retriever that never attached is not an error.
            }
        }
    }

    /**
     * Decodes via [decode] twice: once for bounds, once downsampled to at most
     * [LARGE_PX] on the long edge. Full-resolution album art is routinely
     * 3000px square, which would allocate ~36 MB per image.
     */
    private inline fun decodeSampled(
        decode: (BitmapFactory.Options) -> Bitmap?,
    ): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        decode(bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val opts = BitmapFactory.Options().apply {
            inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight, LARGE_PX)
        }
        return decode(opts)
    }

    /** Keeps cache filenames legal: album keys look like `ms:123`. */
    private fun sanitizeKey(key: String): String =
        key.map { if (it.isLetterOrDigit() || it == '-' || it == '_') it else '_' }
            .joinToString("")

    private fun writeWebp(source: Bitmap, target: File, maxEdge: Int) {
        val w = source.width
        val h = source.height
        val scaled = if (w > maxEdge || h > maxEdge) {
            val scale = maxEdge.toFloat() / maxOf(w, h)
            Bitmap.createScaledBitmap(
                source,
                (w * scale).toInt().coerceAtLeast(1),
                (h * scale).toInt().coerceAtLeast(1),
                true,
            )
        } else {
            source
        }
        val format = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Bitmap.CompressFormat.WEBP_LOSSY
        } else {
            @Suppress("DEPRECATION")
            Bitmap.CompressFormat.WEBP
        }
        FileOutputStream(target).use { out ->
            scaled.compress(format, WEBP_QUALITY, out)
        }
        if (scaled !== source) {
            scaled.recycle()
        }
    }

    private fun sampleSize(width: Int, height: Int, targetEdge: Int): Int {
        var sample = 1
        var edge = maxOf(width, height)
        while (edge / 2 >= targetEdge) {
            sample *= 2
            edge /= 2
        }
        return sample
    }

    private fun normalizeTrack(rawTrack: Int): Int? {
        if (rawTrack <= 0) return null
        return rawTrack % TRACK_MODULUS
    }

    private fun nullableInt(cursor: android.database.Cursor, idx: Int): Int? {
        if (idx < 0 || cursor.isNull(idx)) return null
        return cursor.getInt(idx)
    }

    private fun nullableLong(cursor: android.database.Cursor, idx: Int): Long? {
        if (idx < 0 || cursor.isNull(idx)) return null
        return cursor.getLong(idx)
    }

    private fun normalize(value: String?): String? {
        val trimmed = value?.trim() ?: return null
        if (trimmed.isEmpty()) return null
        return if (trimmed.lowercase() in lowercaseSet) null else trimmed
    }

    private val lowercaseSet = setOf("<unknown>", "unknown", "null", "undefined")

    private fun succeed(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }

    private fun fail(result: MethodChannel.Result, code: String, message: String?) {
        mainHandler.post { result.error(code, message, null) }
    }

    companion object {
        const val CHANNEL = "voratube/ingest_v1"
        const val MAX_BATCH = 1000
        const val MAX_ART_BATCH = 60
        const val SMALL_PX = 256
        const val LARGE_PX = 512
        const val SMALL_SUFFIX = "_s"
        const val LARGE_SUFFIX = "_l"
        const val SMALL = "small"
        const val LARGE = "large"
        const val ART_DIR = "art"

        /**
         * Removed in Android 10 (API 29). Kept only for the pre-Q fallback —
         * opening it on a newer device throws, which is exactly the bug that
         * made artwork silently never appear.
         */
        const val LEGACY_ALBUM_ART_BASE = "content://media/external/audio/albumart"
        const val WEBP_QUALITY = 85
        const val TRACK_MODULUS = 10000

        /** Sentinel for "no artwork could be resolved", sent back verbatim. */
        val NO_ART: Map<String, String?> = mapOf(SMALL to null, LARGE to null)
    }
}

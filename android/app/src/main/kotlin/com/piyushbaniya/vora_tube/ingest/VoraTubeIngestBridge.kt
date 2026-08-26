package com.piyushbaniya.vora_tube.ingest

import android.content.Context
import android.content.ContentUris
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
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
                            @Suppress("UNCHECKED_CAST")
                            val ids = call.argument<List<Number>>("albumIds")
                                ?: emptyList()
                            succeed(result, resolveArtwork(ids.map { it.toLong() }))
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

    private fun resolveArtwork(albumIds: List<Long>): Map<Long, Map<String, String?>> {
        val artDir = File(appContext.filesDir, ART_DIR).apply { mkdirs() }
        val out = HashMap<Long, Map<String, String?>>(albumIds.size)
        for (albumId in albumIds.take(MAX_ART_BATCH)) {
            out[albumId] = resolveSingleArtwork(albumId, artDir)
        }
        return out
    }

    private fun resolveSingleArtwork(
        albumId: Long,
        artDir: File,
    ): Map<String, String?> {
        val smallFile = File(artDir, "$albumId${SMALL_SUFFIX}.webp")
        val largeFile = File(artDir, "$albumId${LARGE_SUFFIX}.webp")
        if (smallFile.isFile && largeFile.isFile) {
            return mapOf(SMALL to smallFile.absolutePath, LARGE to largeFile.absolutePath)
        }
        try {
            val artUri = Uri.parse(ALBUM_ART_BASE).buildUpon()
                .appendPath(albumId.toString())
                .build()
            resolver.openFileDescriptor(artUri, "r")?.use { pfd ->
                val bounds = BitmapFactory.Options().apply {
                    inJustDecodeBounds = true
                }
                BitmapFactory.decodeFileDescriptor(pfd.fileDescriptor, null, bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
                    return mapOf(SMALL to null, LARGE to null)
                }
                val sampleForLarge = sampleSize(bounds.outWidth, bounds.outHeight, LARGE_PX)
                val opts = BitmapFactory.Options().apply {
                    inSampleSize = sampleForLarge
                }
                val largeBitmap = BitmapFactory.decodeFileDescriptor(
                    pfd.fileDescriptor,
                    null,
                    opts,
                ) ?: return mapOf(SMALL to null, LARGE to null)

                writeWebp(largeBitmap, largeFile, LARGE_PX)
                writeWebp(largeBitmap, smallFile, SMALL_PX)
                largeBitmap.recycle()
                return mapOf(
                    SMALL to smallFile.absolutePath,
                    LARGE to largeFile.absolutePath,
                )
            } ?: return mapOf(SMALL to null, LARGE to null)
        } catch (_: Exception) {
            return mapOf(SMALL to null, LARGE to null)
        }
    }

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
        FileOutputStream(target).use { out ->
            scaled.compress(Bitmap.CompressFormat.WEBP, WEBP_QUALITY, out)
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
        const val ALBUM_ART_BASE = "content://media/external/audio/albumart"
        const val WEBP_QUALITY = 85
        const val TRACK_MODULUS = 10000
    }
}

package com.piyushbaniya.vora_tube.audio

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer

/**
 * Native audio utility bridge: trimming a segment from a local track into a
 * ringtone file and handing the result to the system ringtone flow.
 *
 * Keeping this on the Android side avoids shipping a heavy transcoding
 * dependency (the project deliberately favors small, stable dependencies). It
 * uses the platform's own [MediaCodec]/[MediaMuxer] pipeline so it honors the
 * project's "use platform capabilities" rule and stays Play-Store compliant:
 * the ringtone file is written into app-owned storage and registered
 * with [MediaStore] (API 29+), then the default assignment is applied directly
 * through [RingtoneManager] so the user never leaves the app.
 *
 * The heavy cut runs on a daemon worker thread, never on the UI thread.
 */
class VoraTubeAudioUtilBridge(context: Context) {

    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger) {
        val channel = MethodChannel(messenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "cutAudio" -> {
                    val source = call.argument<String>("sourceUri")
                    val startMs = (call.argument<Number>("startMs") ?: 0L).toLong()
                    val endMs = (call.argument<Number>("endMs") ?: 0L).toLong()
                    val songTitle = call.argument<String>("songTitle") ?: "Ringtone"
                    val worker = Thread {
                        try {
                            succeed(result, cutAudio(source, startMs, endMs, songTitle))
                        } catch (e: CutFailed) {
                            android.util.Log.e("VoraTubeAudio", "cut failed: ${e.code} / ${e.message}")
                            fail(result, e.code, e.message)
                        } catch (e: Exception) {
                            android.util.Log.e("VoraTubeAudio", "cut audio exception", e)
                            fail(result, "cut_failed", e.message ?: "could not trim audio")
                        }
                    }
                    worker.isDaemon = true
                    worker.start()
                }
                "setDefaultRingtone" -> {
                    val contentUri = call.argument<String>("contentUri")
                    val worker = Thread {
                        try {
                            succeed(result, setDefaultRingtone(contentUri))
                        } catch (e: CutFailed) {
                            android.util.Log.e("VoraTubeAudio", "set ringtone failed: ${e.code} / ${e.message}")
                            fail(result, e.code, e.message)
                        } catch (e: Exception) {
                            android.util.Log.e("VoraTubeAudio", "set ringtone exception", e)
                            fail(result, "set_failed", e.message ?: "could not set ringtone")
                        }
                    }
                    worker.isDaemon = true
                    worker.start()
                }
                "supportsCutting" -> succeed(result, true)
                else -> fail(result, "unsupported_method", call.method)
            }
        }
    }

    /**
     * Sets [contentUri] as the device's default ringtone without leaving the app.
     *
     * The system picker is deliberately not used: assignment is performed
     * directly through [RingtoneManager.setActualDefaultRingtoneUri], which
     * requires the caller to hold the WRITE_SETTINGS special permission.
     */
    @Throws(CutFailed::class)
    private fun setDefaultRingtone(contentUri: String?): Map<String, Any?> {
        if (contentUri.isNullOrBlank()) {
            throw CutFailed("missing_content_uri", "no exported ringtone uri")
        }
        if (!Settings.System.canWrite(appContext)) {
            throw CutFailed(
                "write_settings_denied",
                "ringtone assignment needs the modify-system-settings permission",
            )
        }
        val uri = Uri.parse(contentUri)
        try {
            RingtoneManager.setActualDefaultRingtoneUri(
                appContext,
                RingtoneManager.TYPE_RINGTONE,
                uri,
            )
        } catch (e: Exception) {
            android.util.Log.e("VoraTubeAudio", "setActualDefaultRingtoneUri failed", e)
            throw CutFailed("set_failed", e.message ?: "could not set ringtone")
        }
        android.util.Log.d("VoraTubeAudio", "Default ringtone set to $uri")
        return mapOf("assigned" to true)
    }

    private class CutFailed(val code: String, msg: String?) : Exception(msg)

    private fun cutAudio(
        sourceUri: String?,
        startMs: Long,
        endMs: Long,
        songTitle: String,
    ): Map<String, Any?> {
        if (sourceUri.isNullOrBlank()) {
            throw CutFailed("missing_source", "source audio is unavailable")
        }
        if (startMs < 0 || endMs <= startMs) {
            throw CutFailed("invalid_range", "invalid trim range $startMs..$endMs")
        }
        val uri = Uri.parse(sourceUri)
        val sourceDuration = queryDurationMs(uri)
        if (sourceDuration != null && sourceDuration > 0 && endMs > sourceDuration) {
            throw CutFailed("invalid_range", "end ($endMs) exceeds track duration ($sourceDuration)")
        }

        val outFile = createOutputFile(songTitle)
        trimToFile(uri, startMs, endMs, outFile)
        val contentUri = registerWithMediaStore(outFile, songTitle)
        val finalDurationMs = queryDurationMs(contentUri ?: Uri.fromFile(outFile))
            ?: (endMs - startMs)
        return mapOf(
            "path" to outFile.absolutePath,
            "contentUri" to (contentUri?.toString() ?: ""),
            "durationMs" to finalDurationMs,
        )
    }

    private fun queryDurationMs(uri: Uri): Long? {
        val retriever = android.media.MediaMetadataRetriever()
        return try {
            retriever.setDataSource(appContext, uri)
            retriever.extractMetadata(
                android.media.MediaMetadataRetriever.METADATA_KEY_DURATION
            )?.toLongOrNull()
        } catch (_: Exception) {
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }

    /**
     * Re-encodes the [startMs, endMs] window into [outFile] as an AAC M4A.
     *
     * A full decode→re-encode is deliberately used rather than raw sample
     * splicing: MP3 and other non-muxable sources cannot be byte-spliced frame-
     * accurately, and the resulting file is guaranteed to be a valid, seekable
     * ringtone on every format just_audio can play. Source timestamps are
     * rebased to zero so the output starts precisely at the selected sample.
     */
    private fun trimToFile(uri: Uri, startMs: Long, endMs: Long, outFile: File) {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        var decoder: MediaCodec? = null
        var encoder: MediaCodec? = null
        var muxerStarted = false
        try {
            extractor.setDataSource(appContext, uri, null)
            var audioTrackIndex = -1
            var sourceFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val fmt = extractor.getTrackFormat(i)
                if (fmt.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                    audioTrackIndex = i
                    sourceFormat = fmt
                    break
                }
            }
            if (audioTrackIndex < 0 || sourceFormat == null) {
                throw CutFailed("no_audio_track", "no audible audio track found")
            }
            val mime = sourceFormat.getString(MediaFormat.KEY_MIME)!!
            extractor.selectTrack(audioTrackIndex)

            val sampleRate = sourceFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channelCount = sourceFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

            decoder = MediaCodec.createDecoderByType(mime)
            decoder.configure(sourceFormat, null, null, 0)

            encoder = MediaCodec.createEncoderByType(M4A_MIME)
            val encFormat = MediaFormat.createAudioFormat(M4A_MIME, sampleRate, channelCount)
            encFormat.setInteger(
                MediaFormat.KEY_BIT_RATE,
                (sampleRate * channelCount * 2).coerceIn(64000, 192000),
            )
            encFormat.setInteger(
                MediaFormat.KEY_AAC_PROFILE,
                MediaCodecInfo.CodecProfileLevel.AACObjectLC,
            )
            encoder.configure(encFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)

            muxer = MediaMuxer(outFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            val startUs = startMs * 1000L
            val endUs = endMs * 1000L

            android.util.Log.d("VoraTubeAudio", "Starting trim: startUs=$startUs, endUs=$endUs, sampleRate=$sampleRate, channels=$channelCount, mime=$mime")
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            android.util.Log.d("VoraTubeAudio", "Sought extractor: current sampleTime=${extractor.sampleTime}, track=${extractor.sampleTrackIndex}")

            decoder.start()
            encoder.start()

            var muxerTrack = -1
            var decoderInputDone = false
            var passedWindowEnd = false
            var encoderEosQueued = false
            var allMuxed = false
            var totalPcmBytesQueued = 0L
            var totalMuxerSamples = 0L
            val encInfo = MediaCodec.BufferInfo()

            fun drainEncoder() {
                var encIdle = false
                while (!encIdle) {
                    val encIdx = encoder.dequeueOutputBuffer(encInfo, 2000L)
                    when {
                        encIdx == MediaCodec.INFO_TRY_AGAIN_LATER -> encIdle = true
                        encIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            if (!muxerStarted) {
                                val newFmt = encoder.outputFormat
                                android.util.Log.d("VoraTubeAudio", "Encoder format changed: $newFmt")
                                muxerTrack = muxer.addTrack(newFmt)
                                muxer.start()
                                muxerStarted = true
                            }
                        }
                        encIdx >= 0 -> {
                            val isConfig = (encInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
                            val isEos = (encInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                            if (encInfo.size > 0 && muxerStarted && !isConfig) {
                                val encOut = encoder.getOutputBuffer(encIdx)
                                if (encOut != null) {
                                    encOut.position(encInfo.offset)
                                    encOut.limit(encInfo.offset + encInfo.size)
                                    muxer.writeSampleData(muxerTrack, encOut, encInfo)
                                    totalMuxerSamples++
                                }
                            }
                            encoder.releaseOutputBuffer(encIdx, false)
                            if (isEos) {
                                android.util.Log.d("VoraTubeAudio", "Encoder EOS reached! Total muxed samples: $totalMuxerSamples")
                                allMuxed = true
                                encIdle = true
                            }
                        }
                        else -> encIdle = true
                    }
                }
            }

            var loopCount = 0
            while (!allMuxed) {
                loopCount++
                // 1) Feed the decoder until EOS or end of window.
                if (!decoderInputDone && !passedWindowEnd) {
                    val inIdx = decoder.dequeueInputBuffer(3000L)
                    if (inIdx >= 0) {
                        val inBuf = decoder.getInputBuffer(inIdx)
                        inBuf?.clear()
                        val sampleSize = if (inBuf != null) extractor.readSampleData(inBuf, 0) else -1
                        val curTrack = extractor.sampleTrackIndex
                        val sourcePtsUs = extractor.sampleTime
                        if (sampleSize > 0 && inBuf != null && curTrack == audioTrackIndex) {
                            decoder.queueInputBuffer(
                                inIdx,
                                0,
                                sampleSize,
                                sourcePtsUs,
                                0,
                            )
                            extractor.advance()
                        } else {
                            android.util.Log.d("VoraTubeAudio", "Extractor finished or invalid track (sampleSize=$sampleSize, track=$curTrack). Queueing decoder EOS.")
                            decoder.queueInputBuffer(
                                inIdx,
                                0,
                                0,
                                0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            decoderInputDone = true
                        }
                    }
                }

                // 2) Drain decoded PCM into the encoder.
                var decIdle = false
                while (!decIdle && !passedWindowEnd) {
                    val decInfo = MediaCodec.BufferInfo()
                    val outIdx = decoder.dequeueOutputBuffer(decInfo, 2000L)
                    when {
                        outIdx == MediaCodec.INFO_TRY_AGAIN_LATER -> decIdle = true
                        outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            android.util.Log.d("VoraTubeAudio", "Decoder output format: ${decoder.outputFormat}")
                        }
                        outIdx >= 0 -> {
                            val pcm = decoder.getOutputBuffer(outIdx)
                            val srcPts = decInfo.presentationTimeUs
                            val isEos = (decInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                            val isConfig = (decInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0

                            if (srcPts >= endUs || isEos) {
                                android.util.Log.d("VoraTubeAudio", "Passed window end: srcPts=$srcPts (endUs=$endUs), isEos=$isEos")
                                passedWindowEnd = true
                            }

                            if (pcm != null && !isConfig && decInfo.size > 0 && srcPts in startUs until endUs) {
                                val encPtsBase = (srcPts - startUs).coerceAtLeast(0L)
                                val bytesPerUs =
                                    if (sampleRate > 0) (sampleRate * channelCount * 2L).toDouble() / 1_000_000.0
                                    else 0.0
                                var written = 0
                                while (written < decInfo.size) {
                                    var encIn = encoder.dequeueInputBuffer(3000L)
                                    var attempts = 0
                                    while (encIn < 0 && attempts < 100) {
                                        drainEncoder()
                                        encIn = encoder.dequeueInputBuffer(3000L)
                                        attempts++
                                    }
                                    if (encIn < 0) {
                                        throw IllegalStateException("Audio encoder stalled during trim")
                                    }
                                    val encBuf = encoder.getInputBuffer(encIn)
                                    if (encBuf == null) {
                                        encoder.queueInputBuffer(encIn, 0, 0, encPtsBase, 0)
                                        continue
                                    }
                                    encBuf.clear()
                                    val room = encBuf.remaining()
                                    val take = minOf(room, decInfo.size - written)
                                    if (take <= 0) {
                                        throw IllegalStateException("Audio encoder input buffer too small")
                                    }
                                    pcm.position(decInfo.offset + written)
                                    pcm.limit(decInfo.offset + written + take)
                                    encBuf.put(pcm)
                                    val encPts =
                                        if (bytesPerUs <= 0) encPtsBase
                                        else encPtsBase + (written / bytesPerUs).toLong()
                                    encoder.queueInputBuffer(encIn, 0, take, encPts, 0)
                                    written += take
                                    totalPcmBytesQueued += take
                                }
                            }
                            decoder.releaseOutputBuffer(outIdx, false)
                        }
                        else -> decIdle = true
                    }
                }

                // 3) Signal encoder EOS once selection is fully decoded.
                if (passedWindowEnd && !encoderEosQueued) {
                    android.util.Log.d("VoraTubeAudio", "Signalling encoder EOS after $totalPcmBytesQueued PCM bytes")
                    var eosQueued = false
                    var attempts = 0
                    while (!eosQueued && attempts < 100) {
                        val encIn = encoder.dequeueInputBuffer(3000L)
                        if (encIn >= 0) {
                            encoder.queueInputBuffer(
                                encIn,
                                0,
                                0,
                                (endUs - startUs).coerceAtLeast(0L),
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            eosQueued = true
                            encoderEosQueued = true
                        } else {
                            drainEncoder()
                            attempts++
                        }
                    }
                }

                // 4) Drain encoded data into the muxer.
                drainEncoder()
            }
            android.util.Log.d("VoraTubeAudio", "Trim complete: totalPcmBytes=$totalPcmBytesQueued, totalMuxerSamples=$totalMuxerSamples, outFileSize=${outFile.length()}")
        } finally {
            try {
                extractor.release()
            } catch (_: Exception) {
            }
            closeQuietly(decoder)
            closeQuietly(encoder)
            try {
                muxer?.stop()
            } catch (_: Exception) {
            }
            try {
                muxer?.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun closeQuietly(codec: MediaCodec?) {
        if (codec == null) return
        try {
            codec.stop()
        } catch (_: Exception) {
        }
        try {
            codec.release()
        } catch (_: Exception) {
        }
    }

    private fun createOutputFile(songTitle: String): File {
        val base = appContext.getExternalFilesDir(null) ?: appContext.filesDir
        val dir = File(base, "ringtones").apply { mkdirs() }
        val clean = sanitizeFileName(songTitle)
        var candidate = File(dir, "$clean - Ringtone.m4a")
        var n = 2
        while (candidate.exists()) {
            candidate = File(dir, "$clean - Ringtone $n.m4a")
            n++
        }
        return candidate
    }

    private fun registerWithMediaStore(file: File, songTitle: String): Uri? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return try {
            val values = ContentValues().apply {
                put(MediaStore.Audio.Media.DISPLAY_NAME, file.name)
                put(MediaStore.Audio.Media.MIME_TYPE, "audio/mp4")
                put(MediaStore.Audio.Media.RELATIVE_PATH, "Ringtones/VoraTube")
                put(MediaStore.Audio.Media.IS_RINGTONE, 1)
                put(MediaStore.Audio.Media.IS_PENDING, 1)
                put(MediaStore.Audio.Media.TITLE, songTitle)
            }
            val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val uri = appContext.contentResolver.insert(collection, values)
            if (uri == null) return null
            android.util.Log.d("VoraTubeAudio", "Inserted pending row: $uri")
            appContext.contentResolver.openOutputStream(uri)?.use { out ->
                file.inputStream().use { it.copyTo(out) }
            }
            // Publishing the item makes the provider re-scan the file and
            // re-derive its flags, which can reset is_ringtone (and, on some
            // builds, replace the pending row with a new _id). Resolve the live
            // row by display name and re-assert the ringtone flag afterwards so
            // the system picker actually lists the tone.
            val publish = ContentValues().apply {
                put(MediaStore.Audio.Media.IS_PENDING, 0)
            }
            val publishCount = appContext.contentResolver.update(uri, publish, null, null)
            android.util.Log.d("VoraTubeAudio", "Published pending row, updated=$publishCount")

            fun findCurrentRow(): Uri? {
                var found: Uri? = null
                appContext.contentResolver.query(
                    collection,
                    arrayOf(MediaStore.Audio.Media._ID),
                    "${MediaStore.Audio.Media.DISPLAY_NAME}=?",
                    arrayOf(file.name),
                    null,
                )?.use { c ->
                    if (c.moveToFirst()) {
                        val id = c.getLong(0)
                        found = ContentUris.withAppendedId(collection, id)
                        android.util.Log.d(
                            "VoraTubeAudio",
                            "Live ringtone row: id=$id (inserted=${uri.lastPathSegment})",
                        )
                    }
                }
                return found
            }

            fun assertRingtone(row: Uri?, label: String) {
                if (row == null) {
                    android.util.Log.w("VoraTubeAudio", "$label: no live row to update")
                    return
                }
                try {
                    val flag = ContentValues().apply {
                        put(MediaStore.Audio.Media.IS_RINGTONE, 1)
                    }
                    val n = appContext.contentResolver.update(row, flag, null, null)
                    android.util.Log.d("VoraTubeAudio", "$label: update($row)=$n")
                } catch (e: Exception) {
                    android.util.Log.e("VoraTubeAudio", "$label update failed", e)
                }
            }

            val live = findCurrentRow()
            assertRingtone(live, "Immediate re-assert")
            mainHandler.postDelayed(
                {
                    val now = findCurrentRow()
                    assertRingtone(now, "Delayed re-assert")
                },
                1800L,
            )
            // Keep the caller waiting until the re-asserted flag has settled, so
            // the system picker never opens before the tone is listed.
            Thread.sleep(1900L)
            live ?: uri
        } catch (e: Exception) {
            android.util.Log.e("VoraTubeAudio", "registerWithMediaStore failed", e)
            null
        }
    }

    private fun sanitizeFileName(name: String): String {
        val cleaned = name
            .map { if (it.isLetterOrDigit() || it == '-' || it == '_' || it == ' ') it else '_' }
            .joinToString("")
            .replace(Regex("\\s+"), " ")
            .trim()
        return if (cleaned.isBlank()) "Ringtone" else cleaned.take(80)
    }

    private fun succeed(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }

    private fun fail(result: MethodChannel.Result, code: String, message: String?) {
        mainHandler.post {
            result.error(code, message ?: "", null)
        }
    }

    companion object {
        const val CHANNEL = "voratube/audio_util_v1"
        const val M4A_MIME = "audio/mp4a-latm"
    }
}

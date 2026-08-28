package com.piyushbaniya.vora_tube.audio

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.Intent
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
 * the ringtone file is written into app-owned external storage and registered
 * with [MediaStore] (API 29+) so it appears in the system picker, and the
 * default assignment is always completed by the user inside the system UI.
 *
 * The heavy cut runs on a daemon worker thread, never on the UI thread.
 */
class VoraTubeAudioUtilBridge(context: Context) {

    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var pendingActivity: Activity? = null

    @Volatile
    private var pendingPickerResult: MethodChannel.Result? = null

    @Volatile
    private var existingRingtone: Uri? = null

    /** Configures the [Activity] used to launch system intents (from MainActivity). */
    fun setActivity(activity: Activity?) {
        pendingActivity = activity
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
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
                            fail(result, e.code, e.message)
                        } catch (e: Exception) {
                            fail(result, "cut_failed", e.message ?: "could not trim audio")
                        }
                    }
                    worker.isDaemon = true
                    worker.start()
                }
                "openRingtonePicker" -> {
                    existingRingtone = call.argument<String>("contentUri")?.takeIf { it.isNotBlank() }
                        ?.let { Uri.parse(it) }
                    openRingtonePicker(result)
                }
                "supportsCutting" -> succeed(result, true)
                else -> fail(result, "unsupported_method", call.method)
            }
        }
    }

    /** Routes the system picker result back to the waiting Dart Future. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != RINGTONE_PICKER_REQUEST) return
        val pending = pendingPickerResult
        pendingPickerResult = null
        if (pending == null) return
        val chosen = data?.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        if (resultCode == Activity.RESULT_OK) {
            succeed(pending, mapOf("assigned" to true, "pickedUri" to (chosen?.toString() ?: "")))
        } else {
            succeed(pending, mapOf("assigned" to false, "pickedUri" to null))
        }
    }

    private fun openRingtonePicker(result: MethodChannel.Result) {
        val activity = pendingActivity
        if (activity == null) {
            fail(result, "no_activity", "ringtone picker requires an activity")
            return
        }
        if (pendingPickerResult != null) {
            fail(result, "picker_busy", "a ringtone picker is already open")
            return
        }
        val existing = existingRingtone
        existingRingtone = null
        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_RINGTONE)
            putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Set ringtone")
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, false)
            if (existing != null) {
                putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, existing)
            }
        }
        pendingPickerResult = result
        try {
            activity.startActivityForResult(intent, RINGTONE_PICKER_REQUEST)
        } catch (e: Exception) {
            pendingPickerResult = null
            fail(result, "picker_unavailable", e.message ?: "no ringtone picker is available")
        }
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
                (sampleRate * channelCount).coerceIn(64000, 196000),
            )
            encFormat.setInteger(
                MediaFormat.KEY_AAC_PROFILE,
                MediaCodecInfo.CodecProfileLevel.AACObjectLC,
            )
            encoder.configure(encFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)

            muxer = MediaMuxer(outFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            val startUs = startMs * 1000L
            val endUs = endMs * 1000L

            decoder.start()
            encoder.start()

            var muxerTrack = -1
            var muxerStarted = false
            var decoderInputDone = false
            var passedWindowEnd = false
            var encoderEosQueued = false
            var allMuxed = false
            val encInfo = MediaCodec.BufferInfo()

            while (!allMuxed) {
                // 1) Feed the decoder until EOS.
                if (!decoderInputDone) {
                    val inIdx = decoder.dequeueInputBuffer(3000L)
                    if (inIdx >= 0) {
                        val inBuf = decoder.getInputBuffer(inIdx)
                        val sampleSize = extractor.sampleSize.toInt()
                        if (sampleSize > 0 && inBuf != null) {
                            extractor.readSampleData(inBuf, 0)
                            val sourcePtsUs = extractor.sampleTime.toLong()
                            decoder.queueInputBuffer(
                                inIdx,
                                0,
                                sampleSize,
                                sourcePtsUs,
                                0,
                            )
                            extractor.advance()
                        } else {
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

                // 2) Drain decoded PCM into the encoder, dropping samples outside
                //    [startUs, endUs] and rebasing retained ones to zero.
                var decIdle = false
                while (!decIdle) {
                    val decInfo = MediaCodec.BufferInfo()
                    val outIdx = decoder.dequeueOutputBuffer(decInfo, 0L)
                    when {
                        outIdx == MediaCodec.INFO_TRY_AGAIN_LATER -> decIdle = true
                        outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {}
                        outIdx >= 0 -> {
                            val pcm = decoder.getOutputBuffer(outIdx)
                            val srcPts = decInfo.presentationTimeUs
                            val isEos = decInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                            val config = decInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                            if (pcm != null && !config && decInfo.size > 0 &&
                                srcPts in startUs until endUs
                            ) {
                                val encIn = encoder.dequeueInputBuffer(3000L)
                                if (encIn >= 0) {
                                    val encBuf = encoder.getInputBuffer(encIn)
                                    encBuf?.clear()
                                    pcm.position(decInfo.offset)
                                    encBuf?.put(pcm)
                                    encoder.queueInputBuffer(
                                        encIn,
                                        0,
                                        decInfo.size,
                                        (srcPts - startUs).coerceAtLeast(0L),
                                        decInfo.flags,
                                    )
                                }
                            } else if (srcPts >= endUs) {
                                // Decoder has produced a buffer past our window:
                                // the whole selection has now been decoded.
                                passedWindowEnd = true
                            }
                            decoder.releaseOutputBuffer(outIdx, false)
                            if (isEos) {
                                passedWindowEnd = true
                                decIdle = true
                            }
                        }
                        else -> decIdle = true
                    }
                }

                // 3) Signal encoder EOS only once the selection has been fully
                //    decoded (i.e. the decoder passed the window end). Queuing it
                //    any earlier would truncate the clip to whatever had already
                //    been fed, cutting off the tail of the selection.
                if (passedWindowEnd && !encoderEosQueued) {
                    val encIn = encoder.dequeueInputBuffer(3000L)
                    if (encIn >= 0) {
                        encoder.queueInputBuffer(
                            encIn,
                            0,
                            0,
                            0,
                            MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                        )
                        encoderEosQueued = true
                    }
                }

                // 4) Drain encoded data into the muxer.
                var encIdle = false
                while (!encIdle) {
                    val encIdx = encoder.dequeueOutputBuffer(encInfo, 0L)
                    when {
                        encIdx == MediaCodec.INFO_TRY_AGAIN_LATER -> encIdle = true
                        encIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            if (!muxerStarted) {
                                muxerTrack = muxer.addTrack(encoder.outputFormat)
                                muxer.start()
                                muxerStarted = true
                            }
                        }
                        encIdx >= 0 -> {
                            if (encInfo.size > 0 && muxerStarted) {
                                val encOut = encoder.getOutputBuffer(encIdx)
                                encOut?.position(encInfo.offset)
                                encOut?.limit(encInfo.offset + encInfo.size)
                                muxer.writeSampleData(muxerTrack, encOut!!, encInfo)
                            }
                            encoder.releaseOutputBuffer(encIdx, false)
                            if (encInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                                allMuxed = true
                                encIdle = true
                            }
                        }
                        else -> encIdle = true
                    }
                }
            }
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
                put(MediaStore.Audio.Media.RELATIVE_PATH, "Music/VoraTube")
                put(MediaStore.Audio.Media.IS_RINGTONE, 1)
                put(MediaStore.Audio.Media.IS_PENDING, 1)
                put(MediaStore.Audio.Media.TITLE, songTitle)
            }
            val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val uri = appContext.contentResolver.insert(collection, values)
            if (uri == null) return null
            appContext.contentResolver.openOutputStream(uri)?.use { out ->
                file.inputStream().use { it.copyTo(out) }
            }
            val done = ContentValues().apply { put(MediaStore.Audio.Media.IS_PENDING, 0) }
            appContext.contentResolver.update(uri, done, null, null)
            uri
        } catch (_: Exception) {
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
        const val RINGTONE_PICKER_REQUEST = 41731
        const val M4A_MIME = "audio/mp4a-latm"
    }
}

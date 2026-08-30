package com.piyushbaniya.vora_tube.audio

import android.annotation.SuppressLint
import android.content.Context
import android.media.audiofx.LoudnessEnhancer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Real audio gain for the Volume Booster.
 *
 * ExoPlayer (which backs just_audio) clamps its volume to 0..1, so a Flutter
 * multiplier above 1.0 can never raise the output — the previous implementation
 * multiplied a value that was then clamped to exactly the same 1.0, which is why
 * the booster changed the UI but not the audio.
 *
 * This bridge attaches an [android.media.audiofx.LoudnessEnhancer] to the audio
 * session that ExoPlayer/just_audio owns and raises true millibel gain up to
 * that session's native ceiling. The enhancer lives on the session, so it
 * persists across track transitions and pause/resume and only needs a
 * re-attach if the session id itself changes.
 *
 * All calls are best-effort: an AudioEffect failure (unusual session, driver
 * resource exhaustion) leaves playback at normal volume rather than crashing.
 */
class VoraTubeVolumeBoosterBridge(context: Context) {

    private var enhancer: LoudnessEnhancer? = null
    private var currentSessionId = -1

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "attach" -> {
                    attachEnhancer(call.argument<Int>("sessionId") ?: -1)
                    result.success(true)
                }
                "setGain" -> {
                    setGain(call.argument<Int>("millibel") ?: 0)
                    result.success(true)
                }
                "release" -> {
                    releaseEnhancer()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    @SuppressLint("NewApi")
    private fun attachEnhancer(sessionId: Int) {
        if (sessionId < 0) {
            releaseEnhancer()
            return
        }
        if (sessionId == currentSessionId && enhancer != null) {
            return
        }
        releaseEnhancer()
        try {
            val next = LoudnessEnhancer(sessionId)
            next.enabled = true
            enhancer = next
            currentSessionId = sessionId
        } catch (_: Exception) {
            // LoudnessEnhancer can fail if the session is invalid or the
            // audio effect chain rejects it; degrade to normal volume.
            enhancer = null
            currentSessionId = -1
        }
    }

    private fun setGain(millibel: Int) {
        val e = enhancer ?: return
        try {
            // LoudnessEnhancer exposes 0..1000 mB (0..+10 dB). Clamp on the
            // safe side; anything at/under 0 is "no boost".
            e.setTargetGain(millibel.coerceIn(0, 1000))
            e.enabled = true
        } catch (_: Exception) {
            // Best-effort: ignore and leave volume untouched.
        }
    }

    private fun releaseEnhancer() {
        try {
            enhancer?.setEnabled(false)
            enhancer?.release()
        } catch (_: Exception) {
            // Ignore disposal errors; the object is being dropped regardless.
        }
        enhancer = null
        currentSessionId = -1
    }

    companion object {
        const val CHANNEL = "voratube/volume_booster_v1"
    }
}
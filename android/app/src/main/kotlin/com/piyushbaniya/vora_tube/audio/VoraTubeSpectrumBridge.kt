package com.piyushbaniya.vora_tube.audio

import android.annotation.SuppressLint
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import java.nio.ByteBuffer

/**
 * Streams live 48-band spectrum frames from the post-EQ PCM tap to Flutter
 * through a single EventChannel.
 *
 * Lifecycle is consumer-driven: the worker thread and the FFT run only while
 * Flutter is listening (`voratube/spectrum`) — leaving the Equalizer screen or
 * disabling the analyzer stops all analysis work, background playback keeps
 * running untouched. Frames are capped at ~30/s; a single worker always
 * analyses the newest window, no unbounded queue builds up.
 */
@SuppressLint("UnsafeOptInUsageError")
class VoraTubeSpectrumBridge(
  messenger: BinaryMessenger,
  private val analyzer: SpectrumAnalyzer,
) {

  private val eventChannel = EventChannel(messenger, "voratube/spectrum")
  private var sink: EventChannel.EventSink? = null

  @Volatile
  private var worker: HandlerThread? = null

  /** Identity guard: a stale tick must never feed a newer/closed worker. */
  @Volatile
  private var handler: Handler? = null

  /** Platform events must be delivered on the main thread; owned by this bridge. */
  private val mainHandler = Handler(Looper.getMainLooper())

  /** Invoked from the audio path after every processed buffer. */
  fun onPcm(buffer: ByteBuffer, channels: Int, isFloat: Boolean) {
    try {
      analyzer.feedFrame(buffer, channels, isFloat)
    } catch (_: Throwable) {
      // Spectrum is strictly observational: never let it disturb playback.
    }
  }

  /** Clears stale windows on seek / track change. */
  fun onReset() {
    try {
      analyzer.flush()
    } catch (_: Throwable) {}
  }

  /** Re-aligns the log band grid when the playback sample rate changes. */
  fun setSampleRate(rate: Int) {
    try {
      analyzer.updateSampleRate(rate)
    } catch (_: Throwable) {}
  }

  fun register() {
    eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        analyzer.start()
        startWorker()
      }

      override fun onCancel(arguments: Any?) {
        stopWorker()
        sink = null
        analyzer.stop()
      }
    })
  }

  fun dispose() {
    stopWorker()
    sink = null
    analyzer.stop()
    eventChannel.setStreamHandler(null)
  }

  private fun startWorker() {
    if (worker?.isAlive == true) return
    val thread = HandlerThread("VoraTubeSpectrum").apply { start() }
    val owner = Handler(thread.looper)
    worker = thread
    handler = owner
    owner.post(object : Runnable {
      override fun run() {
        // A newer worker (or a shutdown) owns the analyzer now: stop ticking.
        if (handler !== owner) return
        val frame = try {
          analyzer.pullFrame()
        } catch (_: Throwable) {
          null
        }
        if (frame != null) {
          val payload = mapOf(
            "values" to List(frame.size) { frame[it].toDouble() },
            "sampleRate" to analyzer.sampleRate,
            "timestamp" to SystemClock.uptimeMillis(),
          )
          mainHandler.post { if (handler === owner) sink?.success(payload) }
        }
        owner.postDelayed(this, SpectrumAnalyzer.FRAME_INTERVAL_MS)
      }
    })
  }

  private fun stopWorker() {
    handler = null
    worker?.quitSafely()
    worker = null
    mainHandler.removeCallbacksAndMessages(null)
  }
}

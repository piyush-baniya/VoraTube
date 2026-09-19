package com.piyushbaniya.vora_tube.audio

import android.annotation.SuppressLint
import androidx.media3.common.audio.AudioProcessor
import com.ryanheise.just_audio.AudioProcessorBridge
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Owns the single parametric equalizer processor, registers it into the
 * just_audio audio chain and exposes it to Dart through the
 * `voratube/parametric_eq_v1` method channel.
 *
 * Registration must happen before the first ExoPlayer is built (i.e. before
 * any track is loaded), so this is wired in `MainActivity.configureFlutterEngine`,
 * which runs before Dart `main`.
 */
class VoraTubeParametricEqBridge(private val messenger: BinaryMessenger) {

  val processor = VoraTubeParametricEqProcessor()

  private val spectrumBridge = VoraTubeSpectrumBridge(messenger, SpectrumAnalyzer())

  private val channel = MethodChannel(messenger, "voratube/parametric_eq_v1")
  private val rateChannel = MethodChannel(messenger, "voratube/parametric_eq_v1/sampleRate")

  /** Hot path is always wired; the channel only carries rare config events. */
  fun register() {
    AudioProcessorBridge.setProcessors(arrayOf<AudioProcessor>(processor))

    channel.setMethodCallHandler { call, result ->
      when (call.method) {
        "configure" -> {
          val cfg = processor.config ?: ParametricEqConfig()
          val rawGen = call.argument<Int>("gen")
          val rawEnabled = call.argument<Boolean>("enabled")
          val rawRate = call.argument<Int>("rate")
          val rawCoeffs = call.argument<List<List<Double>>>("coeffs")
          cfg.generation = maxOf(rawGen ?: 0, cfg.generation)
          cfg.enabled = rawEnabled ?: false
          cfg.bandCount = rawCoeffs?.size ?: 0
          cfg.coeffs = (rawCoeffs ?: emptyList()).map { it.toDoubleArray() }.toTypedArray()
          cfg.validForSampleRate = rawRate ?: 0
          processor.config = cfg
          result.success(null)
        }
        "dispose" -> {
          AudioProcessorBridge.setProcessors(emptyArray<AudioProcessor>())
          processor.config = null
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }

    processor.onSampleRateChanged = { sampleRate ->
      rateChannel.invokeMethod("sampleRate", sampleRate, null)
      Unit
    }

    // Real spectrum path: post-EQ PCM from this processor, observed only.
    processor.spectrumTap = spectrumBridge::onPcm
    processor.onPlaybackReset = spectrumBridge::onReset
    processor.onConfigured = { rate -> spectrumBridge.setSampleRate(rate) }
    spectrumBridge.register()
  }

  fun dispose() {
    processor.spectrumTap = null
    processor.onPlaybackReset = null
    processor.onConfigured = null
    spectrumBridge.dispose()
  }
}

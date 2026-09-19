package com.piyushbaniya.vora_tube.audio

import android.annotation.SuppressLint
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Thread-safe configuration snapshot for the parametric equalizer.
 *
 * Only [bandCount], [enabled] and the `coeffs`/`order` arrays are read on the
 * audio thread; they are replaced wholesale via volatile writes on the Flutter
 * thread. [generation] increments on every configuration change.
 */
class ParametricEqConfig {
  @Volatile var generation: Int = 0
  @Volatile var enabled: Boolean = false
  @Volatile var bandCount: Int = 0
  @Volatile var coeffs: Array<DoubleArray> = emptyArray()
  @Volatile var validForSampleRate: Int = 0
}

/**
 * Real parametric equalizer implemented as a Media3 [AudioProcessor] sitting in
 * the just_audio ExoPlayer audio chain, immediately after decode.
 *
 * Each band is a second-order biquad (RBJ cookbook coefficients computed on the
 * Flutter side and pushed via a MethodChannel) and the bands run serially over
 * every decoded sample. The processor is always present in the chain but is a
 * byte-for-byte pass-through whenever the config is disabled or its
 * coefficients are not valid for the current sample rate, so it can never
 * colour audio unless parametric mode is explicitly active.
 *
 * The hot path ([queueInput]) performs no allocation, no locking and no
 * platform-channel traffic: it only reads volatile coordinates, runs the biquad
 * difference equation and applies a short per-channel crossfade whenever the
 * config generation changes (a cheap, bounded pop/click suppressor).
 */
@SuppressLint("UnsafeOptInUsageError", "UnsafeExperimentalUsageError")
class VoraTubeParametricEqProcessor : AudioProcessor {
  private var sampleRate = 0
  private var channels = 2
  private var encoding = C.ENCODING_PCM_16BIT

  private var processedGeneration = Int.MIN_VALUE
  private var fadeRemaining = 0
  private var prevOut = DoubleArray(2)

  private val bandStates = ArrayList<DoubleArray>()

  private var outputBuffer = ByteBuffer.allocateDirect(0)

  @Volatile
  var config: ParametricEqConfig? = null

  /** Callback for the sample-rate events Dart needs to recompute biquads. */
  var onSampleRateChanged: ((Int) -> Unit)? = null

  override fun getDurationAfterProcessorApplied(inputDurationUs: Long): Long = inputDurationUs

  override fun configure(inputFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
    sampleRate = inputFormat.sampleRate
    channels = inputFormat.channelCount
    encoding = inputFormat.encoding
    if (prevOut.size != channels) prevOut = DoubleArray(channels)
    val cfg = config
    if (cfg != null && cfg.enabled && cfg.bandCount > 0 &&
        cfg.validForSampleRate != sampleRate) {
      onSampleRateChanged?.invoke(sampleRate)
    }
    return AudioProcessor.AudioFormat(sampleRate, channels, encoding)
  }

  override fun isActive(): Boolean = true

  override fun queueInput(byteBuffer: ByteBuffer) {
    val cfg = config
    val active = cfg != null && cfg.enabled && cfg.bandCount > 0
    if (!active || sampleRate == 0 || cfg.validForSampleRate != sampleRate) {
      // Bypassed or coefficients not ready for this rate: copy unchanged.
      rawCopy(byteBuffer)
      return
    }
    if (processedGeneration != cfg.generation) {
      processedGeneration = cfg.generation
      fadeRemaining = FADE_SAMPLES
    }
    if (bandStates.size != cfg.bandCount) {
      bandStates.clear()
      repeat(cfg.bandCount) { bandStates.add(DoubleArray(channels * 4)) }
    }

    val outBuf = ensureOutput(byteBuffer.remaining())
    if (encoding == C.ENCODING_PCM_FLOAT) {
      processFloat(byteBuffer, outBuf, cfg)
    } else {
      processShort(byteBuffer, outBuf, cfg)
    }
    outputBuffer.flip()
  }

  override fun queueEndOfStream() {}

  override fun getOutput(): ByteBuffer = outputBuffer

  override fun isEnded(): Boolean = false

  override fun flush() {
    // Keep filtering state across seeks; a fresh config generation already
    // triggers the short crossfade and biquad state decays in a few samples.
    fadeRemaining = 0
  }

  override fun reset() {
    outputBuffer.clear()
    bandStates.forEach { it.fill(0.0) }
    processedGeneration = Int.MIN_VALUE
    fadeRemaining = 0
    prevOut.fill(0.0)
  }

  private fun ensureOutput(bytes: Int): ByteBuffer {
    if (outputBuffer.capacity() < bytes) {
      outputBuffer = ByteBuffer.allocateDirect(bytes).order(ByteOrder.LITTLE_ENDIAN)
    } else {
      outputBuffer.clear()
    }
    return outputBuffer
  }

  private fun rawCopy(input: ByteBuffer) {
    val out = ensureOutput(input.remaining())
    while (input.hasRemaining()) out.put(input.get())
    outputBuffer.flip()
  }

  private fun processShort(input: ByteBuffer, out: ByteBuffer, cfg: ParametricEqConfig) {
    while (input.hasRemaining()) {
      if (input.remaining() < channels * 2) {
        // Partial trailing frame: copy verbatim rather than drop samples.
        while (input.hasRemaining()) out.put(input.get())
        return
      }
      for (ch in 0 until channels) {
        var sample = input.short.toDouble() * (1.0 / 32768.0)
        sample = processBands(sample, ch, cfg)
        sample *= 32768.0
        out.putShort(sample.coerceIn(-32768.0, 32767.0).toInt().toShort())
      }
    }
  }

  private fun processFloat(input: ByteBuffer, out: ByteBuffer, cfg: ParametricEqConfig) {
    while (input.hasRemaining()) {
      if (input.remaining() < channels * 4) {
        while (input.hasRemaining()) out.put(input.get())
        return
      }
      for (ch in 0 until channels) {
        var sample = input.float.toDouble()
        sample = processBands(sample, ch, cfg)
        out.putFloat(sample.toFloat())
      }
    }
  }

  /**
   * Runs the sample through every enabled biquad, then applies a per-channel
   * linear crossfade bridging the previous output when the config changed
   * (kills enable/disable/mode-switch clicks).
   */
  private fun processBands(initial: Double, ch: Int, cfg: ParametricEqConfig): Double {
    var sample = initial
    var band = 0
    while (band < cfg.bandCount) {
      val c = cfg.coeffs[band]
      val s = bandStates[band]
      val base = ch * 4
      val x1 = s[base]
      val x2 = s[base + 1]
      val y1 = s[base + 2]
      val y2 = s[base + 3]
      val y = c[0] * sample + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
      s[base] = sample
      s[base + 1] = x1
      s[base + 2] = y
      s[base + 3] = y1
      sample = y
      band++
    }
    if (fadeRemaining > 0) {
      val step = fadeRemaining.toDouble() / FADE_SAMPLES.toDouble()
      val blended = prevOut[ch] * step + sample * (1.0 - step)
      prevOut[ch] = blended
      fadeRemaining--
      return blended
    }
    prevOut[ch] = sample
    return sample
  }

  private companion object {
    const val FADE_SAMPLES = 512
  }
}
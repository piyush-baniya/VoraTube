package com.piyushbaniya.vora_tube.audio

import android.annotation.SuppressLint
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Exercises the real production spectrum path end to end: decoded PCM → the
 * actual [VoraTubeParametricEqProcessor] post-EQ tap → the actual
 * [SpectrumAnalyzer]. A parametric boost/cut at 1 kHz must move the spectrum in
 * the matching band and nowhere else, which is what makes the visualizer real
 * rather than decorative.
 */
@SuppressLint("UnsafeOptInUsageError")
class VoraTubeParametricEqProcessorTest {

  private val rate = 48000

  /** RBJ peaking biquad `[b0, b1, b2, a1, a2]`, matching parametric_eq.dart. */
  private fun peakingConfig(gainDb: Double, freq: Double = 1000.0, q: Double = 1.0): ParametricEqConfig {
    val w0 = 2.0 * PI * freq / rate
    val alpha = sin(w0) / (2.0 * q)
    val a = 10.0.pow(gainDb / 40.0)
    val cosW = cos(w0)
    val b0 = 1 + alpha * a
    val b1 = -2 * cosW
    val b2 = 1 - alpha * a
    val a0 = 1 + alpha / a
    val a1 = -2 * cosW
    val a2 = 1 - alpha / a
    val inv = 1.0 / a0
    val cfg = ParametricEqConfig()
    cfg.generation = 1
    cfg.enabled = true
    cfg.bandCount = 1
    cfg.coeffs = arrayOf(doubleArrayOf(b0 * inv, b1 * inv, b2 * inv, a1 * inv, a2 * inv))
    cfg.validForSampleRate = rate
    return cfg
  }

  /** Continuous-phase stereo tone(s); [tones] are (frequency, amplitude) pairs. */
  private fun tone(
    frames: Int,
    phaseOffset: Int,
    vararg tones: Pair<Double, Double>,
  ): ByteBuffer {
    val buffer = ByteBuffer.allocate(frames * 2 * 2).order(ByteOrder.LITTLE_ENDIAN)
    for (i in 0 until frames) {
      val t = (phaseOffset + i).toDouble()
      var v = 0.0
      for ((freq, amp) in tones) v += amp * sin(2.0 * PI * freq * t / rate)
      val s = (v * 32767.0).toInt().coerceIn(-32768, 32767).toShort()
      buffer.putShort(s)
      buffer.putShort(s)
    }
    buffer.flip()
    return buffer
  }

  /**
   * Pushes [frames] of audio through the processor with [cfg] and returns the
   * newest spectrum frame the analyzer produced from the post-EQ tap.
   */
  private fun analyze(cfg: ParametricEqConfig?, vararg tones: Pair<Double, Double>): FloatArray {
    val analyzer = SpectrumAnalyzer().apply { updateSampleRate(rate) }
    analyzer.start()
    val processor = VoraTubeParametricEqProcessor()
    // Exactly what VoraTubeParametricEqBridge wires up in production.
    processor.spectrumTap = { buffer, channels, isFloat ->
      analyzer.feedFrame(buffer, channels, isFloat)
    }
    processor.configure(AudioProcessor.AudioFormat(rate, 2, C.ENCODING_PCM_16BIT))
    processor.config = cfg

    val frames = 16384
    var fed = 0
    while (fed < frames) {
      val chunk = minOf(2048, frames - fed)
      processor.queueInput(tone(chunk, fed, *tones))
      fed += chunk
    }
    val frame = analyzer.pullFrame()
    assertEquals(SpectrumAnalyzer.BAND_COUNT, frame!!.size)
    for (v in frame) assertTrue("bad band value $v", !v.isNaN() && v in 0f..1f)
    return frame
  }

  private fun bandOf(freq: Double): Int =
    (ln(freq / 20.0) / ln(rate / 2.0 / 20.0) * SpectrumAnalyzer.BAND_COUNT).toInt()

  @Test
  fun bypassPathStillFeedsTheAnalyzer() {
    // No parametric config: the processor raw-copies and must still tap.
    val frame = analyze(null, 1000.0 to 0.25)
    val band = bandOf(1000.0)
    assertTrue("peak ${frame[band]}", frame[band] > 0.3f)
    assertTrue(frame[band] >= frame.max())
  }

  @Test
  fun parametricBoostRaisesTheMatchingBand() {
    val flat = analyze(null, 1000.0 to 0.05)
    val boosted = analyze(peakingConfig(12.0), 1000.0 to 0.05)
    val band = bandOf(1000.0)
    assertTrue("boosted ${boosted[band]} vs flat ${flat[band]}", boosted[band] > flat[band] + 0.05f)
  }

  @Test
  fun parametricCutLowersTheMatchingBand() {
    val flat = analyze(null, 1000.0 to 0.05)
    val cut = analyze(peakingConfig(-12.0), 1000.0 to 0.05)
    val band = bandOf(1000.0)
    assertTrue("cut ${cut[band]} vs flat ${flat[band]}", cut[band] < flat[band] - 0.05f)
  }

  @Test
  fun parametricMoveDoesNotFabricateEnergyElsewhere() {
    val tones = arrayOf(1000.0 to 0.05, 8000.0 to 0.05)
    val flat = analyze(null, *tones)
    val boosted = analyze(peakingConfig(12.0), *tones)
    val lowBand = bandOf(1000.0)
    val highBand = bandOf(8000.0)
    assertTrue("1 kHz should rise", boosted[lowBand] > flat[lowBand] + 0.05f)
    assertTrue("8 kHz should be untouched", abs(boosted[highBand] - flat[highBand]) < 0.1f)
  }
}

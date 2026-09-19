package com.piyushbaniya.vora_tube.audio

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tests the exact production SpectrumAnalyzer used by the audio pipeline:
 * sine peaks land in the correct log band, silence yields zero, stereo is
 * averaged, output is finite and always 48 bands.
 */
class SpectrumAnalyzerTest {

  private fun analyzer(rate: Int) = SpectrumAnalyzer().apply { updateSampleRate(rate) }

  private fun pcmSine(rate: Int, freq: Double, frames: Int, amplitude: Double = 0.5): ByteBuffer {
    val buffer = ByteBuffer.allocate(frames * 2 * 2).order(ByteOrder.LITTLE_ENDIAN)
    for (i in 0 until frames) {
      val s = (amplitude * 32767.0 * sin(2.0 * PI * freq * i / rate)).toInt().toShort()
      buffer.putShort(s) // left
      buffer.putShort(s) // right
    }
    buffer.flip()
    return buffer
  }

  private fun peakBand(values: FloatArray): Int {
    var best = 0
    for (i in values.indices) if (values[i] > values[best]) best = i
    return best
  }

  private fun feed(analyzer: SpectrumAnalyzer, rate: Int, freq: Double, frames: Int) {
    var fed = 0
    while (fed < frames) {
      val chunk = minOf(4096, frames - fed)
      analyzer.feedFrame(pcmSine(rate, freq, chunk), 2, false)
      fed += chunk
    }
  }

  @Test
  fun silenceProducesNearZero() {
    val a = analyzer(48000)
    a.start()
    a.feedFrame(pcmSine(48000, 1000.0, 4096), 2, false)
    // Overwrite with silence.
    val silence = ByteBuffer.allocate(4096 * 2 * 2).order(ByteOrder.LITTLE_ENDIAN)
    a.feedFrame(silence, 2, false)
    val frame = a.pullFrame()
    assertNotNull(frame)
    for (v in frame!!) assertTrue("band too loud: $v", v < 0.05f)
  }

  @Test
  fun sine1kHzPeaksNear1kHzBand() {
    val a = analyzer(48000)
    a.start()
    feed(a, 48000, 1000.0, 8192)
    val frame = a.pullFrame()
    assertNotNull(frame)
    assertEquals(SpectrumAnalyzer.BAND_COUNT, frame!!.size)
    val peak = peakBand(frame)
    // Log grid 20 Hz → 24 kHz: 1 kHz sits near band 26.
    assertTrue("peak band $peak", peak in 24..28)
    assertTrue(frame[peak] > 0.5f)
  }

  @Test
  fun sine100HzPeaksLow() {
    val a = analyzer(48000)
    a.start()
    feed(a, 48000, 100.0, 8192)
    val frame = a.pullFrame()!!
    val peak = peakBand(frame)
    // log(100/20)/log(1200)*48 ≈ band 11.
    assertTrue("peak band $peak", peak in 8..14)
  }

  @Test
  fun sine10kHzPeaksHigh() {
    val a = analyzer(48000)
    a.start()
    feed(a, 48000, 10000.0, 8192)
    val frame = a.pullFrame()!!
    val peak = peakBand(frame)
    // log(10000/20)/log(1200)*48 ≈ band 42.
    assertTrue("peak band $peak", peak in 39..44)
  }

  @Test
  fun twoToneShowTwoRegions() {
    val a = analyzer(48000)
    a.start()
    val buffer = ByteBuffer.allocate(8192 * 2 * 2).order(ByteOrder.LITTLE_ENDIAN)
    for (i in 0 until 8192) {
      val s = (0.4 * 32767 * (sin(2 * PI * 100.0 * i / 48000) + sin(2 * PI * 8000.0 * i / 48000))).toInt().toShort()
      buffer.putShort(s); buffer.putShort(s)
    }
    buffer.flip()
    a.feedFrame(buffer, 2, false)
    val frame = a.pullFrame()!!
    assertTrue("low region energy", frame[8..14].max() > 0.4f)
    assertTrue("high region energy", frame[33..41].max() > 0.4f)
  }

  @Test
  fun outputIsFiniteAndBounded() {
    val a = analyzer(48000)
    a.start()
    feed(a, 48000, 440.0, 4096)
    val frame = a.pullFrame()!!
    for (v in frame) {
      assertTrue("NaN/infinite band", !v.isNaN() && !v.isInfinite())
      assertTrue("out of range: $v", v >= 0f && v <= 1f)
    }
  }

  @Test
  fun stereoIsAveraged() {
    val a = analyzer(48000)
    a.start()
    val buffer = ByteBuffer.allocate(4096 * 2 * 2).order(ByteOrder.LITTLE_ENDIAN)
    for (i in 0 until 4096) {
      buffer.putShort(0.toShort()) // silent left
      val s = (0.5 * 32767 * sin(2 * PI * 1000.0 * i / 48000)).toInt().toShort()
      buffer.putShort(s) // full right
    }
    buffer.flip()
    a.feedFrame(buffer, 2, false)
    val frame = a.pullFrame()!!
    assertTrue(frame[peakBand(frame)] > 0.4f)
  }

  @Test
  fun worksAt44100And96000() {
    for (rate in intArrayOf(44100, 96000)) {
      val a = analyzer(rate)
      a.start()
      feed(a, rate, 1000.0, 8192)
      val frame = a.pullFrame()
      assertNotNull(frame)
      assertEquals(SpectrumAnalyzer.BAND_COUNT, frame!!.size)
      val peak = peakBand(frame)
      val expected = (kotlin.math.ln(1000.0 / 20.0) / kotlin.math.ln(rate / 2.0 / 20.0) * 48).toInt()
      assertTrue("rate $rate peak $peak vs $expected", kotlin.math.abs(peak - expected) <= 2)
    }
  }

  @Test
  fun nyquistDoesNotCollapse() {
    val a = analyzer(48000)
    a.start()
    feed(a, 48000, 20000.0, 8192)
    val frame = a.pullFrame()!!
    assertTrue("top bands all zero", frame[40..47].max() > 0.2f)
  }

  @Test
  fun stopPreventsFrames() {
    val a = analyzer(48000)
    a.start()
    feed(a, 48000, 1000.0, 4096)
    a.stop()
    assertEquals(null, a.pullFrame())
  }

  @Test
  fun flushClearsStaleAudio() {
    val a = analyzer(48000)
    a.start()
    feed(a, 48000, 1000.0, 4096)
    a.flush()
    // A full ring of new audio must overwrite every stale sample.
    feed(a, 48000, 20000.0, 32768)
    val frame = a.pullFrame()!!
    // Stale 1 kHz energy is gone from the region where it used to peak.
    assertTrue(frame[24..28].max() < 0.35f)
    assertTrue(frame[peakBand(frame)] > 0.5f)
  }

  @Test
  fun pauseDecaysSpectrumToZero() {
    val a = analyzer(48000)
    a.start()
    feed(a, 48000, 1000.0, 4096)
    val active = a.pullFrame()!!
    assertTrue(active[peakBand(active)] > 0.4f)
    // Playback paused: no new PCM. Repeated frames must decay to silence.
    var last = active
    for (n in 1..40) {
      last = a.pullFrame()!!
    }
    assertTrue(last[peakBand(last)] < 0.05f)
  }

  @Test
  fun smoothingRisesThenDecays() {
    val a = analyzer(48000)
    a.start()
    feed(a, 48000, 1000.0, 4096)
    val first = a.pullFrame()!!
    feed(a, 48000, 1000.0, 4096)
    val second = a.pullFrame()!!
    // Attack smoothing: values climb towards the target rather than jump.
    assertTrue(second[peakBand(second)] >= first[peakBand(first)])
  }
}

private operator fun FloatArray.get(range: IntRange): FloatArray =
  FloatArray(range.count()) { this[range.first + it] }

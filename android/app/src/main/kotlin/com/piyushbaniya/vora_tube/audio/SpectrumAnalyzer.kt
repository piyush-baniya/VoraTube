package com.piyushbaniya.vora_tube.audio

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.ShortBuffer
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.min
import kotlin.math.sin

/**
 * Real-time FFT spectrum analyzer.
 *
 * The processor taps post-EQ PCM and feeds it via [feedFrame] on the audio
 * thread; the analysis itself ([pullFrame]) runs on a dedicated worker at
 * most ~30 times per second. [feedFrame] is a bounded copy into a fixed-size
 * roll buffer — it never allocates and never grows, so it is safe for the
 * realtime path. Analysis is observation only: it can never alter the audio.
 *
 * PCM format: 16-bit signed little-endian or 32-bit float, interleaved.
 */
class SpectrumAnalyzer {

  companion object {
    const val BAND_COUNT = 48
    const val BAND_MIN_HZ = 20.0
    const val FRAME_INTERVAL_MS = 33L // ~30 fps ceiling
  }

  private val fftSize = 4096
  private val noiseFloorDb = -66.0
  private val ceilingDb = -6.0

  @Volatile
  var enabled: Boolean = false
    private set

  // Fixed-size mono roll buffer. Audio thread writes newest samples,
  // overwriting the oldest; worker snapshots under the same lightweight lock.
  private val ring = FloatArray(fftSize)
  private var ringWrite = 0
  private var ringFilled = 0

  // Precomputed FFT tables (allocation-free hot path).
  private val bitReverse = IntArray(fftSize)
  private val cosTable = DoubleArray(fftSize / 2)
  private val sinTable = DoubleArray(fftSize / 2)
  private val hann = DoubleArray(fftSize)
  private val windowGain: Double

  private val re = DoubleArray(fftSize)
  private val im = DoubleArray(fftSize)
  private val magnitudes = DoubleArray(fftSize / 2)
  /** Reused worker-side analysis window (never touched by the audio thread). */
  private val window = FloatArray(fftSize)
  private val smoothed = FloatArray(BAND_COUNT)

  /**
   * Band → FFT-bin grid for the current sample rate. Replaced wholesale so the
   * worker always reads one consistent grid while the rate changes.
   */
  @Volatile
  private var bandEdges = IntArray(BAND_COUNT + 1)
  private var fedTotal = 0L

  @Volatile
  private var lastFedTotal = -1L

  @Volatile
  var sampleRate: Int = 48000
    private set

  init {
    val n = fftSize
    var bits = 0
    while (1 shl bits < n) bits++
    for (i in 0 until n) {
      var r = 0
      for (b in 0 until bits) if (i and (1 shl b) != 0) r = r or (1 shl (bits - 1 - b))
      bitReverse[i] = r
    }
    for (i in 0 until n / 2) {
      val angle = -2.0 * PI * i / n
      cosTable[i] = cos(angle)
      sinTable[i] = sin(angle)
    }
    var sumW = 0.0
    for (i in 0 until n) {
      val w = 0.5 - 0.5 * cos(2.0 * PI * i / n)
      hann[i] = w
      sumW += w
    }
    windowGain = 2.0 / sumW // Hann amplitude-correction factor
    computeBandEdges()
  }

  /** Re-aligns the log band grid to the actual playback sample rate. */
  fun updateSampleRate(rate: Int) {
    if (rate <= 0 || rate == sampleRate) return
    sampleRate = rate
    flush()
    computeBandEdges()
  }

  private fun computeBandEdges() {
    val minLog = ln(BAND_MIN_HZ)
    val maxLog = ln(sampleRate / 2.0)
    val edges = IntArray(BAND_COUNT + 1)
    var prev = 1
    for (b in 0 until BAND_COUNT) {
      val f = kotlin.math.exp(minLog + (maxLog - minLog) * b / BAND_COUNT)
      val bin = (f * fftSize / sampleRate).toInt().coerceIn(prev, fftSize / 2 - 1)
      edges[b] = bin
      prev = bin + 1
    }
    edges[BAND_COUNT] = fftSize / 2
    bandEdges = edges
  }

  /** Begin analysis. Resets stale buffer state. */
  fun start() {
    synchronized(ring) {
      ringWrite = 0
      ringFilled = 0
    }
    synchronized(smoothed) {
      java.util.Arrays.fill(smoothed, 0f)
    }
    lastFedTotal = -1L
    enabled = true
  }

  /** Stop analysis; drops buffered audio and stops producing frames. */
  fun stop() {
    enabled = false
    flush()
  }

  /** Clears stale buffered audio (seek / track change / pause restart). */
  fun flush() {
    synchronized(ring) {
      ringWrite = 0
      ringFilled = 0
    }
  }

  /**
   * Audio-thread tap. Copies the buffer into the bounded roll buffer;
   * no allocation and a monitor held only over a small float copy.
   */
  fun feedFrame(buffer: ByteBuffer, channels: Int, isFloat: Boolean) {
    if (!enabled || channels <= 0) return
    val dup = buffer.duplicate().order(ByteOrder.LITTLE_ENDIAN)
    synchronized(ring) {
      if (isFloat) {
        while (dup.remaining() >= 4 * channels) {
          var acc = 0f
          for (c in 0 until channels) acc += dup.float
          ring[ringWrite] = acc / channels
          ringWrite = (ringWrite + 1) % fftSize
          if (ringFilled < fftSize) ringFilled++
          fedTotal++
        }
      } else {
        val shorts: ShortBuffer = dup.asShortBuffer()
        val frames = shorts.remaining() / channels
        for (f in 0 until frames) {
          var acc = 0
          for (c in 0 until channels) acc += shorts.get().toInt()
          ring[ringWrite] = acc / channels / 32768f
          ringWrite = (ringWrite + 1) % fftSize
          if (ringFilled < fftSize) ringFilled++
          fedTotal++
        }
      }
    }
  }

  /**
   * Worker-side: compute the newest 48-band spectrum frame, or null when not
   * enough audio has accumulated. Values are normalized 0..1 loudness with
   * attack/decay smoothing applied (decay reaches 0 on silence, so pause
   * decays the display naturally).
   */
  fun pullFrame(): FloatArray? {
    if (!enabled) return null
    val fedNow: Long
    synchronized(ring) {
      if (ringFilled < fftSize) return null
      fedNow = fedTotal
      var read = ringWrite // oldest sample sits at the write cursor
      for (i in 0 until fftSize) {
        window[i] = ring[read]
        read = (read + 1) % fftSize
      }
    }
    if (fedNow == lastFedTotal) {
      // No new audio since the last frame (playback paused): decay the
      // display smoothly to silence instead of freezing.
      synchronized(smoothed) {
        for (i in smoothed.indices) {
          smoothed[i] *= 0.85f
          if (smoothed[i] < 0.005f) smoothed[i] = 0f
        }
      }
      lastFedTotal = fedNow
      return smoothed.copyOf()
    }
    lastFedTotal = fedNow
    for (i in 0 until fftSize) {
      re[i] = window[i] * hann[i]
      im[i] = 0.0
    }
    transform()
    for (i in 0 until fftSize / 2) {
      magnitudes[i] = hypot(re[i], im[i]) * windowGain
    }

    val next = FloatArray(BAND_COUNT)
    for (b in 0 until BAND_COUNT) {
      val lo = bandEdges[b]
      val hi = min(bandEdges[b + 1], fftSize / 2)
      if (hi <= lo) continue
      var peak = 0.0
      for (i in lo until hi) {
        val m = magnitudes[i]
        if (m > peak) peak = m
      }
      val db = 20.0 * log10(peak + 1e-9)
      next[b] = (((db - noiseFloorDb) / (ceilingDb - noiseFloorDb)).coerceIn(0.0, 1.0)).toFloat()
    }
    synchronized(smoothed) {
      for (i in next.indices) {
        val target = next[i]
        val current = smoothed[i]
        val coef = if (target > current) 0.55f else 0.16f
        smoothed[i] = current + coef * (target - current)
        next[i] = smoothed[i]
      }
    }
    return next
  }

  /** Iterative radix-2 Cooley-Tukey FFT, in place on [re]/[im]. */
  private fun transform() {
    val n = fftSize
    for (i in 0 until n) {
      val j = bitReverse[i]
      if (j > i) {
        val tr = re[i]; re[i] = re[j]; re[j] = tr
        val ti = im[i]; im[i] = im[j]; im[j] = ti
      }
    }
    var size = 2
    while (size <= n) {
      val half = size / 2
      val tableStep = n / size
      for (start in 0 until n step size) {
        var k = 0
        for (j in start until start + half) {
          val twR = cosTable[k]
          val twI = sinTable[k]
          val i2 = j + half
          val tr = re[i2] * twR - im[i2] * twI
          val ti = re[i2] * twI + im[i2] * twR
          re[i2] = re[j] - tr
          im[i2] = im[j] - ti
          re[j] += tr
          im[j] += ti
          k += tableStep
        }
      }
      size *= 2
    }
  }
}

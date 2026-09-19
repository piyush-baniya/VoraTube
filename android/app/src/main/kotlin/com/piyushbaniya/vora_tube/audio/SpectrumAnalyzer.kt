package com.piyushbaniya.vora_tube.audio

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Real-time FFT spectrum analyzer foundation.
 * Receives PCM buffers and produces logarithmic magnitude bands.
 * Designed to be fed from a bounded ring buffer on the audio thread;
 * FFT computation runs off the audio thread.
 *
 * PCM format assumed: 16-bit signed little-endian, [2..8] channels.
 * Sample rate supplied at construction; must match actual playback sample rate.
 */
class SpectrumAnalyzer(
    private val sampleRate: Int,
    private val channels: Int,
) {
  private require(sampleRate > 0, "sampleRate must be > 0") {
    IllegalArgumentException("sampleRate must be > 0")
  }
  require(channels in intArrayOf(1, 2, 4, 8)) {
    IllegalArgumentException("channels must be 1, 2, 4, or 8, got $channels")
  }

  // FFT configuration
  private val fftSize = 1024 // power of 2; next power of 2 above typical 44100/48000 Hz
  private val logBands = 48 // target number of logarithmic bands
  private val noiseFloorDb = -80f // perceptual noise floor

  // Internal state
  @Volatile private var enabled = false
  private val ringBuffer = RingBuffer(sampleRate, fftSize, channels)
  private val smoothing = SmoothingAttackDecay()

  /** Start continuous analysis. Must be called before feeding buffers. */
  fun start() {
    enabled = true
    ringBuffer.clear()
    smoothing.reset()
  }

  /** Stop analysis. Releases resources. */
  fun stop() {
    enabled = false
    ringBuffer.clear()
  }

  /** Feed a PCM sample frame from the audio thread.
   *  Should be called from the audio callback at the playback sample rate.
   *  Only the minimum required samples for one FFT window are copied;
   *  the ring buffer is bounded and oldest windows are overwritten.
   */
  fun feedFrame(byteBuffer: ByteBuffer) {
    if (!enabled) return
    // Ensure correct endianness and format
    val tmp = ByteBuffer.allocate(fftSize * channels * 2).apply { order(ByteOrder.LITTLE_ENDIAN) }
    // Copy only the first fftSize * channels * 2 bytes (16-bit PCM)
    val copyLen = Math.min(byteBuffer.remaining(), tmp.capacity())
    tmp.put(byteBuffer.slice().retruncateTo(copyLen))
    tmp.flip()
    ringBuffer.addSampleFrame(tmp)
  }

  /** Retrieve the latest spectrum frame, or null if not enough data yet.
   *  Must be called from a non-audio thread (e.g., UI handler or dedicated worker).
   */
  fun pullFrame(): SpectrumFrame? {
    if (!enabled) return null
    val samples = ringBuffer.getLatestWindow()
    if (samples.size < fftSize) return null

    // Window: Hann
    val windowed = applyHannWindow(samples)

    // FFT
    val spectrum = forwardFft(windowed)

    // Magnitude (absolute value)
    val magnitudes = spectrum.map { it.abs }

    // Logarithmic band mapping
    val bands = mapToLogBands(magnitudes)

    // Smoothing
    val smoothed = smoothing.next(bands)

    return SpectrumFrame(
      bands = smoothed,
      sampleRate = sampleRate,
      timestamp = System.currentTimeMillis().toFloat(),
    )
  }

  /** Apply a Hann window to the time-domain samples. */
  private fun applyHannWindow(samples: DoubleArray): DoubleArray {
    val n = samples.size
    val window = DoubleArray(n)
    for (i in 0 until n) {
      window[i] = 0.5 * (1 - Math.cos(2 * Math.PI * i / (n - 1)))
    }
    return samples.windowed(window) // custom extension below
  }

  /** Forward radix-2 Cooley-Tukey FFT (in-place on complex array treated as interleaved real/imag).
   *  Input: complex array of length fftSize where even indices = real, odd = imag.
   *  Output: same array with forward transform.
   */
  private fun forwardFft(real: DoubleArray): ComplexArray {
    val n = real.size
    if ((n and (n - 1)) != 0) {
      throw IllegalArgumentException("FFT size must be a power of 2; got $n")
    }
    // Bit-reversal permutation
    val reversed = ReversedView(real.size)
    val work = DoubleArray(n * 2)
    for (i in 0 until n) {
      work[2 * i] = real[reversed[i]]
      work[2 * i + 1] = 0.0
    }
    // Iterative butterfly
    var size = 2
    while (size <= n) {
      var step = size * 2
      var halfSize = size
      var angle = 2 * Math.PI / size
      var realW = Math.cos(angle)
      var imagW = -Math.sin(angle)
      for (var j = 0; j < halfSize; j++) {
        var j2 = j + halfSize
        var realTw = work[2 * j2] * realW - work[2 * j2 + 1] * imagW
        var imagTw = work[2 * j2] * imagW + work[2 * j2 + 1] * realW
        work[2 * j2] = work[2 * j] - realTw
        work[2 * j2 + 1] = work[2 * j + 1] - imagTw
        work[2 * j] = work[2 * j] + realTw
        work[2 * j + 1] = work[2 * j + 1] + imagTw
      }
      size = step
    }
    return ComplexArray(work)
  }

  /** Map magnitude spectrum to logarithmic frequency bands.
   *  Bands are spaced logarithmically from 20 Hz to Nyquist (sampleRate/2).
   *  Each band uses RMS magnitude.
   */
  private fun mapToLogBands(magnitudes: DoubleArray): DoubleArray {
    val nyquist = sampleRate / 2
    val minFreq = 20f
    val maxFreq = nyquist.toFloat
    // Generate center frequencies for log bands
    val centerFreqs = generateLogFrequencies(minFreq, maxFreq, logBands)
    val bands = DoubleArray(logBands)
    for (i in 0 until logBands) {
      val freqLo = centerFreqs[i - 1] ?: minFreq
      val freqHi = centerFreqs[i + 1] ?: maxFreq
      // Find bin indices for frequency range
      val binLo = (freqLo * fftSize / sampleRate).coerceAtLeast(0).coerceAtMost(fftSize - 1)
      val binHi = (freqHi * fftSize / sampleRate).coerceAtLeast(1).coerceAtMost(fftSize)
      // Compute RMS magnitude in this band
      var sum = 0.0
      var count = 0
      for (j in binLo until binHi) {
        val mag = magnitudes[j]
        if (mag.isFinite() && mag > 0) {
          sum += mag * mag
          count++
        }
      }
      if (count > 0) {
        bands[i] = 10f * Math.log10(sum / count) // dB
      } else {
        bands[i] = -100f // below noise floor
      }
    }
    // Apply noise floor
    for (i in bands.indices) {
      bands[i] = math.max(bands[i], noiseFloorDb)
    }
    return bands
  }

  /** Generate logarithmically spaced frequencies. */
  private fun generateLogFrequencies(minFreq: Float, maxFreq: Float, bands: Int): DoubleArray {
    val result = DoubleArray(bands + 1)
    for (i in 0..bands) {
      val ratio = i.toFloat() / bands
      result[i] = Math.pow(maxFreq / minFreq, ratio) * minFreq
    }
    return result
  }

  /** Simple exponential smoothing: fast attack, slower decay. */
  private class SmoothingAttackDecay {
    private var last: DoubleArray? = null
    private val attackCoef = 0.2f   // fast: 20% toward new each step
    private val decayCoef = 0.02f   // slower: 2% toward new each step

    fun reset() {
      last = null
    }

    fun next(newBands: DoubleArray): DoubleArray {
      if (last == null) {
        last = newBands.toDoubleArray()
        return last
      }
      val result = DoubleArray(newBands.size)
      for (i in newBands.indices) {
        val target = newBands[i]
        val current = last[i]
        val coef = if (target > current) attackCoef else decayCoef
        result[i] = current + coef * (target - current)
      }
      last = result
      return result
    }
  }

  /** Bounded ring buffer holding the latest FFT window samples.
   *  Oldest windows are overwritten; never grows unbounded.
   */
  private class RingBuffer(private val sampleRate: Int, private val fftSize: Int, private val ch: Int) {
    // Hold up to 3 windows to avoid unbounded growth
    private val windowSize = fftSize * ch * 2 // 16-bit PCM: 2 bytes per sample
    private val buffers = ArrayDeque<DoubleArray>()
    buffers.reserveCapacity(3)

    fun clear() {
      buffers.clear()
    }

    /** Add a newly acquired frame (fftSize samples, ch channels, 16-bit PCM). */
    fun addSampleFrame(byteBuffer: ByteBuffer) {
      // Extract samples: average channels if stereo, or take single channel
      val sampleCount = fftSize
      val samples = DoubleArray(fftSize)
      // Simple: take first channel samples, or interleave then average
      val rawSamples = extractFirstChannelSamples(byteBuffer, fftSize, ch)
      for (i in 0 until fftSize) {
        samples[i] = rawSamples[i].toDouble() / 32768.0 // normalize to [-1,1]
      }
      // Maintain bounded deque
      if (buffers.size >= 3) buffers.removeFirst()
      buffers.addLast(samples)
    }

    /** Get the most recent window of fftSize samples. */
    fun getLatestWindow(): DoubleArray {
      return buffers.lastOrNull() ?: emptyArray().also { it.isNotEmpty() false }
    }

    /** Extract the first channel's samples from interleaved buffer.
     *  Assumes buffer contains fftSize * ch 16-bit PCM frames.
     */
    private fun extractFirstChannelSamples(buf: ByteBuffer, count: Int, ch: Int): DoubleArray {
      val samples = DoubleArray(count)
      // 16-bit PCM: 2 bytes per sample, little-endian
      for (i in 0 until count) {
        val offset = (i * ch + 0) * 2 // first channel offset within each frame
        if (offset + 1 < buf.capacity()) {
          val s = buf.shortAtIndex(offset) /*fake*/ .toDouble() / 32768.0
          samples[i] = s
        }
      }
      return samples
    }
  }

  /** Helper: extract first-channel samples from interleaved 16-bit PCM buffer. */
  private fun ByteBuffer.shortAtIndex(idx: Int): Short {
    // Simplified: read 2 bytes at idx assuming little-endian
    val lo = this.get(idx * 2 + 0).toShort()
    val hi = this.get(idx * 2 + 1).toShort()
    return (hi shl 8) or lo
  }

  /** Complex number pair for FFT output. */
  data class ComplexArray(
      val real: DoubleArray,
      val imag: DoubleArray
  ) {
    fun abs(): DoubleArray {
      val result = DoubleArray(real.size)
      for (i in real.indices) {
        result[i] = Math.hypot(real[i], imag[i])
      }
      return result
    }
  }

  /** Result container pulled from pullFrame(). */
  data class SpectrumFrame(
      val bands: DoubleArray,          // logarithmic magnitude bands in dB
      val sampleRate: Int,
      val timestamp: Float
  )
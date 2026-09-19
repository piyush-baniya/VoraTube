package com.ryanheise.just_audio;

import androidx.media3.common.audio.AudioProcessor;

/**
 * Binding point where a host app can register custom Media3 AudioProcessors
 * before any ExoPlayer is created. just_audio keeps a single, stable reference:
 * the app sets {@link #processors()} exactly once at startup (volatile write
 * happens-before any player is built) and the audio sink reads it once when the
 * player is first initialised.
 */
public final class AudioProcessorBridge {
  private static volatile AudioProcessor[] processors = new AudioProcessor[0];

  private AudioProcessorBridge() {}

  public static void setProcessors(AudioProcessor[] value) {
    processors = value == null ? new AudioProcessor[0] : value;
  }

  public static AudioProcessor[] processors() {
    return processors;
  }
}
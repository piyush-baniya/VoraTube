package com.ryanheise.just_audio;

import android.annotation.SuppressLint;
import android.content.Context;

import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.audio.AudioSink;
import androidx.media3.exoplayer.audio.DefaultAudioSink;

/**
 * Identical to the stock DefaultRenderersFactory except that any audio
 * processors registered through {@link AudioProcessorBridge} are appended to
 * the audio sink. Appending processors does not change just_audio's default
 * behaviour when none are registered (the default sink builders are mirrored
 * exactly), so untouched apps are unaffected.
 */
@SuppressLint({"UnsafeOptInUsageError", "UnsafeExperimentalUsageError"})
final class VoratubeRenderersFactory extends DefaultRenderersFactory {
  VoratubeRenderersFactory(Context context) {
    super(context);
  }

  @Override
  protected AudioSink buildAudioSink(
      Context context, boolean enableFloatOutput, boolean enableAudioTrackPlaybackParams) {
    AudioProcessor[] processors = AudioProcessorBridge.processors();
    DefaultAudioSink.Builder builder =
        new DefaultAudioSink.Builder(context)
            .setEnableFloatOutput(enableFloatOutput)
            .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams);
    if (processors.length > 0) {
      builder.setAudioProcessors(processors);
    }
    return builder.build();
  }
}
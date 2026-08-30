package com.piyushbaniya.vora_tube

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import com.piyushbaniya.vora_tube.audio.VoraTubeAudioUtilBridge
import com.piyushbaniya.vora_tube.audio.VoraTubeVolumeBoosterBridge
import com.piyushbaniya.vora_tube.ingest.VoraTubeIngestBridge
import com.piyushbaniya.vora_tube.storage.VoraTubeDeviceStorageBridge

class MainActivity : AudioServiceActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        VoraTubeIngestBridge(applicationContext)
            .register(flutterEngine.dartExecutor.binaryMessenger)
        VoraTubeDeviceStorageBridge(applicationContext)
            .register(flutterEngine.dartExecutor.binaryMessenger)
        VoraTubeAudioUtilBridge(applicationContext)
            .register(flutterEngine.dartExecutor.binaryMessenger)
        VoraTubeVolumeBoosterBridge(applicationContext)
            .register(flutterEngine.dartExecutor.binaryMessenger)
    }
}
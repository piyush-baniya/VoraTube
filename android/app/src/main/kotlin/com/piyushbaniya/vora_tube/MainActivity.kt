package com.piyushbaniya.vora_tube

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import com.piyushbaniya.vora_tube.ingest.VoraTubeIngestBridge

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        VoraTubeIngestBridge(applicationContext)
            .register(flutterEngine.dartExecutor.binaryMessenger)
    }
}

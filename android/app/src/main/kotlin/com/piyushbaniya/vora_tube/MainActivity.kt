package com.piyushbaniya.vora_tube

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.piyushbaniya.vora_tube.ingest.VoraTubeIngestBridge

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        VoraTubeIngestBridge(applicationContext)
            .register(flutterEngine.dartExecutor.binaryMessenger)
    }
}

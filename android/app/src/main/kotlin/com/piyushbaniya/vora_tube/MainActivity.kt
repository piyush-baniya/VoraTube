package com.piyushbaniya.vora_tube

import android.content.Intent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import com.piyushbaniya.vora_tube.audio.VoraTubeAudioUtilBridge
import com.piyushbaniya.vora_tube.ingest.VoraTubeIngestBridge

class MainActivity : AudioServiceActivity() {

    private var audioBridge: VoraTubeAudioUtilBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        VoraTubeIngestBridge(applicationContext)
            .register(flutterEngine.dartExecutor.binaryMessenger)
        val bridge = VoraTubeAudioUtilBridge(applicationContext)
        this.audioBridge = bridge
        bridge.setActivity(this)
        bridge.register(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onResume() {
        super.onResume()
        audioBridge?.setActivity(this)
    }

    override fun onPause() {
        audioBridge?.setActivity(null)
        super.onPause()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        audioBridge?.onActivityResult(requestCode, resultCode, data)
    }
}

package com.piyushbaniya.vora_tube

import android.content.Intent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import com.piyushbaniya.vora_tube.audio.VoraTubeAudioUtilBridge
import com.piyushbaniya.vora_tube.audio.VoraTubeVolumeBoosterBridge
import com.piyushbaniya.vora_tube.ingest.VoraTubeIngestBridge
import com.piyushbaniya.vora_tube.storage.VoraTubeDeviceStorageBridge
import com.piyushbaniya.vora_tube.storage.VoraTubeMediaDeleteBridge
import com.piyushbaniya.vora_tube.system.VoraTubeAndroidVersionBridge

class MainActivity : AudioServiceActivity() {

    private lateinit var mediaDeleteBridge: VoraTubeMediaDeleteBridge

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
        mediaDeleteBridge = VoraTubeMediaDeleteBridge(applicationContext)
        mediaDeleteBridge.register(flutterEngine.dartExecutor.binaryMessenger)
        VoraTubeAndroidVersionBridge(flutterEngine.dartExecutor.binaryMessenger)
            .register()
    }

    override fun onResume() {
        super.onResume()
        if (::mediaDeleteBridge.isInitialized) {
            mediaDeleteBridge.setActivity(this)
        }
    }

    override fun onPause() {
        super.onPause()
        if (::mediaDeleteBridge.isInitialized) {
            mediaDeleteBridge.setActivity(null)
        }
    }

    override fun onDestroy() {
        if (::mediaDeleteBridge.isInitialized) {
            mediaDeleteBridge.dispose()
        }
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (::mediaDeleteBridge.isInitialized &&
            mediaDeleteBridge.handleActivityResult(requestCode, resultCode)
        ) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
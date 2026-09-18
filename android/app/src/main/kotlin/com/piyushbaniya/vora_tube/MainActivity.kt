package com.piyushbaniya.vora_tube

import android.content.Intent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import com.piyushbaniya.vora_tube.audio.VoraTubeAudioUtilBridge
import com.piyushbaniya.vora_tube.audio.VoraTubeVolumeBoosterBridge
import com.piyushbaniya.vora_tube.ingest.VoraTubeIngestBridge
import com.piyushbaniya.vora_tube.storage.VoraTubeBackupStorageBridge
import com.piyushbaniya.vora_tube.storage.VoraTubeDeviceStorageBridge
import com.piyushbaniya.vora_tube.storage.VoraTubeMediaDeleteBridge
import com.piyushbaniya.vora_tube.system.VoraTubeAndroidVersionBridge
import com.piyushbaniya.vora_tube.system.VoraTubePlayUpdateBridge

class MainActivity : AudioServiceActivity() {

    private lateinit var mediaDeleteBridge: VoraTubeMediaDeleteBridge
    private lateinit var backupStorageBridge: VoraTubeBackupStorageBridge
    private lateinit var playUpdateBridge: VoraTubePlayUpdateBridge

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
        backupStorageBridge = VoraTubeBackupStorageBridge(applicationContext)
        backupStorageBridge.register(flutterEngine.dartExecutor.binaryMessenger)
        VoraTubeAndroidVersionBridge(flutterEngine.dartExecutor.binaryMessenger)
            .register()
        playUpdateBridge = VoraTubePlayUpdateBridge(applicationContext)
        playUpdateBridge.register(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onResume() {
        super.onResume()
        if (::mediaDeleteBridge.isInitialized) {
            mediaDeleteBridge.setActivity(this)
        }
        if (::backupStorageBridge.isInitialized) {
            backupStorageBridge.setActivity(this)
        }
        if (::playUpdateBridge.isInitialized) {
            playUpdateBridge.setActivity(this)
        }
    }

    override fun onPause() {
        super.onPause()
        if (::mediaDeleteBridge.isInitialized) {
            mediaDeleteBridge.setActivity(null)
        }
        if (::backupStorageBridge.isInitialized) {
            backupStorageBridge.setActivity(null)
        }
        if (::playUpdateBridge.isInitialized) {
            playUpdateBridge.setActivity(null)
        }
    }

    override fun onDestroy() {
        if (::mediaDeleteBridge.isInitialized) {
            mediaDeleteBridge.dispose()
        }
        if (::backupStorageBridge.isInitialized) {
            backupStorageBridge.dispose()
        }
        if (::playUpdateBridge.isInitialized) {
            playUpdateBridge.dispose()
        }
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (::backupStorageBridge.isInitialized &&
            backupStorageBridge.handleActivityResult(requestCode, resultCode, data)
        ) {
            return
        }
        if (::mediaDeleteBridge.isInitialized &&
            mediaDeleteBridge.handleActivityResult(requestCode, resultCode)
        ) {
            return
        }
        if (::playUpdateBridge.isInitialized &&
            playUpdateBridge.handleActivityResult(requestCode, resultCode)
        ) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
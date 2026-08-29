package com.piyushbaniya.vora_tube.storage

import android.content.Context
import android.os.Environment
import android.os.StatFs
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Reports real on-device storage numbers to Dart.
 *
 * [StatFs] reads filesystem metadata only, so no storage permission is
 * required. The primary shared-storage partition is used, which matches the
 * "internal storage" figure Android's own Settings > Storage shows on most
 * devices. Any unreadable partition resolves to null and the Dart side renders
 * an "unavailable" state — a storage read must never crash the app.
 */
class VoraTubeDeviceStorageBridge(context: Context) {

    private val appContext = context.applicationContext

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != METHOD) {
                result.notImplemented()
            } else {
                result.success(storageSummary())
            }
        }
    }

    private fun storageSummary(): Map<String, Long>? {
        return try {
            val path = Environment.getExternalStorageDirectory()?.absolutePath
                ?: appContext.filesDir.absolutePath
            val stat = StatFs(path)
            val blockSize = stat.blockSizeLong
            val totalBytes = stat.blockCountLong * blockSize
            val availableBytes = stat.availableBlocksLong * blockSize
            val usedBytes = (totalBytes - availableBytes).coerceAtLeast(0L)
            mapOf(
                "totalBytes" to totalBytes,
                "usedBytes" to usedBytes,
                "availableBytes" to availableBytes,
            )
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        const val CHANNEL = "voratube/device_storage_v1"
        const val METHOD = "getStorageSummary"
    }
}
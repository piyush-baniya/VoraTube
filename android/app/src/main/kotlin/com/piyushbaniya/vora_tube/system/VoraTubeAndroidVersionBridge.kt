package com.piyushbaniya.vora_tube.system

import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Exposes the real Android SDK API level to Flutter.
 *
 * Flutter's `Platform.operatingSystemVersion` reports `Build.VERSION.RELEASE`
 * (e.g. "15"), and on some devices/manufacturers it is a build fingerprint such
 * as "AP3A.240905.015...". Neither is a dependable source of the API level,
 * which is what the permission layer branches on (API 33+ needs
 * `READ_MEDIA_AUDIO`; API 32 and below needs legacy storage). Reading
 * `Build.VERSION.SDK_INT` natively is the only reliable answer.
 */
class VoraTubeAndroidVersionBridge(private val messenger: BinaryMessenger) {

    fun register() {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        const val CHANNEL = "voratube/android_version_v1"
    }
}

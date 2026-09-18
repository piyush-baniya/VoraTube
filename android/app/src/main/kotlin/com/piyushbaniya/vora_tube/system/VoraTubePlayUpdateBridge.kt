package com.piyushbaniya.vora_tube.system

import android.app.Activity
import android.content.Context
import android.os.Build
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.install.InstallState
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class VoraTubePlayUpdateBridge(private val context: Context) :
    InstallStateUpdatedListener {

    private var channel: MethodChannel? = null
    private var manager: AppUpdateManager? = null
    private var activity: Activity? = null
    private var flowResult: MethodChannel.Result? = null
    private var listenerRegistered = false

    fun setActivity(a: Activity?) {
        activity = a
    }

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkForUpdate" -> checkForUpdate(result)
                    "startFlexibleUpdate" -> startFlexibleUpdate(result)
                    "completeUpdate" -> completeUpdate(result)
                    else -> result.notImplemented()
                }
            }
        }
    }

    /**
     * In-app updates only work for the Play-distributed production build. The
     * v2dev package and any sideloaded install (no Play installer) are reported
     * as unsupported so the UI stays silent instead of erroring.
     */
    private fun eligible(): Boolean {
        if (context.packageName != PRODUCTION_PACKAGE) return false
        return installerPackage() == PLAY_STORE_PACKAGE
    }

    private fun installerPackage(): String? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            context.packageManager
                .getInstallSourceInfo(context.packageName)
                .installingPackageName
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getInstallerPackageName(context.packageName)
        }
    } catch (_: Exception) {
        null
    }

    private fun manager(): AppUpdateManager? {
        if (!eligible()) return null
        manager?.let { return it }
        // Always build from the application context so the Play Core client
        // never pins an Activity; the Activity is supplied per flow start.
        return AppUpdateManagerFactory.create(context).also { manager = it }
    }

    private fun checkForUpdate(result: MethodChannel.Result) {
        val m = manager() ?: run { result.success(status(UNSUPPORTED)); return }
        m.appUpdateInfo
            .addOnSuccessListener { info ->
                val mapped = mapUpdate(info)
                // An update already running (or one the user started earlier in
                // this session) needs the install-state listener to stream
                // progress; a plain availability check does not.
                if (mapped["status"] == DOWNLOADING) ensureListener(m)
                result.success(mapped)
            }
            .addOnFailureListener { result.success(status(FAILED)) }
    }

    private fun startFlexibleUpdate(result: MethodChannel.Result) {
        val m = manager() ?: run { result.success(status(UNSUPPORTED)); return }
        val host = activity
        if (host == null || host.isFinishing) {
            result.success(status(FAILED))
            return
        }
        ensureListener(m)
        m.appUpdateInfo
            .addOnSuccessListener { info ->
                if (info.updateAvailability() != UpdateAvailability.UPDATE_AVAILABLE ||
                    !info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE)
                ) {
                    result.success(mapUpdate(info))
                    return@addOnSuccessListener
                }
                // A stale pending flow must never be left hanging.
                flowResult?.success(status(CANCELED))
                flowResult = result
                val started = m.startUpdateFlowForResult(
                    info,
                    AppUpdateType.FLEXIBLE,
                    host,
                    REQUEST_CODE,
                )
                if (!started) {
                    flowResult = null
                    result.success(status(FAILED))
                }
            }
            .addOnFailureListener { result.success(status(FAILED)) }
    }

    private fun completeUpdate(result: MethodChannel.Result) {
        val m = manager() ?: run { result.success(status(UNSUPPORTED)); return }
        try {
            m.completeUpdate()
            result.success(status(INSTALLING))
        } catch (_: Exception) {
            result.success(status(FAILED))
        }
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val pending = flowResult
        flowResult = null
        pending?.success(
            if (resultCode == Activity.RESULT_OK) {
                mapOf("status" to "downloading")
            } else {
                mapOf("status" to "canceled")
            },
        )
        return true
    }

    override fun onStateUpdate(state: InstallState) {
        channel?.invokeMethod("onInstallState", mapInstallState(state))
    }

    private fun ensureListener(m: AppUpdateManager) {
        if (!listenerRegistered) {
            m.registerListener(this)
            listenerRegistered = true
        }
    }

    private fun mapUpdate(info: AppUpdateInfo): Map<String, Any?> {
        val status = when {
            info.installStatus() == InstallStatus.DOWNLOADED -> DOWNLOADED
            info.installStatus() == InstallStatus.INSTALLING -> INSTALLING
            info.installStatus() == InstallStatus.INSTALLED -> INSTALLED
            info.installStatus() == InstallStatus.DOWNLOADING ||
                info.installStatus() == InstallStatus.PENDING ||
                info.updateAvailability() ==
                UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS -> DOWNLOADING
            info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE -> AVAILABLE
            else -> NOT_AVAILABLE
        }
        val map = mutableMapOf<String, Any?>(
            "status" to status,
            "updatePriority" to info.updatePriority(),
            "isFlexibleAllowed" to info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
        )
        info.availableVersionCode()?.let { map["availableVersionCode"] = it }
        info.clientVersionStalenessDays()?.let { map["stalenessDays"] = it }
        return map
    }

    private fun mapInstallState(state: InstallState): Map<String, Any?> = mapOf(
        "status" to when (state.installStatus()) {
            InstallStatus.PENDING, InstallStatus.DOWNLOADING -> DOWNLOADING
            InstallStatus.DOWNLOADED -> DOWNLOADED
            InstallStatus.INSTALLING -> INSTALLING
            InstallStatus.INSTALLED -> INSTALLED
            InstallStatus.FAILED -> FAILED
            InstallStatus.CANCELED -> CANCELED
            else -> NOT_AVAILABLE
        },
        "downloadedBytes" to state.bytesDownloaded(),
        "totalBytes" to state.totalBytesToDownload(),
    )

    private fun status(value: String): Map<String, Any?> = mapOf("status" to value)

    fun dispose() {
        if (listenerRegistered) {
            manager?.unregisterListener(this)
            listenerRegistered = false
        }
        flowResult?.success(status(CANCELED))
        flowResult = null
        channel?.setMethodCallHandler(null)
        channel = null
        activity = null
    }

    companion object {
        const val CHANNEL = "voratube/play_update_v1"
        const val PRODUCTION_PACKAGE = "com.piyushbaniya.vora_tube"
        const val PLAY_STORE_PACKAGE = "com.android.vending"
        const val REQUEST_CODE = 4243

        const val UNSUPPORTED = "unsupported"
        const val NOT_AVAILABLE = "notAvailable"
        const val AVAILABLE = "available"
        const val DOWNLOADING = "downloading"
        const val DOWNLOADED = "downloaded"
        const val INSTALLING = "installing"
        const val INSTALLED = "installed"
        const val FAILED = "failed"
        const val CANCELED = "canceled"
    }
}

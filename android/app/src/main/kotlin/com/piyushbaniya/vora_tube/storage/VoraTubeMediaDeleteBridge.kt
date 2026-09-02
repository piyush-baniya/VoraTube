package com.piyushbaniya.vora_tube.storage

import android.app.Activity
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Handles deletion of MediaStore media items with proper Android user-consent
 * flow on API 30+.
 *
 * On Android 11+ scoped storage, direct [ContentResolver.delete] on media
 * created by another app throws [SecurityException].  The correct API is
 * [MediaStore.createDeleteRequest], which produces a [PendingIntent] the
 * system presents as a confirmation dialog.
 *
 * The flow:
 * 1. Dart calls `deleteMediaFile` with the content-URI string.
 * 2. On API < 30, the item is deleted directly via [ContentResolver.delete].
 *    The result is returned synchronously.
 * 3. On API 30+, a [MediaStore.createDeleteRequest] [PendingIntent] is
 *    launched via [Activity.startIntentSenderForResult].  The Dart call
 *    blocks until the system dialog completes.
 * 4. [onActivityResult] is forwarded from [MainActivity] to
 *    [handleActivityResult], which resolves the pending [MethodChannel.Result].
 */
class VoraTubeMediaDeleteBridge(private val appContext: Context) {

    private var pendingResult: MethodChannel.Result? = null
    private var activity: Activity? = null

    fun setActivity(a: Activity?) {
        activity = a
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "deleteMediaFile" -> {
                    val uriStr = call.argument<String>("contentUri")
                    if (uriStr.isNullOrBlank()) {
                        result.error("missing_uri", "contentUri is required", null)
                        return@setMethodCallHandler
                    }
                    handleDelete(uriStr, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun handleDelete(contentUriString: String, result: MethodChannel.Result) {
        val uri = Uri.parse(contentUriString)

        // Pre-API-30: direct delete is allowed for all MediaStore items the app
        // can see.  (The app already verified file existence in Dart.)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            try {
                val deleted = appContext.contentResolver.delete(uri, null, null)
                if (deleted > 0) {
                    result.success(mapOf("deleted" to true))
                } else {
                    result.success(mapOf("deleted" to false, "reason" to "uri_not_found"))
                }
            } catch (e: Exception) {
                result.success(mapOf("deleted" to false, "reason" to (e.message ?: "unknown")))
            }
            return
        }

        // API 30+: try direct delete first (works when the app owns the row,
        // e.g. ringtones created by VoraTube itself).
        try {
            val deleted = appContext.contentResolver.delete(uri, null, null)
            if (deleted > 0) {
                result.success(mapOf("deleted" to true))
                return
            }
        } catch (_: SecurityException) {
            // Expected when the file was created by another app — fall through
            // to the user-consent request below.
        } catch (_: Exception) {
            // Other failures (stale URI, etc.) fall through too.
        }

        // Direct delete did not work — ask the system for user consent.
        val act = activity
        if (act == null) {
            result.error("no_activity", "Activity is unavailable", null)
            return
        }
        if (pendingResult != null) {
            result.error("busy", "Another delete request is in progress", null)
            return
        }

        try {
            val request = MediaStore.createDeleteRequest(
                act.contentResolver,
                listOf(uri),
            )
            pendingResult = result
            act.startIntentSenderForResult(
                request.intentSender,
                REQUEST_CODE_DELETE,
                null, 0, 0, 0,
            )
        } catch (e: Exception) {
            pendingResult = null
            result.error(
                "delete_request_failed",
                e.message ?: "could not create delete request",
                null,
            )
        }
    }

    /**
     * Called from [MainActivity.onActivityResult].
     *
     * If the user confirmed, the system performs the actual deletion — we
     * simply report success.  If the user cancelled, we report cancellation
     * (not an error) so Dart can treat it as a normal cancel.
     */
    fun handleActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_CODE_DELETE) return false
        val result = pendingResult ?: return false
        pendingResult = null
        if (resultCode == Activity.RESULT_OK) {
            result.success(mapOf("deleted" to true))
        } else {
            // User cancelled the system dialog — this is not an error.
            result.success(mapOf("deleted" to false, "cancelled" to true))
        }
        return true
    }

    /** Drop any in-flight request when the Activity is destroyed. */
    fun dispose() {
        pendingResult?.error("activity_destroyed", "Activity was destroyed", null)
        pendingResult = null
        activity = null
    }

    companion object {
        const val CHANNEL = "voratube/media_delete_v1"
        const val REQUEST_CODE_DELETE = 19_283
    }
}

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
 *
 * Robustness notes (the consent flow itself can silently lose its result on
 * some devices/OEMs, which previously left the channel wedged and every later
 * attempt failing with "busy"):
 *  * A new delete request pre-empts a stale in-flight one instead of failing.
 *  * RESULT_OK is not trusted blindly: the target row is verified to be gone
 *    before reporting success, so a consent dialog that "succeeds" without
 *    actually deleting the file no longer deletes the library row.
 *  * When the activity returns to the foreground while a request is still in
 *    flight, the dialog's result was lost — the bridge reconciles by checking
 *    whether the row actually vanished.
 */
class VoraTubeMediaDeleteBridge(private val appContext: Context) {

    private var pendingResult: MethodChannel.Result? = null
    private var pendingUri: Uri? = null
    private var activity: Activity? = null

    fun setActivity(a: Activity?) {
        activity = a
        // If the activity regains the foreground while a request is still in
        // flight, onActivityResult was lost (a device/OEM where the system
        // consent dialog closes without delivering the result). Reconcile the
        // pending call against the actual MediaStore state so it can never
        // wedge a later request.
        if (a != null && pendingResult != null) {
            resolveLostResult()
        }
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

        // Pre-empt any stale in-flight request (a previous consent dialog whose
        // result was lost would otherwise wedge every later call with "busy").
        val stale = pendingResult
        if (stale != null) {
            stale.success(mapOf("deleted" to false, "cancelled" to true))
        }

        try {
            val request = MediaStore.createDeleteRequest(
                act.contentResolver,
                listOf(uri),
            )
            pendingResult = result
            pendingUri = uri
            act.startIntentSenderForResult(
                request.intentSender,
                REQUEST_CODE_DELETE,
                null, 0, 0, 0,
            )
        } catch (e: Exception) {
            pendingResult = null
            pendingUri = null
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
     * RESULT_OK means the user granted consent — it does *not* guarantee the
     * row is actually gone on every device. The row is verified afterwards;
     * if it is still present, a final direct delete is attempted and only a
     * genuinely-deleted item is reported as success. A cancel is reported as
     * cancellation (not an error) so Dart treats it as a normal cancel.
     */
    fun handleActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_CODE_DELETE) return false
        val result = pendingResult ?: return false
        val uri = pendingUri ?: return false
        pendingResult = null
        pendingUri = null
        if (resultCode == Activity.RESULT_OK) {
            resolveAfterUserConsent(uri, result)
        } else {
            // User cancelled the system dialog — this is not an error.
            result.success(mapOf("deleted" to false, "cancelled" to true))
        }
        return true
    }

    /** A device where the consent dialog's result got lost: reconcile instead. */
    private fun resolveLostResult() {
        val result = pendingResult ?: return
        val uri = pendingUri
        pendingResult = null
        pendingUri = null
        if (uri != null && !rowExists(uri)) {
            // The file is gone, so the deletion effectively happened.
            result.success(mapOf("deleted" to true))
        } else {
            // Row still present: no deletion happened. Treat as a cancel so the
            // user's library is left untouched and they can try again cleanly.
            result.success(mapOf("deleted" to false, "cancelled" to true))
        }
    }

    private fun resolveAfterUserConsent(uri: Uri, result: MethodChannel.Result) {
        if (!rowExists(uri)) {
            result.success(mapOf("deleted" to true))
            return
        }
        // The consent dialog "succeeded" but the row is still there — attempt
        // one direct delete before giving up.
        try {
            val deleted = appContext.contentResolver.delete(uri, null, null)
            if (deleted > 0) {
                result.success(mapOf("deleted" to true))
                return
            }
        } catch (_: Exception) {
            // Ignore: we fall through to reporting still-absent deletion.
        }
        result.success(mapOf("deleted" to false, "reason" to "still_present"))
    }

    private fun rowExists(uri: Uri): Boolean {
        return try {
            val cursor = appContext.contentResolver.query(
                uri,
                arrayOf(MediaStore.MediaColumns._ID),
                null,
                null,
                null,
            )
            if (cursor == null) {
                // Cannot inspect the row — be conservative and assume it still
                // exists so we never report a deletion we cannot confirm.
                true
            } else {
                cursor.use { c -> c.moveToFirst() }
            }
        } catch (_: Exception) {
            // Same conservative default.
            true
        }
    }

    /** Drop any in-flight request when the Activity is destroyed. */
    fun dispose() {
        pendingResult?.error("activity_destroyed", "Activity was destroyed", null)
        pendingResult = null
        pendingUri = null
        activity = null
    }

    companion object {
        const val CHANNEL = "voratube/media_delete_v1"
        const val REQUEST_CODE_DELETE = 19_283
    }
}
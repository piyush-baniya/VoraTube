package com.piyushbaniya.vora_tube.storage

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class VoraTubeBackupStorageBridge(context: Context) {
    private val resolver = context.applicationContext.contentResolver
    private var activity: Activity? = null
    private var pending: MethodChannel.Result? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null

    fun setActivity(value: Activity?) { activity = value }
    fun dispose() {
        channel?.setMethodCallHandler(null)
        pending?.error("closed", "Storage picker closed", null)
        pending = null
        executor.shutdown()
    }

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "voratube/backup_storage_v1")
        channel!!.setMethodCallHandler { call, result ->
            if (call.method == "pickDirectory" || call.method == "pickFile") {
                val owner = activity
                if (owner == null || pending != null) {
                    result.error("busy", "Storage picker unavailable", null)
                } else {
                    val directory = call.method == "pickDirectory"
                    val intent = Intent(if (directory) Intent.ACTION_OPEN_DOCUMENT_TREE else Intent.ACTION_OPEN_DOCUMENT)
                    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    if (directory) intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    else { intent.type = "*/*"; intent.addCategory(Intent.CATEGORY_OPENABLE) }
                    intent.putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                    pending = result
                    try { owner.startActivityForResult(intent, if (directory) 7401 else 7402) }
                    catch (e: Exception) { pending = null; result.error("picker", e.message, null) }
                }
            } else {
                executor.execute {
                    try {
                        val value: Any? = when (call.method) {
                            "writeFile" -> {
                                val tree = Uri.parse(requireNotNull(call.argument<String>("dirUri")))
                                val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
                                val uri = requireNotNull(DocumentsContract.createDocument(resolver, parent,
                                    "application/octet-stream", requireNotNull(call.argument<String>("fileName"))))
                                val bytes = requireNotNull(call.argument<ByteArray>("bytes"))
                                requireNotNull(resolver.openOutputStream(uri, "w")).use { it.write(bytes); it.flush() }
                                uri.toString()
                            }
                            "readFile" -> {
                                val uri = Uri.parse(requireNotNull(call.argument<String>("fileUri")))
                                requireNotNull(resolver.openInputStream(uri)).use { stream ->
                                    val out = java.io.ByteArrayOutputStream()
                                    val buffer = ByteArray(65536)
                                    while (true) {
                                        val count = stream.read(buffer)
                                        if (count < 0) break
                                        require(out.size() + count <= 64 * 1024 * 1024) { "Backup exceeds 64 MB" }
                                        out.write(buffer, 0, count)
                                    }
                                    out.toByteArray()
                                }
                            }
                            "displayName" -> {
                                val input = Uri.parse(requireNotNull(call.argument<String>("uri")))
                                val uri = if (DocumentsContract.isTreeUri(input)) DocumentsContract.buildDocumentUriUsingTree(input, DocumentsContract.getTreeDocumentId(input)) else input
                                resolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
                                    if (it.moveToFirst()) it.getString(0) else null
                                }
                            }
                            "hasPermission" -> {
                                val uri = Uri.parse(requireNotNull(call.argument<String>("dirUri")))
                                resolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission && it.isWritePermission }
                            }
                            else -> throw IllegalArgumentException("Unknown backup operation")
                        }
                        main.post { result.success(value) }
                    } catch (e: Exception) {
                        main.post { result.error("storage", e.message ?: "Storage unavailable", null) }
                    }
                }
            }
        }
    }

    fun handleActivityResult(request: Int, result: Int, data: Intent?): Boolean {
        if (request != 7401 && request != 7402) return false
        val callback = pending ?: return true
        pending = null
        val uri = data?.data
        if (result != Activity.RESULT_OK || uri == null) { callback.success(null); return true }
        try {
            if (request == 7401) {
                val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                resolver.takePersistableUriPermission(uri, flags)
                require(resolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission && it.isWritePermission })
            }
            callback.success(uri.toString())
        } catch (e: Exception) { callback.error("permission", "Unable to retain folder access", null) }
        return true
    }
}


package com.ornobaadi.twofold

import android.Manifest
import android.app.Activity
import android.app.DownloadManager
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import kotlin.concurrent.thread

private const val PICK_DOCS = 4201
private const val PICK_FOLDER = 4202

class MainActivity : AudioServiceActivity() {
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "twofold/permissions").setMethodCallHandler { call, result ->
            if (call.method != "requestNotifications") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            // Android 13+: without this the media notification never shows.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4101)
            }
            result.success(null)
        }
        MethodChannel(messenger, "twofold/downloads").setMethodCallHandler { call, result ->
            when (call.method) {
                "enqueue" -> background(result) {
                    enqueue(
                        call.argument<String>("url")!!,
                        call.argument<String>("path")!!,
                        call.argument<String>("title")!!,
                        call.argument<String>("userAgent")!!,
                        call.argument<Boolean>("wifiOnly") == true,
                    )
                }
                "status" -> background(result) {
                    status(call.argument<List<Number>>("ids")!!.map { it.toLong() })
                }
                "remove" -> background(result) {
                    val ids = call.argument<List<Number>>("ids")!!.map { it.toLong() }
                    if (ids.isNotEmpty()) downloads().remove(*ids.toLongArray())
                    null
                }
                "folder" -> result.success(audioDir().absolutePath)
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, "twofold/files").setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDocuments" -> pickDocuments(
                    call.argument<List<String>>("mimes")!!,
                    call.argument<Boolean>("multiple")!!,
                    result,
                )
                "pickFolder" -> pickFolder(result)
                "keepScreenOn" -> {
                    if (call.argument<Boolean>("on") == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                "inCall" -> result.success(
                    (getSystemService(AUDIO_SERVICE) as AudioManager).mode != AudioManager.MODE_NORMAL,
                )
                "copy" -> background(result) {
                    contentResolver.openInputStream(Uri.parse(call.argument<String>("uri")!!))!!.use { from ->
                        File(call.argument<String>("dest")!!).outputStream().use { from.copyTo(it) }
                    }
                    null
                }
                "read" -> background(result) {
                    readRange(
                        Uri.parse(call.argument<String>("uri")!!),
                        call.argument<Number>("offset")!!.toLong(),
                        call.argument<Number>("length")!!.toInt(),
                    )
                }
                "size" -> background(result) {
                    contentResolver.openAssetFileDescriptor(
                        Uri.parse(call.argument<String>("uri")!!), "r",
                    )!!.use { it.length }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        thread {
            try {
                val value = work()
                runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                runOnUiThread { result.error("io", e.message, null) }
            }
        }
    }

    private fun readRange(uri: Uri, offset: Long, length: Int): ByteArray {
        contentResolver.openFileDescriptor(uri, "r")!!.use { pfd ->
            FileInputStream(pfd.fileDescriptor).channel.use { channel ->
                val buffer = ByteBuffer.allocate(length)
                channel.position(offset)
                while (buffer.hasRemaining()) {
                    if (channel.read(buffer) < 0) break
                }
                return buffer.array().copyOf(buffer.position())
            }
        }
    }

    private fun pickDocuments(
        mimes: List<String>,
        multiple: Boolean,
        result: MethodChannel.Result,
    ) {
        pending?.success(emptyList<Map<String, Any?>>())
        pending = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = if (mimes.size == 1) mimes[0] else "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, mimes.toTypedArray())
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple)
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        startActivityForResult(intent, PICK_DOCS)
    }

    private fun pickFolder(result: MethodChannel.Result) {
        pending?.success(emptyList<Map<String, Any?>>())
        pending = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        startActivityForResult(intent, PICK_FOLDER)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_DOCS && requestCode != PICK_FOLDER) return
        val result = pending ?: return
        pending = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        background(result) {
            if (requestCode == PICK_DOCS) describePicked(data) else listFolder(data.data!!)
        }
    }

    private fun keep(uri: Uri) {
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: SecurityException) {
            // This provider doesn't offer lasting access; the file works for now.
        }
    }

    private fun describePicked(data: Intent): List<Map<String, Any?>> {
        val uris = mutableListOf<Uri>()
        data.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
        }
        if (uris.isEmpty()) data.data?.let { uris.add(it) }
        return uris.map { uri ->
            keep(uri)
            var name = uri.lastPathSegment ?: "file"
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst() && !it.isNull(0)) name = it.getString(0)
            }
            mapOf("uri" to uri.toString(), "name" to name)
        }
    }

    /** Files in a folder and its subfolders; Dart keeps the audio ones. */
    private fun listFolder(tree: Uri): List<Map<String, Any?>> {
        keep(tree)
        val out = mutableListOf<Map<String, Any?>>()
        fun walk(docId: String, prefix: String) {
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, docId)
            val columns = arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
            contentResolver.query(children, columns, null, null, null)?.use {
                while (it.moveToNext()) {
                    val id = it.getString(0)
                    val name = it.getString(1) ?: continue
                    if (it.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                        walk(id, "$prefix$name/")
                    } else {
                        out.add(
                            mapOf(
                                "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, id).toString(),
                                "name" to name,
                                "sortKey" to "$prefix$name",
                            ),
                        )
                    }
                }
            }
        }
        walk(DocumentsContract.getTreeDocumentId(tree), "")
        return out
    }

    // --- audiobook downloads (Android's DownloadManager) ---

    private fun downloads() = getSystemService(DOWNLOAD_SERVICE) as DownloadManager

    /** App-private, needs no storage permission, removed with the app. */
    private fun audioDir(): File {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Environment.DIRECTORY_AUDIOBOOKS
        } else {
            Environment.DIRECTORY_MUSIC
        }
        return File(getExternalFilesDir(type) ?: filesDir, "twofold")
    }

    /** Saves [url] to [path] under audioDir(); returns the download id. */
    private fun enqueue(url: String, path: String, title: String, agent: String, wifiOnly: Boolean): Long {
        val uri = Uri.parse(url)
        // Only the archive.org files LibriVox points to, and only over https.
        require(uri.scheme == "https" && (uri.host == "archive.org" || uri.host!!.endsWith(".archive.org"))) {
            "not an allowed address"
        }
        val dest = File(audioDir(), path)
        dest.parentFile?.mkdirs()
        if (dest.exists()) dest.delete()
        val request = DownloadManager.Request(uri)
            .setTitle(title)
            .setDescription("TwoFold audiobook")
            .addRequestHeader("User-Agent", agent)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationUri(Uri.fromFile(dest))
            .setAllowedOverRoaming(false)
        if (wifiOnly) {
            request.setAllowedNetworkTypes(DownloadManager.Request.NETWORK_WIFI)
            request.setAllowedOverMetered(false)
        }
        return downloads().enqueue(request)
    }

    /** For each id: state (pending, running, paused, done, failed, gone), bytes, total, file. */
    private fun status(ids: List<Long>): List<Map<String, Any?>> {
        if (ids.isEmpty()) return emptyList()
        val found = mutableMapOf<Long, Map<String, Any?>>()
        downloads().query(DownloadManager.Query().setFilterById(*ids.toLongArray())).use { c ->
            while (c.moveToNext()) {
                val id = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_ID))
                val state = when (c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))) {
                    DownloadManager.STATUS_PENDING -> "pending"
                    DownloadManager.STATUS_RUNNING -> "running"
                    DownloadManager.STATUS_PAUSED -> "paused"
                    DownloadManager.STATUS_SUCCESSFUL -> "done"
                    else -> "failed"
                }
                val local = c.getString(c.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
                found[id] = mapOf(
                    "id" to id,
                    "state" to state,
                    "bytes" to c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)),
                    "total" to c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)),
                    "file" to local?.let { Uri.parse(it).path },
                )
            }
        }
        return ids.map { found[it] ?: mapOf("id" to it, "state" to "gone") }
    }
}

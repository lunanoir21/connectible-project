package io.connectible.mobile.files

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

/**
 * "Save to..." bridge (T-X6): streams a received file out of app-private
 * storage into a user-chosen SAF document without ever buffering the
 * whole file in memory.
 *
 * Dart calls `saveTo(sourcePath, fileName)` on `connectible/savefile`;
 * this launches ACTION_CREATE_DOCUMENT and, once the user picks a
 * destination, copies the source file into the returned content URI with
 * a fixed 64 KiB buffer on a background thread. The previous
 * implementation (Dart `readAsBytes` + file_picker's `bytes:` parameter)
 * held the entire file in the Dart heap -- a GB-scale video/APK (this is
 * a LAN file-transfer app) risked OOM; here no file byte ever crosses
 * the platform channel at all.
 *
 * Resolution contract: `true` = saved, `false` = user canceled the
 * picker, error = I/O failure. One save at a time; a second call while
 * one is pending resolves with a "busy" error.
 */
class SaveFilePlugin(private val activity: Activity) {
    companion object {
        private const val TAG = "SaveFilePlugin"
        private const val CHANNEL = "connectible/savefile"

        // Unique within this app (Flutter plugins use small codes; this is
        // deliberately high) and within the 16-bit range Android requires.
        private const val REQUEST_CODE = 0x5AF3
        private const val BUFFER_SIZE = 64 * 1024
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingResult: MethodChannel.Result? = null
    private var pendingSourcePath: String? = null

    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveTo" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        val fileName = call.argument<String>("fileName")
                        if (sourcePath == null || fileName == null) {
                            result.error(
                                "bad_args",
                                "sourcePath and fileName are required",
                                null,
                            )
                        } else {
                            saveTo(sourcePath, fileName, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveTo(sourcePath: String, fileName: String, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "another save is already in progress", null)
            return
        }
        if (!File(sourcePath).isFile) {
            result.error("missing_source", "source file does not exist", null)
            return
        }
        pendingResult = result
        pendingSourcePath = sourcePath
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        try {
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (e: Throwable) {
            pendingResult = null
            pendingSourcePath = null
            result.error(
                "no_picker",
                "could not open the system document picker: ${e.message}",
                null,
            )
        }
    }

    /** Returns true when the result belonged to this plugin's request. */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pendingResult ?: return true
        val sourcePath = pendingSourcePath
        pendingResult = null
        pendingSourcePath = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || sourcePath == null) {
            result.success(false) // user backed out of the picker
            return true
        }
        copyToUri(sourcePath, uri, result)
        return true
    }

    private fun copyToUri(sourcePath: String, uri: Uri, result: MethodChannel.Result) {
        // The copy is plain blocking I/O on a dedicated thread: fixed-size
        // buffer, constant memory regardless of file size, and the UI
        // thread never blocks (a GB copy on it would ANR).
        Thread({
            try {
                FileInputStream(File(sourcePath)).use { input ->
                    val output = activity.contentResolver.openOutputStream(uri, "w")
                        ?: throw IllegalStateException("destination stream unavailable")
                    output.use { out ->
                        val buffer = ByteArray(BUFFER_SIZE)
                        while (true) {
                            val n = input.read(buffer)
                            if (n < 0) break
                            out.write(buffer, 0, n)
                        }
                        out.flush()
                    }
                }
                mainHandler.post { result.success(true) }
            } catch (e: Throwable) {
                Log.w(TAG, "save-to copy failed: ${e.message}")
                // Best-effort: drop the half-written destination document so
                // the user is not left with a silently truncated file.
                try {
                    DocumentsContract.deleteDocument(activity.contentResolver, uri)
                } catch (_: Throwable) {
                }
                mainHandler.post { result.error("copy_failed", e.message, null) }
            }
        }, "ConnectibleSaveTo").start()
    }
}

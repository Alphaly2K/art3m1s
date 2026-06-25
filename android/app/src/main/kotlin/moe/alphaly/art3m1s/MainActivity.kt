package moe.alphaly.art3m1s

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {

    companion object {
        private const val REQ_PICK_DIRECTORY = 1001

        init {
            System.loadLibrary("art3m1s_jni")
        }

        @JvmStatic
        private external fun nativeGetVmPtr(): Long

        @JvmStatic
        private external fun nativeRegisterContext(ctx: Any): Long
    }

    private var pendingImportResult: Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "moe.alphaly.art3m1s/native_ptrs"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAndroidContextPtrs" -> {
                    val vmPtr = nativeGetVmPtr()
                    val ctxPtr = nativeRegisterContext(applicationContext)
                    result.success(mapOf("vmPtr" to vmPtr, "contextPtr" to ctxPtr))
                }
                "pickDirectoryAndCopy" -> {
                    if (pendingImportResult != null) {
                        result.error("ALREADY_PENDING", "上一次操作还未完成", null)
                        return@setMethodCallHandler
                    }
                    pendingImportResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivityForResult(intent, REQ_PICK_DIRECTORY)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_PICK_DIRECTORY) {
            val result = pendingImportResult
            pendingImportResult = null
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                result?.error("PICK_CANCELLED", "用户取消了目录选择", null)
                return
            }
            try {
                val sandboxPath = copyTreeToSandbox(data!!.data!!)
                result?.success(sandboxPath)
            } catch (e: Exception) {
                result?.error("COPY_FAILED", e.message, null)
            }
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun copyTreeToSandbox(treeUri: Uri): String {
        try {
            contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: Exception) { }

        val rootDoc = DocumentFile.fromTreeUri(this, treeUri)
            ?: throw IllegalStateException("无法读取所选目录")

        val incomingDir = File(filesDir, "games/incoming/${System.currentTimeMillis()}")
        incomingDir.mkdirs()

        val count = copyDocumentDir(rootDoc, incomingDir)
        if (count == 0) {
            incomingDir.deleteRecursively()
            throw IllegalStateException("所选目录为空或无法读取")
        }
        return incomingDir.absolutePath
    }

    private fun copyDocumentDir(docDir: DocumentFile, targetDir: File): Int {
        var count = 0
        for (doc in docDir.listFiles()) {
            val name = doc.name ?: continue
            if (doc.isDirectory) {
                val subDir = File(targetDir, name)
                subDir.mkdirs()
                count += copyDocumentDir(doc, subDir)
            } else if (doc.isFile) {
                contentResolver.openInputStream(doc.uri)?.use { input ->
                    FileOutputStream(File(targetDir, name)).use { output ->
                        input.copyTo(output)
                    }
                    count++
                }
            }
        }
        return count
    }
}

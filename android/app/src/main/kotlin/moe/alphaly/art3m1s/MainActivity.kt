package moe.alphaly.art3m1s

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import android.provider.DocumentsContract
import android.view.Surface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
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

        @JvmStatic
        private external fun nativeAcquireSurfaceWindow(surface: Surface): Long

        @JvmStatic
        private external fun nativeReleaseSurfaceWindow(window: Long)
    }

    private var pendingImportResult: Result? = null
    private lateinit var nativeChannel: MethodChannel
    private var lastImportProgressAt = 0L
    private var sharedTextureProducer: TextureRegistry.SurfaceProducer? = null
    private var sharedTextureWindow: Long = 0
    private lateinit var sharedTextureChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        nativeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "moe.alphaly.art3m1s/native_ptrs"
        )
        nativeChannel.setMethodCallHandler { call, result ->
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
                        addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                    }
                    startActivityForResult(intent, REQ_PICK_DIRECTORY)
                }
                else -> result.notImplemented()
            }
        }

        sharedTextureChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "moe.alphaly.art3m1s/shared_texture"
        )
        sharedTextureChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "create" -> {
                    val width = call.argument<Int>("width") ?: 0
                    val height = call.argument<Int>("height") ?: 0
                    if (width <= 0 || height <= 0) {
                        result.error("INVALID_SIZE", "Invalid shared texture size", null)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(createSharedTexture(flutterEngine, width, height))
                    } catch (error: Exception) {
                        result.error("CREATE_FAILED", error.message, null)
                    }
                }
                "frameAvailable" -> result.success(null)
                "release" -> {
                    releaseSharedTexture()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun createSharedTexture(
        flutterEngine: FlutterEngine,
        width: Int,
        height: Int
    ): Map<String, Long> {
        releaseSharedTexture()
        val producer = flutterEngine.renderer.createSurfaceProducer(
            TextureRegistry.SurfaceLifecycle.resetInBackground
        )
        producer.setSize(width, height)
        sharedTextureProducer = producer
        producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
            override fun onSurfaceCleanup() {
                sharedTextureChannel.invokeMethod("surfaceCleanup", null)
            }

            override fun onSurfaceAvailable() {
                val descriptor = acquireSharedTextureWindow() ?: return
                sharedTextureChannel.invokeMethod("surfaceAvailable", descriptor)
            }
        })
        return acquireSharedTextureWindow()
            ?: throw IllegalStateException("Unable to acquire Flutter texture surface")
    }

    private fun acquireSharedTextureWindow(): Map<String, Long>? {
        val producer = sharedTextureProducer ?: return null
        val window = nativeAcquireSurfaceWindow(producer.surface)
        if (window == 0L) return null
        val previous = sharedTextureWindow
        sharedTextureWindow = window
        if (previous != 0L) nativeReleaseSurfaceWindow(previous)
        return mapOf(
            "textureId" to producer.id(),
            "kind" to 1L,
            "handle" to window
        )
    }

    private fun releaseSharedTexture() {
        sharedTextureProducer?.setCallback(null)
        if (sharedTextureWindow != 0L) {
            nativeReleaseSurfaceWindow(sharedTextureWindow)
            sharedTextureWindow = 0
        }
        sharedTextureProducer?.release()
        sharedTextureProducer = null
    }

    override fun onDestroy() {
        releaseSharedTexture()
        super.onDestroy()
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
            val treeUri = data.data!!
            Thread({
                try {
                    val sandboxPath = copyTreeToSandbox(treeUri)
                    runOnUiThread {
                        if (!isDestroyed) result?.success(sandboxPath)
                    }
                } catch (e: Exception) {
                    runOnUiThread {
                        if (!isDestroyed) result?.error("COPY_FAILED", e.message, null)
                    }
                }
            }, "art3m1s-import").start()
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

        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        val rootUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootId)
        val folderName = sanitizeImportedDirectoryName(queryDocumentName(rootUri))
        val incomingDir = File(filesDir, "games/incoming/${System.currentTimeMillis()}/$folderName")
        incomingDir.mkdirs()

        lastImportProgressAt = 0L
        val stats = ImportStats()
        try {
            reportImportProgress(stats, folderName, force = true)
            copyDocumentDir(treeUri, rootId, incomingDir, stats)
            reportImportProgress(stats, "", force = true)
            if (stats.files == 0) {
                throw IllegalStateException("所选目录为空或无法读取")
            }
        } catch (error: Exception) {
            incomingDir.deleteRecursively()
            throw error
        }
        return incomingDir.absolutePath
    }

    private fun sanitizeImportedDirectoryName(raw: String?): String {
        val name = raw.orEmpty().trim()
            .replace(Regex("[\\/]+"), "_")
            .trim('.', ' ')
        return if (name.isEmpty() || name == "." || name == "..") "game" else name
    }

    private data class ImportStats(var files: Int = 0, var bytes: Long = 0)
    private data class ImportDocument(
        val id: String,
        val name: String,
        val mimeType: String?
    )

    private fun queryDocumentName(documentUri: Uri): String? {
        val projection = arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
        return try {
            contentResolver.query(documentUri, projection, null, null, null)?.use { cursor ->
                if (!cursor.moveToFirst()) null else cursor.getString(0)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun copyDocumentDir(
        treeUri: Uri,
        parentDocumentId: String,
        targetDir: File,
        stats: ImportStats
    ) {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            parentDocumentId
        )
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE
        )
        val documents = mutableListOf<ImportDocument>()
        try {
            contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                val idColumn = cursor.getColumnIndexOrThrow(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID
                )
                val nameColumn = cursor.getColumnIndexOrThrow(
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME
                )
                val mimeColumn = cursor.getColumnIndexOrThrow(
                    DocumentsContract.Document.COLUMN_MIME_TYPE
                )
                while (cursor.moveToNext()) {
                    val id = cursor.getString(idColumn) ?: continue
                    documents += ImportDocument(
                        id = id,
                        name = sanitizeDocumentName(cursor.getString(nameColumn)),
                        mimeType = cursor.getString(mimeColumn)
                    )
                }
            }
        } catch (error: Exception) {
            throw IllegalStateException("无法读取目录: ${error.message}", error)
        }
        for (document in documents) {
            if (document.mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                val subDir = File(targetDir, document.name)
                if (!subDir.exists() && !subDir.mkdirs()) {
                    throw IllegalStateException("无法创建导入目录: ${document.name}")
                }
                copyDocumentDir(treeUri, document.id, subDir, stats)
            } else {
                val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                    treeUri,
                    document.id
                )
                copyDocumentFile(
                    documentUri,
                    File(targetDir, document.name),
                    document.name,
                    stats
                )
            }
        }
    }

    private fun copyDocumentFile(
        documentUri: Uri,
        target: File,
        displayName: String,
        stats: ImportStats
    ) {
        val input = contentResolver.openInputStream(documentUri)
            ?: throw IllegalStateException("无法读取文件: $displayName")
        input.use { source ->
            FileOutputStream(target).use { output ->
                val buffer = ByteArray(1024 * 1024)
                while (true) {
                    val read = source.read(buffer)
                    if (read < 0) break
                    if (read == 0) continue
                    output.write(buffer, 0, read)
                    stats.bytes += read
                    reportImportProgress(stats, displayName)
                }
            }
        }
        stats.files++
        reportImportProgress(stats, displayName)
    }

    private fun sanitizeDocumentName(raw: String?): String {
        val name = raw.orEmpty().replace(Regex("[\\/]+"), "_").trim()
        return if (name.isEmpty() || name == "." || name == "..") "unnamed" else name
    }

    private fun reportImportProgress(
        stats: ImportStats,
        currentName: String,
        force: Boolean = false
    ) {
        val now = SystemClock.elapsedRealtime()
        if (!force && now - lastImportProgressAt < 120) return
        lastImportProgressAt = now
        val payload = mapOf(
            "files" to stats.files,
            "bytes" to stats.bytes,
            "current" to currentName
        )
        runOnUiThread {
            if (!isDestroyed) nativeChannel.invokeMethod("importProgress", payload)
        }
    }
}

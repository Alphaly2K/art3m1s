package moe.alphaly.art3m1s

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.Settings
import android.view.Surface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry

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

    private var pendingPickResult: Result? = null
    private lateinit var nativeChannel: MethodChannel
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
                "hasAllFilesAccess" -> {
                    result.success(hasStorageAccess())
                }
                "requestAllFilesAccess" -> {
                    requestStorageAccess()
                    result.success(null)
                }
                "pickGameDirectory" -> {
                    if (pendingPickResult != null) {
                        result.error("ALREADY_PENDING", "上一次操作还未完成", null)
                        return@setMethodCallHandler
                    }
                    if (!hasStorageAccess()) {
                        // Dart 侧先弹说明,再调 requestAllFilesAccess 引导授权。
                        result.success(mapOf("status" to "needsAllFilesAccess"))
                        return@setMethodCallHandler
                    }
                    pendingPickResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
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

    // ── 存储访问:全文件访问(API 30+)或旧式 READ_EXTERNAL_STORAGE ──

    private fun hasStorageAccess(): Boolean {
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                Environment.isExternalStorageManager()
            // API 23-29:运行时权限;API < 23:安装时即授予。
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ->
                checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) ==
                    PackageManager.PERMISSION_GRANTED
            else -> true
        }
    }

    private fun requestStorageAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                startActivity(
                    Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                        data = Uri.parse("package:$packageName")
                    }
                )
            } catch (_: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            requestPermissions(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE), 0)
        }
    }

    // SAF tree URI("primary:Games/foo" 或 "<volumeUuid>:Games/foo")解析为
    // 真实文件系统路径;无法解析时返回 null,由 Dart 侧降级为手动输入。
    private fun resolveTreePath(treeUri: Uri): String? {
        val docId = try {
            DocumentsContract.getTreeDocumentId(treeUri)
        } catch (_: Exception) {
            return null
        }
        val split = docId.split(':', limit = 2)
        val volume = split.getOrNull(0)?.takeIf { it.isNotEmpty() } ?: return null
        val relative = split.getOrNull(1).orEmpty()
        val base = when {
            volume.equals("primary", ignoreCase = true) ->
                Environment.getExternalStorageDirectory().absolutePath
            // documents provider 的 home 卷路径不确定,交给手动输入兜底。
            volume.equals("home", ignoreCase = true) -> return null
            else -> "/storage/$volume"
        }
        val path = if (relative.isEmpty()) base else "$base/$relative"
        val dir = java.io.File(path)
        return if (dir.isDirectory) dir.absolutePath else null
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
            val result = pendingPickResult
            pendingPickResult = null
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                result?.error("PICK_CANCELLED", "用户取消了目录选择", null)
                return
            }
            val path = resolveTreePath(data.data!!)
            if (path == null) {
                result?.success(mapOf("status" to "unresolved"))
            } else {
                result?.success(mapOf("status" to "ok", "path" to path))
            }
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }
}

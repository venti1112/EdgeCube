package com.venti1112.edgecube

import android.annotation.SuppressLint
import android.app.ActivityManager
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size
import androidx.annotation.NonNull
import com.venti1112.edgecube.server.JreLayout
import com.venti1112.edgecube.server.RuntimeInstaller
import com.venti1112.edgecube.server.ServerProcessManager
import com.venti1112.edgecube.server.TunnelProcessManager
import com.venti1112.edgecube.shell.ShellCommandRunner
import com.venti1112.edgecube.shell.ShellProcessManager
import com.venti1112.edgecube.shell.ShellResolver
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStreamReader
import java.nio.charset.StandardCharsets
import kotlin.concurrent.thread

/**
 * 平台通道宿主：
 *  - storage：「管理全部文件」权限查询/申请。
 *  - power：电池优化白名单状态查询与申请。
 *  - server / server_events：服务端 JVM 进程的启动、停止、命令输入与日志/状态回传。
 */
class MainActivity : FlutterActivity() {
    private val storageChannel = "com.venti1112.edgecube/storage"
    private val photoChannel = "com.venti1112.edgecube/photos"
    private val powerChannel = "com.venti1112.edgecube/power"
    private val serverChannel = "com.venti1112.edgecube/server"
    private val serverEventChannel = "com.venti1112.edgecube/server_events"
    private val systemMonitorChannel = "com.venti1112.edgecube/system_monitor"
    private val tunnelChannel = "com.venti1112.edgecube/tunnel"
    private val tunnelEventChannel = "com.venti1112.edgecube/tunnel_events"
    private val forgeEventChannel = "com.venti1112.edgecube/forge_events"
    private val archiveEventChannel = "com.venti1112.edgecube/archive_events"
    private val shellChannel = "com.venti1112.edgecube/shell"
    private val shellEventChannel = "com.venti1112.edgecube/shell_events"
    private var pendingPhotoPermissionResult: MethodChannel.Result? = null
    private var pendingStoragePermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestPostNotifications()
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> return
        } ?: return

        // 检查文件名是否以 .ecpkg 结尾
        val fileName = getFileNameFromUri(uri)
        if (fileName == null) {
            sendEcpkgError("无法获取文件名")
            return
        }
        if (!fileName.lowercase().endsWith(".ecpkg")) {
            sendEcpkgError("不是有效的 .ecpkg 文件")
            return
        }

        // 获取可访问的文件路径
        val path = resolveFilePath(uri)
        if (path == null) {
            sendEcpkgError("无法读取文件，请检查文件访问权限")
            return
        }
        // Flutter engine 尚未就绪时暂存，configureFlutterEngine 中发送
        pendingEcpkgPath = path
        trySendPendingEcpkg()
    }

    private fun sendEcpkgError(message: String) {
        val channel = ecpkgChannel
        if (channel != null) {
            channel.invokeMethod("ecpkgError", message)
        } else {
            pendingEcpkgError = message
        }
    }

    private var pendingEcpkgError: String? = null

    private fun getFileNameFromUri(uri: Uri): String? {
        // 尝试从 URI 中获取文件名
        if (uri.scheme == "file") {
            return uri.lastPathSegment
        }
        // 对于 content:// URI，查询 DISPLAY_NAME
        if (uri.scheme == "content") {
            contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                    if (nameIndex >= 0) {
                        return cursor.getString(nameIndex)
                    }
                }
            }
        }
        return uri.lastPathSegment
    }

    private fun resolveFilePath(uri: Uri): String? {
        // 对于 file:// scheme，直接返回路径
        if (uri.scheme == "file") {
            val path = uri.path
            if (path != null && File(path).exists()) {
                return path
            }
        }
        // 对于 content:// scheme 或 file:// 无法直接访问时，复制到缓存
        return try {
            val fileName = getFileNameFromUri(uri) ?: "imported.ecpkg"
            val tempFile = File(cacheDir, fileName)
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(tempFile).use { output ->
                    input.copyTo(output)
                }
            }
            tempFile.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    private var pendingEcpkgPath: String? = null
    private var ecpkgChannel: MethodChannel? = null

    private fun trySendPendingEcpkg() {
        val channel = ecpkgChannel ?: return

        val error = pendingEcpkgError
        if (error != null) {
            pendingEcpkgError = null
            channel.invokeMethod("ecpkgError", error)
            return
        }

        val path = pendingEcpkgPath ?: return
        pendingEcpkgPath = null
        channel.invokeMethod("openEcpkg", path)
    }

    /** 请求通知权限（Android 13+）；授权后自动接着请求本地网络权限。 */
    private fun requestPostNotifications() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1001)
                return
            }
        }
        requestLocalNetworkPermission()
    }

    /** Android 17+ 需要 ACCESS_LOCAL_NETWORK 权限才能访问局域网（Minecraft 服务端、FTP、SSH、UPnP）。 */
    private fun requestLocalNetworkPermission() {
        if (Build.VERSION.SDK_INT >= 37) {
            if (checkSelfPermission(android.Manifest.permission.ACCESS_LOCAL_NETWORK)
                != PackageManager.PERMISSION_GRANTED
            ) {
                requestPermissions(arrayOf(android.Manifest.permission.ACCESS_LOCAL_NETWORK), 1004)
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            1001 -> {
                // 通知权限对话框关闭后，接着请求本地网络权限。
                requestLocalNetworkPermission()
            }
            1002 -> {
                pendingPhotoPermissionResult?.success(hasPhotoPermission())
                pendingPhotoPermissionResult = null
            }
            1003 -> {
                pendingStoragePermissionResult?.success(isGranted())
                pendingStoragePermissionResult = null
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val serverManager = ServerProcessManager.getInstance(applicationContext)
        val tunnelManager = TunnelProcessManager.getInstance(applicationContext)
        val shellManager = ShellProcessManager.getInstance(applicationContext)

        ecpkgChannel = MethodChannel(messenger, "com.venti1112.edgecube/ecpkg")
        trySendPendingEcpkg()

        MethodChannel(messenger, storageChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "isGranted" -> result.success(isGranted())
                "request" -> {
                    requestAccess(result)
                }
                "externalStorageRoot" ->
                    result.success(Environment.getExternalStorageDirectory()?.absolutePath)
                "getStorageStats" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("BAD_ARGS", "缺少 path", null)
                    } else {
                        try {
                            val stat = StatFs(path)
                            val total = stat.totalBytes
                            val available = stat.availableBytes
                            result.success(
                                mapOf(
                                    "totalBytes" to total,
                                    "availableBytes" to available,
                                ),
                            )
                        } catch (e: Exception) {
                            result.error("STAT_FAILED", e.message, null)
                        }
                    }
                }
                "getAppSize" -> {
                    try {
                        val pm = applicationContext.packageManager
                        val info = pm.getPackageInfo(packageName, 0)
                        val apkSize = File(info.applicationInfo!!.sourceDir).length()
                        var nativeLibSize = 0L
                        val nativeLibDir = File(info.applicationInfo!!.nativeLibraryDir)
                        if (nativeLibDir.exists()) {
                            nativeLibDir.walkTopDown().filter { it.isFile }
                                .forEach { nativeLibSize += it.length() }
                        }
                        result.success(
                            mapOf(
                                "apkSize" to apkSize,
                                "nativeLibSize" to nativeLibSize,
                                "totalSize" to (apkSize + nativeLibSize),
                            ),
                        )
                    } catch (e: Exception) {
                        result.error("APP_SIZE_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, photoChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "isGranted" -> result.success(hasPhotoPermission())
                "request" -> requestPhotoPermission(result)
                "list" -> {
                    thread {
                        try {
                            val photos = queryPhotos()
                            runOnUiThread { result.success(photos) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("PHOTO_LIST_FAILED", e.message, null) }
                        }
                    }
                }
                "bytes" -> {
                    val uri = call.argument<String>("uri")
                    val maxSize = call.argument<Int>("maxSize") ?: 512
                    if (uri == null) {
                        result.error("BAD_ARGS", "缺少 uri", null)
                    } else {
                        thread {
                            try {
                                val bytes = readPhotoBytes(uri, maxSize)
                                runOnUiThread { result.success(bytes) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("PHOTO_BYTES_FAILED", e.message, null) }
                            }
                        }
                    }
                }
                "originalBytes" -> {
                    val uri = call.argument<String>("uri")
                    if (uri == null) {
                        result.error("BAD_ARGS", "缺少 uri", null)
                    } else {
                        thread {
                            try {
                                val bytes = readOriginalBytes(uri)
                                runOnUiThread { result.success(bytes) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("PHOTO_ORIGINAL_FAILED", e.message, null) }
                            }
                        }
                    }
                }
                "copyToCache" -> {
                    val uri = call.argument<String>("uri")
                    val name = call.argument<String>("name")
                    if (uri == null) {
                        result.error("BAD_ARGS", "缺少 uri", null)
                    } else {
                        thread {
                            try {
                                val path = copyPhotoToCache(uri, name)
                                runOnUiThread { result.success(path) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("PHOTO_COPY_FAILED", e.message, null) }
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, powerChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" ->
                    result.success(isIgnoringBatteryOptimizations())
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, serverChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "availableVersions" ->
                    result.success(RuntimeInstaller.availableJreIds(applicationContext))

                "availablePhpRuntimes" ->
                    result.success(RuntimeInstaller.availablePhpIds(applicationContext))

                "isRuntimeReady" -> {
                    val runtimeId = call.argument<String>("runtimeId")
                    if (runtimeId == null) {
                        result.error("BAD_ARGS", "缺少 runtimeId", null)
                    } else {
                        result.success(RuntimeInstaller.isInstalled(applicationContext, runtimeId))
                    }
                }

                "isRunning" -> result.success(serverManager.isRunning)

                "activeInstanceId" -> result.success(serverManager.activeInstanceId)

                "start" -> {
                    val instanceId = call.argument<String>("instanceId")
                    val workingDir = call.argument<String>("workingDir")
                    val runtimeId = call.argument<String>("runtimeId")
                    val runtime = call.argument<String>("runtime") ?: "java"
                    val jvmArgs = call.argument<List<String>>("jvmArgs") ?: emptyList()
                    val programArgs = call.argument<List<String>>("programArgs") ?: emptyList()
                    if (instanceId == null || workingDir == null || runtimeId == null) {
                        result.error("BAD_ARGS", "缺少 instanceId/workingDir/runtimeId", null)
                    } else {
                        val instanceName = call.argument<String>("instanceName") ?: instanceId
                        // 含解压，放后台线程；完成后回主线程返回结果。
                        thread {
                            try {
                                serverManager.start(
                                    instanceId, instanceName, workingDir, runtimeId, runtime, jvmArgs, programArgs,
                                )
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("START_FAILED", e.message, null) }
                            }
                        }
                    }
                }

                "sendCommand" -> {
                    serverManager.sendCommand(call.argument<String>("line") ?: "")
                    result.success(null)
                }

                "writeInput" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes != null) serverManager.writeInput(bytes)
                    result.success(null)
                }

                "resize" -> {
                    val cols = call.argument<Int>("cols") ?: 0
                    val rows = call.argument<Int>("rows") ?: 0
                    val cellWidth = call.argument<Int>("cellWidth") ?: 0
                    val cellHeight = call.argument<Int>("cellHeight") ?: 0
                    serverManager.resize(rows, cols, cellWidth, cellHeight)
                    result.success(null)
                }

                "setEcho" -> {
                    val echo = call.argument<Boolean>("echo") ?: true
                    serverManager.setEcho(echo)
                    result.success(null)
                }

                "stop" -> {
                    serverManager.stop()
                    result.success(null)
                }

                "forceStop" -> {
                    serverManager.forceStop()
                    result.success(null)
                }

                "clearLog" -> {
                    serverManager.clearLog()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        // 系统监控通道：设备内存 + CPU 使用率 + 服务端进程内存 + 设备信息
        MethodChannel(messenger, systemMonitorChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSystemInfo" -> {
                    thread {
                        try {
                            val info = getSystemInfo(serverManager)
                            runOnUiThread { result.success(info) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("MONITOR_ERR", e.message, null) }
                        }
                    }
                }
                "getDeviceInfo" -> {
                    thread {
                        try {
                            val info = getDeviceInfo()
                            runOnUiThread { result.success(info) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("DEVICE_INFO_ERR", e.message, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Forge 安装事件通道
        var forgeEventSink: EventChannel.EventSink? = null
        EventChannel(messenger, forgeEventChannel).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    forgeEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    forgeEventSink = null
                }
            },
        )

        // Forge 安装通道：下载 installer 后在本地运行 java -jar installer.jar --installServer
        MethodChannel(messenger, "com.venti1112.edgecube/forge").setMethodCallHandler { call, result ->
            when (call.method) {
                "runInstaller" -> {
                    val installerJar = call.argument<String>("installerJar")
                    val workingDir = call.argument<String>("workingDir")
                    val javaVersion = call.argument<String>("javaVersion") ?: "jre21"
                    if (installerJar == null || workingDir == null) {
                        result.error("BAD_ARGS", "缺少 installerJar/workingDir", null)
                    } else {
                        thread {
                            try {
                                val exitCode = runForgeInstaller(
                                    installerJar, workingDir, javaVersion, forgeEventSink,
                                )
                                runOnUiThread { result.success(exitCode) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("INSTALL_FAILED", e.message, null) }
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 归档通道：zip/tar/tar.*/7z/rar 等格式统一在原生侧处理。
        var archiveEventSink: EventChannel.EventSink? = null
        EventChannel(messenger, archiveEventChannel).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    archiveEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    archiveEventSink = null
                }
            },
        )
        MethodChannel(messenger, "com.venti1112.edgecube/archive").setMethodCallHandler { call, result ->
            when (call.method) {
                "compress" -> {
                    val sourcePaths = call.argument<List<String>>("sourcePaths")
                    val archivePath = call.argument<String>("archivePath")
                    if (sourcePaths == null || archivePath == null) {
                        result.error("BAD_ARGS", "缺少 sourcePaths/archivePath", null)
                    } else {
                        thread {
                            try {
                                val count = com.venti1112.edgecube.files.ArchiveExtractor.compressToZip(
                                    sourcePaths, archivePath,
                                )
                                runOnUiThread { result.success(count) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("COMPRESS_FAILED", e.message, null) }
                            }
                        }
                    }
                }
                "extract" -> {
                    val archivePath = call.argument<String>("archivePath")
                    val destDir = call.argument<String>("destDir")
                    if (archivePath == null || destDir == null) {
                        result.error("BAD_ARGS", "缺少 archivePath/destDir", null)
                    } else {
                        thread {
                            try {
                                val count = com.venti1112.edgecube.files.ArchiveExtractor.extract(
                                    archivePath, destDir,
                                ) { current, total ->
                                    archiveEventSink?.let { sink ->
                                        runOnUiThread {
                                            sink.success(mapOf("current" to current, "total" to total))
                                        }
                                    }
                                }
                                runOnUiThread { result.success(count) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("EXTRACT_FAILED", e.message, null) }
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // FTP 文件管理通道：对外开放指定根目录的 FTP 访问。
        MethodChannel(messenger, "com.venti1112.edgecube/ftp").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val rootDir = call.argument<String>("rootDir")
                    val port = call.argument<Int>("port")
                    val username = call.argument<String>("username") ?: ""
                    val password = call.argument<String>("password") ?: ""
                    val writable = call.argument<Boolean>("writable") ?: true
                    val ipv6Enabled = call.argument<Boolean>("ipv6Enabled") ?: false
                    if (rootDir == null || port == null) {
                        result.error("BAD_ARGS", "缺少 rootDir/port", null)
                    } else {
                        try {
                            com.venti1112.edgecube.ftp.FtpServerManager.start(
                                rootDir, port, username, password, writable, ipv6Enabled,
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("FTP_START_FAILED", e.message, null)
                        }
                    }
                }
                "stop" -> {
                    com.venti1112.edgecube.ftp.FtpServerManager.stop()
                    result.success(null)
                }
                "isRunning" -> {
                    result.success(com.venti1112.edgecube.ftp.FtpServerManager.isRunning)
                }
                else -> result.notImplemented()
            }
        }

        // SSH 服务通道：同一 SSH 服务器同时提供 SFTP 文件访问与 SSH 终端，与 FTP 独立。
        MethodChannel(messenger, "com.venti1112.edgecube/ssh").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val rootDir = call.argument<String>("rootDir")
                    val port = call.argument<Int>("port")
                    val username = call.argument<String>("username") ?: ""
                    val password = call.argument<String>("password") ?: ""
                    val writable = call.argument<Boolean>("writable") ?: true
                    val sftpEnabled = call.argument<Boolean>("sftpEnabled") ?: true
                    val shellEnabled = call.argument<Boolean>("shellEnabled") ?: true
                    val ipv6Enabled = call.argument<Boolean>("ipv6Enabled") ?: false
                    if (rootDir == null || port == null) {
                        result.error("BAD_ARGS", "缺少 rootDir/port", null)
                    } else {
                        // 首次启动需生成 RSA 主机密钥（数百 ms），放后台线程；完成后回主线程返回。
                        thread {
                            try {
                                com.venti1112.edgecube.ssh.SshServerManager.start(
                                    applicationContext, rootDir, port, username, password,
                                    writable, sftpEnabled, shellEnabled, ipv6Enabled,
                                )
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("SSH_START_FAILED", e.message, null) }
                            }
                        }
                    }
                }
                "stop" -> {
                    com.venti1112.edgecube.ssh.SshServerManager.stop()
                    result.success(null)
                }
                "isRunning" -> {
                    result.success(com.venti1112.edgecube.ssh.SshServerManager.isRunning)
                }
                "hostKeyFingerprint" -> {
                    // 首次可能需生成主机密钥（数百 ms），放后台线程；完成后回主线程返回。
                    thread {
                        try {
                            val fp = com.venti1112.edgecube.ssh.SshServerManager
                                .hostKeyFingerprint(applicationContext)
                            runOnUiThread { result.success(fp) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SSH_FP_FAILED", e.message, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // APK 安装通道：触发系统安装界面安装下载好的更新包。
        MethodChannel(messenger, "com.venti1112.edgecube/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val apkPath = call.argument<String>("apkPath")
                    if (apkPath == null) {
                        result.error("BAD_ARGS", "缺少 apkPath", null)
                    } else {
                        try {
                            com.venti1112.edgecube.update.ApkInstaller.install(applicationContext, apkPath)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, serverEventChannel).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    serverManager.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    serverManager.setEventSink(null)
                }
            },
        )

        // Shell 终端通道：交互式 PTY shell（writeInput/resize 等）与一次性命令执行（runCommand）。
        MethodChannel(messenger, shellChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "availableShells" -> {
                    val nativeDir = applicationContext.applicationInfo.nativeLibraryDir
                    result.success(ShellResolver.availableLabels(nativeDir))
                }

                "isRunning" -> result.success(shellManager.isRunning)

                "start" -> {
                    try {
                        shellManager.start(call.argument<String>("cwd"))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SHELL_START_FAILED", e.message, null)
                    }
                }

                "writeInput" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes != null) shellManager.writeInput(bytes)
                    result.success(null)
                }

                "sendCommand" -> {
                    shellManager.sendCommand(call.argument<String>("line") ?: "")
                    result.success(null)
                }

                "resize" -> {
                    val cols = call.argument<Int>("cols") ?: 0
                    val rows = call.argument<Int>("rows") ?: 0
                    val cellWidth = call.argument<Int>("cellWidth") ?: 0
                    val cellHeight = call.argument<Int>("cellHeight") ?: 0
                    shellManager.resize(rows, cols, cellWidth, cellHeight)
                    result.success(null)
                }

                "setEcho" -> {
                    shellManager.setEcho(call.argument<Boolean>("echo") ?: true)
                    result.success(null)
                }

                "stop" -> {
                    shellManager.stop()
                    result.success(null)
                }

                "forceStop" -> {
                    shellManager.forceStop()
                    result.success(null)
                }

                "clearLog" -> {
                    shellManager.clearLog()
                    result.success(null)
                }

                "runCommand" -> {
                    val command = call.argument<String>("command")
                    if (command == null) {
                        result.error("BAD_ARGS", "缺少 command", null)
                    } else {
                        val cwd = call.argument<String>("cwd")
                        // 命令可能阻塞，放后台线程；完成后回主线程返回结果。
                        thread {
                            try {
                                val res = ShellCommandRunner.runOnce(applicationContext, command, cwd)
                                runOnUiThread { result.success(res) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("RUN_FAILED", e.message, null) }
                            }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, shellEventChannel).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    shellManager.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    shellManager.setEventSink(null)
                }
            },
        )

        // 隧道（frpc）通道：与服务端通道完全独立，可同时运行。
        MethodChannel(messenger, tunnelChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "isFrpcAvailable" ->
                    result.success(RuntimeInstaller.isFrpcAvailable(applicationContext))

                "isFrpcReady" ->
                    result.success(RuntimeInstaller.installedFrpc(applicationContext) != null)

                "isRunning" -> result.success(tunnelManager.isRunning)

                "start" -> {
                    val configPath = call.argument<String>("configPath")
                    val name = call.argument<String>("name") ?: "frpc"
                    val runtimeId = call.argument<String>("runtimeId")
                    if (configPath == null) {
                        result.error("BAD_ARGS", "缺少 configPath", null)
                    } else {
                        // 含首次解压，放后台线程；完成后回主线程返回结果。
                        thread {
                            try {
                                tunnelManager.start(configPath, name, runtimeId)
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("START_FAILED", e.message, null) }
                            }
                        }
                    }
                }

                "stop" -> {
                    tunnelManager.stop()
                    result.success(null)
                }

                "forceStop" -> {
                    tunnelManager.forceStop()
                    result.success(null)
                }

                "reload" -> {
                    val port = call.argument<Int>("port") ?: 0
                    val user = call.argument<String>("user")
                    val password = call.argument<String>("password")
                    if (port <= 0) {
                        result.error("BAD_ARGS", "缺少有效的 port", null)
                    } else {
                        thread {
                            val ok = tunnelManager.reload(port, user, password)
                            runOnUiThread { result.success(ok) }
                        }
                    }
                }

                "clearLog" -> {
                    tunnelManager.clearLog()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        // 运行环境通道：已安装运行时的发现、导入与删除。
        val runtimeChannel = "com.venti1112.edgecube/runtime"
        MethodChannel(messenger, runtimeChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "installedRuntimes" -> {
                    val list = RuntimeInstaller.installedRuntimes(applicationContext).map { m ->
                        mapOf(
                            "id" to m.id,
                            "type" to m.type,
                            "name" to m.name,
                            "version" to m.version,
                            "description" to (m.description ?: ""),
                            "author" to (m.author ?: ""),
                            "updateUrl" to (m.updateUrl ?: ""),
                            "minAppVersion" to m.minAppVersion,
                        )
                    }
                    result.success(list)
                }

                "importPackage" -> {
                    val path = call.argument<String>("path")
                    val force = call.argument<Boolean>("force") ?: false
                    if (path == null) {
                        result.error("BAD_ARGS", "缺少 path", null)
                    } else {
                        thread {
                            try {
                                val manifest = RuntimeInstaller.importPackage(
                                    applicationContext, path, force = force,
                                )
                                runOnUiThread {
                                    result.success(
                                        mapOf(
                                            "id" to manifest.id,
                                            "type" to manifest.type,
                                            "name" to manifest.name,
                                            "version" to manifest.version,
                                            "description" to (manifest.description ?: ""),
                                            "author" to (manifest.author ?: ""),
                                            "updateUrl" to (manifest.updateUrl ?: ""),
                                            "minAppVersion" to manifest.minAppVersion,
                                        ),
                                    )
                                }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("IMPORT_FAILED", e.message, null) }
                            }
                        }
                    }
                }

                "deleteRuntime" -> {
                    val id = call.argument<String>("id")
                    if (id == null) {
                        result.error("BAD_ARGS", "缺少 id", null)
                    } else {
                        RuntimeInstaller.deleteRuntime(applicationContext, id)
                        result.success(null)
                    }
                }

                "isRuntimeRunning" -> {
                    val id = call.argument<String>("id")
                    if (id == null) {
                        result.error("BAD_ARGS", "缺少 id", null)
                    } else {
                        val serverRunning = serverManager.activeRuntimeId == id
                        val tunnelRunning = tunnelManager.isRunning &&
                            RuntimeInstaller.installedFrpc(applicationContext)?.id == id
                        result.success(serverRunning || tunnelRunning)
                    }
                }

                // 返回当前设备架构标识符（arm64 / arm / x86_64），无匹配时返回空串。
                "deviceArch" -> {
                    var arch = ""
                    for (abi in Build.SUPPORTED_ABIS) {
                        arch = when (abi) {
                            "arm64-v8a" -> "arm64"
                            "armeabi-v7a" -> "arm"
                            "x86_64" -> "x86_64"
                            else -> continue
                        }
                        break
                    }
                    result.success(arch)
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, tunnelEventChannel).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    tunnelManager.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    tunnelManager.setEventSink(null)
                }
            },
        )
    }

    private fun isGranted(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun requestAccess(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            result.success(null)
            try {
                val intent = Intent(
                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:$packageName"),
                )
                startActivity(intent)
            } catch (e: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            pendingStoragePermissionResult = result
            requestPermissions(
                arrayOf(
                    android.Manifest.permission.WRITE_EXTERNAL_STORAGE,
                    android.Manifest.permission.READ_EXTERNAL_STORAGE,
                ),
                1003,
            )
        } else {
            result.success(true)
        }
    }

    private fun hasPhotoPermission(): Boolean {
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
                checkSelfPermission(android.Manifest.permission.READ_MEDIA_IMAGES) ==
                    PackageManager.PERMISSION_GRANTED
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ->
                checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE) ==
                    PackageManager.PERMISSION_GRANTED
            else -> true
        }
    }

    private fun requestPhotoPermission(result: MethodChannel.Result) {
        if (hasPhotoPermission()) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }
        if (pendingPhotoPermissionResult != null) {
            result.error("REQUEST_PENDING", "已有照片权限请求正在进行", null)
            return
        }
        pendingPhotoPermissionResult = result
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            android.Manifest.permission.READ_MEDIA_IMAGES
        } else {
            android.Manifest.permission.READ_EXTERNAL_STORAGE
        }
        requestPermissions(arrayOf(permission), 1002)
    }

    private fun queryPhotos(): List<Map<String, Any?>> {
        if (!hasPhotoPermission()) return emptyList()
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.SIZE,
            MediaStore.Images.Media.DATE_MODIFIED,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
        )
        val photos = ArrayList<Map<String, Any?>>()
        contentResolver.query(
            collection,
            projection,
            null,
            null,
            "${MediaStore.Images.Media.DATE_MODIFIED} DESC",
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
            val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE)
            val modifiedColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_MODIFIED)
            val widthColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.WIDTH)
            val heightColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.HEIGHT)
            while (cursor.moveToNext()) {
                val id = cursor.getLong(idColumn)
                val uri = ContentUris.withAppendedId(collection, id).toString()
                photos.add(
                    mapOf(
                        "id" to id,
                        "uri" to uri,
                        "name" to cursor.getString(nameColumn),
                        "size" to cursor.getLong(sizeColumn),
                        "modified" to cursor.getLong(modifiedColumn),
                        "width" to cursor.getInt(widthColumn),
                        "height" to cursor.getInt(heightColumn),
                    ),
                )
            }
        }
        return photos
    }

    private fun readOriginalBytes(uriString: String): ByteArray {
        val uri = Uri.parse(uriString)
        return ByteArrayOutputStream().use { output ->
            contentResolver.openInputStream(uri)?.use { input ->
                input.copyTo(output)
            } ?: throw IllegalArgumentException("无法打开图片")
            output.toByteArray()
        }
    }

    private fun readPhotoBytes(uriString: String, maxSize: Int): ByteArray {
        val uri = Uri.parse(uriString)
        val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            contentResolver.loadThumbnail(uri, Size(maxSize, maxSize), null)
        } else {
            decodeScaledBitmap(uri, maxSize)
        }
        return ByteArrayOutputStream().use { output ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 88, output)
            output.toByteArray()
        }
    }

    private fun decodeScaledBitmap(uri: Uri, maxSize: Int): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        contentResolver.openInputStream(uri)?.use { input ->
            BitmapFactory.decodeStream(input, null, bounds)
        }
        val largest = maxOf(bounds.outWidth, bounds.outHeight).coerceAtLeast(1)
        var sampleSize = 1
        while (largest / sampleSize > maxSize) sampleSize *= 2
        val options = BitmapFactory.Options().apply { inSampleSize = sampleSize }
        contentResolver.openInputStream(uri)?.use { input ->
            return BitmapFactory.decodeStream(input, null, options)
                ?: throw IllegalArgumentException("无法解码图片")
        }
        throw IllegalArgumentException("无法打开图片")
    }

    private fun copyPhotoToCache(uriString: String, name: String?): String {
        val uri = Uri.parse(uriString)
        val safeName = (name ?: "photo").replace(Regex("[^A-Za-z0-9._-]"), "_")
        val suffix = File(safeName).extension.let { if (it.isNotEmpty()) ".$it" else ".jpg" }
        val target = File.createTempFile("selected_photo_", suffix, cacheDir)
        contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(target).use { output -> input.copyTo(output) }
        } ?: throw IllegalArgumentException("无法打开图片")
        return target.absolutePath
    }

    /** 本应用是否已被加入电池优化白名单。低于 Android 6.0 无此机制，视为已忽略。 */
    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    /** 弹出系统对话框申请加入电池优化白名单；个别 ROM 不支持时退回到电池优化设置页。 */
    @SuppressLint("BatteryLife")
    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (isIgnoringBatteryOptimizations()) return
        try {
            val intent = Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:$packageName"),
            )
            startActivity(intent)
        } catch (e: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Exception) {
            }
        }
    }

    // ──────────────────────────────────────────────────────
    // 系统监控：设备内存 + CPU 使用率 + 服务端进程内存
    // ──────────────────────────────────────────────────────

    private fun getSystemInfo(serverManager: ServerProcessManager): Map<String, Any?> {
        val memInfo = readMemInfo()
        val cpuUsage = readCpuUsage()

        val pid = serverManager.pid
        var serverMemMb: Long? = null
        if (pid > 0 && serverManager.isRunning) {
            serverMemMb = readProcessRssKb(pid)?.let { it / 1024 }
        }

        val map = HashMap<String, Any?>()
        map["totalMemMb"] = memInfo[0]     // MemTotal (MB)
        map["usedMemMb"] = memInfo[1]      // Used (MB)
        map["availMemMb"] = memInfo[2]     // MemAvailable (MB)
        map["cpuUsage"] = cpuUsage          // 0.0–100.0；不可用时 -1
        map["serverMemMb"] = serverMemMb   // 服务端 RSS MB；未运行则为 null
        return map
    }

    /**
     * 从 /proc/meminfo 读取内存信息。
     * 返回 [totalMb, usedMb, availMb]。
     */
    private fun readMemInfo(): LongArray {
        var totalKb = 0L
        var availKb = 0L
        var buffersKb = 0L
        var cachedKb = 0L
        try {
            BufferedReader(InputStreamReader(FileInputStream("/proc/meminfo"))).use { reader ->
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    val l = line ?: continue
                    when {
                        l.startsWith("MemTotal:") ->
                            totalKb = l.extractKbValue()
                        l.startsWith("MemAvailable:") ->
                            availKb = l.extractKbValue()
                        l.startsWith("Buffers:") ->
                            buffersKb = l.extractKbValue()
                        l.startsWith("Cached:") ->
                            cachedKb = l.extractKbValue()
                    }
                }
            }
        } catch (_: Exception) {
            // 读取失败时使用 ActivityManager 兑底
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val info = ActivityManager.MemoryInfo()
            am.getMemoryInfo(info)
            return longArrayOf(
                info.totalMem / (1024 * 1024),
                (info.totalMem - info.availMem) / (1024 * 1024),
                info.availMem / (1024 * 1024),
            )
        }

        // 若 MemAvailable 不存在（极老内核），用 Buffers + Cached 估算
        if (availKb == 0L && totalKb > 0L) {
            availKb = buffersKb + cachedKb
        }
        val usedKb = totalKb - availKb
        return longArrayOf(totalKb / 1024, usedKb / 1024, availKb / 1024)
    }

    /** 从 /proc/meminfo 的一行中提取 kB 数值。 */
    private fun String.extractKbValue(): Long {
        // 格式："MemTotal:       12345678 kB"
        val parts = this.trim().split("\\s+".toRegex())
        return parts.getOrNull(1)?.toLongOrNull() ?: 0L
    }

    /**
     * 通过读取各 CPU 核心的当前频率与最大/最小频率计算系统全局 CPU 使用率。
     * CPU% = (curFreq - minFreq) / (maxFreq - minFreq) × 100
     * 对所有核心取平均值。
     * 读取路径：
     *   /sys/devices/system/cpu/cpu[X]/cpufreq/cpuinfo_max_freq
     *   /sys/devices/system/cpu/cpu[X]/cpufreq/cpuinfo_min_freq
     *   /sys/devices/system/cpu/cpu[X]/cpufreq/scaling_cur_freq
     */
    private fun readCpuUsage(): Double {
        val cpuBase = java.io.File("/sys/devices/system/cpu")
        val cpuDirs = cpuBase.listFiles { f ->
            f.isDirectory && f.name.startsWith("cpu") &&
                    f.name.length > 3 && f.name.substring(3).all { it.isDigit() }
        } ?: return -1.0
        if (cpuDirs.isEmpty()) return -1.0

        var totalPercent = 0.0
        var validCores = 0

        for (cpuDir in cpuDirs) {
            val freqDir = java.io.File(cpuDir, "cpufreq")
            if (!freqDir.isDirectory) continue

            val maxFreq = readLongFromFile(java.io.File(freqDir, "cpuinfo_max_freq"))
            val minFreq = readLongFromFile(java.io.File(freqDir, "cpuinfo_min_freq"))
            val curFreq = readLongFromFile(java.io.File(freqDir, "scaling_cur_freq"))

            if (maxFreq < 0 || minFreq < 0 || curFreq < 0) continue

            val range = maxFreq - minFreq
            val percent = if (range > 0) {
                ((curFreq - minFreq).toDouble() / range.toDouble()) * 100.0
            } else {
                // 最大最小频率相同，说明是固定频率，根据当前频率判断
                if (curFreq >= maxFreq) 100.0 else 0.0
            }

            totalPercent += percent.coerceIn(0.0, 100.0)
            validCores++
        }

        return if (validCores > 0) {
            (totalPercent / validCores).coerceIn(0.0, 100.0)
        } else {
            -1.0
        }
    }

    /** 读取文件中的长整型数值；失败返回 -1。 */
    private fun readLongFromFile(file: java.io.File): Long {
        return try {
            BufferedReader(InputStreamReader(FileInputStream(file))).use {
                it.readLine()?.trim()?.toLongOrNull() ?: -1
            }
        } catch (_: Exception) {
            -1
        }
    }

    /**
     * 读取指定 PID 进程的 RSS（驻留内存，单位 KB）。
     * 从 /proc/<pid>/stat 第 24 个字段（1-indexed）读取页数，乘以页大小。
     */
    private fun readProcessRssKb(pid: Int): Long? {
        return try {
            val line = BufferedReader(
                InputStreamReader(FileInputStream("/proc/$pid/stat"))
            ).use { it.readLine() } ?: return null

            // 进程名可能含空格和括号，从最后一个 ')' 之后开始切分
            val closeParen = line.lastIndexOf(')')
            if (closeParen < 0) return null
            val fields = line.substring(closeParen + 2).trim().split(" ")
            // ')' 之后第 1 个字段是 state(index 0)，RSS 是 index 21
            if (fields.size < 22) return null
            val rssPages = fields[21].toLongOrNull() ?: return null
            val pageSizeKb = 4L  // Linux 页大小 4KB
            rssPages * pageSizeKb
        } catch (_: Exception) {
            null
        }
    }

    // ──────────────────────────────────────────────────────
    // 设备信息：SoC 型号、架构、制造商、型号
    // ──────────────────────────────────────────────────────

    /**
     * 返回设备硬件信息，用于崩溃报告。
     * SoC 型号从 /proc/cpuinfo 的 Hardware / Processor 字段读取。
     */
    private fun getDeviceInfo(): Map<String, Any?> {
        val map = HashMap<String, Any?>()
        map["socModel"] = readSocModel()
        map["architecture"] = Build.SUPPORTED_ABIS?.firstOrNull() ?: "unknown"
        map["manufacturer"] = Build.MANUFACTURER ?: "unknown"
        map["model"] = Build.MODEL ?: "unknown"
        map["androidVersion"] = Build.VERSION.RELEASE ?: "unknown"
        map["securityPatch"] = Build.VERSION.SECURITY_PATCH ?: "unknown"
        return map
    }

    /**
     * 高通 soc_id 到芯片营销名的映射（来源于 Linux 内核 qcom,ids.h）。
     * 当 /sys/devices/soc0/soc_id 返回数字时，用此表转换为可读名称。
     */
    private val qualcommSocIdMap: Map<String, String> = mapOf(
        // Snapdragon 8 系列
        "339" to "Snapdragon 865",
        "356" to "Snapdragon 870",
        "439" to "Snapdragon 888",
        "457" to "Snapdragon 8 Gen 1",
        "519" to "Snapdragon 8 Gen 2",
        "557" to "Snapdragon 8 Gen 3",
        "618" to "Snapdragon 8 Elite",
        "660" to "Snapdragon 8 Elite Gen 5",
        // Snapdragon 7 系列
        "459" to "Snapdragon 778G",
        "506" to "Snapdragon 7 Gen 1",
        "547" to "Snapdragon 7+ Gen 2",
        "636" to "Snapdragon 7 Gen 3",
        // Snapdragon 6 系列
        "507" to "Snapdragon 695",
        "640" to "Snapdragon 6 Gen 1",
        // Snapdragon X 系列
        "555" to "Snapdragon X Elite",
        // 其他常见
        "530" to "Snapdragon 8+ Gen 1",
        "531" to "Snapdragon 8+ Gen 1",
        "534" to "Snapdragon 8s Gen 3",
    )

    /**
     * 读取 SoC 型号，按优先级尝试多种来源：
     * 1. /proc/cpuinfo 的 Hardware 字段（常见于高通设备）
     * 2. /proc/cpuinfo 的 Processor 字段
     * 3. /proc/cpuinfo 的 model name 字段（常见于 x86 设备）
     * 4. /sys/devices/soc0/machine（sysfs，常含真实芯片名）
     * 5. /sys/devices/soc0/soc_id（高通 soc_id 编码，通过映射表转换）
     * 6. Build.HARDWARE（始终可用，但高通设备只返回 "qcom"）
     */
    private fun readSocModel(): String {
        var hardware = ""
        var processor = ""
        var modelName = ""
        try {
            BufferedReader(InputStreamReader(FileInputStream("/proc/cpuinfo"))).use { reader ->
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    val l = line ?: continue
                    when {
                        l.startsWith("Hardware") && hardware.isEmpty() ->
                            hardware = l.substringAfter(':').trim()
                        l.startsWith("Processor") && processor.isEmpty() ->
                            processor = l.substringAfter(':').trim()
                        l.startsWith("model name") && modelName.isEmpty() ->
                            modelName = l.substringAfter(':').trim()
                    }
                }
            }
        } catch (_: Exception) {
            // 读取失败继续兑底
        }

        // cpuinfo 字段中优先级最高的直接返回
        if (hardware.isNotEmpty()) return hardware
        if (processor.isNotEmpty()) return processor
        if (modelName.isNotEmpty()) return modelName

        // sysfs：常含可读的芯片名（如 "Snapdragon 8 Gen 2"）
        val socMachine = readSysfsTrimmed("/sys/devices/soc0/machine")
        if (!socMachine.isNullOrEmpty() && socMachine != "Unknown") return socMachine

        // soc_id 是数字时，通过映射表转换为可读名称
        val socId = readSysfsTrimmed("/sys/devices/soc0/soc_id")
        if (!socId.isNullOrEmpty()) {
            val mapped = qualcommSocIdMap[socId]
            if (mapped != null) return mapped
            // 不在映射表中，尝试返回原始 soc_id（如果不是纯数字则直接返回）
            if (!socId.all { it.isDigit() }) return socId
        }

        // 最终兑底：Build.HARDWARE，但跳过高通的泛化值 "qcom"
        val hw = Build.HARDWARE
        if (!hw.isNullOrEmpty() && hw != "qcom") return hw

        // 如果所有可读来源都失败，但 soc_id 是数字，也返回它（好过 unknown）
        if (!socId.isNullOrEmpty()) return socId

        return "unknown"
    }

    /** 读取单行 sysfs 文件并去除首尾空白，失败返回 null。 */
    private fun readSysfsTrimmed(path: String): String? {
        return try {
            BufferedReader(InputStreamReader(FileInputStream(path))).use {
                it.readLine()?.trim()?.takeIf { s -> s.isNotEmpty() }
            }
        } catch (_: Exception) {
            null
        }
    }

    // ──────────────────────────────────────────────────────
    // Forge 安装器：通过 liblaunch.so 运行 Forge Installer
    // ──────────────────────────────────────────────────────

    private val forgeAnsiPattern = Regex("\\x1B\\[[0-?]*[ -/]*[@-~]")

    /**
     * 在后台线程运行 Forge Installer（java -jar installer.jar --installServer）。
     * 复用 liblaunch.so + JRE 机制，绕开 Android SELinux 对 data 目录的 execve 限制。
     * 安装器会自行下载 Forge 库文件到 workingDir。
     *
     * @return 进程退出码，0 表示成功。
     */
    private fun runForgeInstaller(
        installerJar: String,
        workingDir: String,
        javaVersion: String,
        sink: EventChannel.EventSink?,
        mainHandler: Handler = Handler(Looper.getMainLooper()),
    ): Int {
        val nativeDir = applicationContext.applicationInfo.nativeLibraryDir
        val tagfixLib = "$nativeDir/libtagfix.so"

        // 确保 JRE 已安装。
        val manifest = RuntimeInstaller.installedRuntime(applicationContext, javaVersion)
            ?: throw IllegalStateException("JRE 运行时 $javaVersion 未安装，请先在「管理 → 运行环境」导入")

        val jreDir = RuntimeInstaller.runtimeDir(applicationContext, javaVersion)
        val resolved = JreLayout.resolve(jreDir, nativeDir)
        val launchBin = File(nativeDir, "liblaunch.so")
        if (!launchBin.exists()) {
            throw IllegalStateException("未找到 liblaunch.so，请确认其已随 APK 打包到 lib 目录")
        }

        val cmd = listOf(
            launchBin.absolutePath,
            "-XX:ErrorFile=/proc/self/fd/2",
            // Android 上 /tmp 不可写，指定可写的 tmpdir
            "-Djava.io.tmpdir=${applicationContext.cacheDir.absolutePath}",
            "-jar", installerJar,
            "--installServer",
        )

        val pb = ProcessBuilder(cmd)
        pb.directory(File(workingDir))
        pb.redirectErrorStream(true)
        val env = pb.environment()
        env["LD_PRELOAD"] = tagfixLib
        env["JAVA_HOME"] = jreDir.absolutePath
        env["EC_LIBJLI"] = resolved.libjli.absolutePath
        env["LD_LIBRARY_PATH"] = resolved.ldLibraryPath
        env["HOME"] = workingDir
        env["TMPDIR"] = applicationContext.cacheDir.absolutePath
        env["LANG"] = "en_US.UTF-8"
        env["FCL_NATIVEDIR"] = nativeDir
        env["POJAV_NATIVEDIR"] = nativeDir
        env["PATH"] = "${jreDir.absolutePath}/bin:${System.getenv("PATH") ?: ""}"
        // 叠加清单 env
        for ((key, rawValue) in manifest.env) {
            if (key.startsWith("EC_") || key == "LD_PRELOAD" || key == "TMPDIR") continue
            val value = rawValue.replace("\${RUNTIME_DIR}", jreDir.absolutePath)
            when (key) {
                "PATH" -> {
                    val existing = env["PATH"] ?: ""
                    env[key] = if (existing.isEmpty()) value else "$value:$existing"
                }
                "LD_LIBRARY_PATH" -> {
                    val existing = env["LD_LIBRARY_PATH"] ?: ""
                    env[key] = if (existing.isEmpty()) value else "$value:$existing"
                }
                else -> env[key] = value
            }
        }

        emitForgeEvent(sink, mainHandler, "[EdgeCube] 开始安装 Forge 服务端…")
        val p = pb.start()

        var exitCode = -1
        try {
            BufferedReader(InputStreamReader(p.inputStream, StandardCharsets.UTF_8)).use { reader ->
                var line = reader.readLine()
                while (line != null) {
                    val clean = forgeAnsiPattern.replace(line, "")
                    emitForgeEvent(sink, mainHandler, clean)
                    line = reader.readLine()
                }
            }
            exitCode = p.waitFor()
        } catch (e: Exception) {
            emitForgeEvent(sink, mainHandler, "[EdgeCube] 安装器异常：${e.message}")
        }

        emitForgeEvent(sink, mainHandler, "[EdgeCube] 安装器退出，退出码：$exitCode")
        return exitCode
    }

    private fun emitForgeEvent(sink: EventChannel.EventSink?, handler: Handler, line: String) {
        if (sink == null) return
        handler.post { sink.success(line) }
    }
}

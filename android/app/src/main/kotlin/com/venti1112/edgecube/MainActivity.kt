package com.venti1112.edgecube

import android.annotation.SuppressLint
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import androidx.annotation.NonNull
import com.venti1112.edgecube.server.RuntimeInstaller
import com.venti1112.edgecube.server.ServerProcessManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.FileInputStream
import java.io.InputStreamReader
import kotlin.concurrent.thread

/**
 * 平台通道宿主：
 *  - storage：「管理全部文件」权限查询/申请。
 *  - power：电池优化白名单状态查询与申请。
 *  - server / server_events：服务端 JVM 进程的启动、停止、命令输入与日志/状态回传。
 */
class MainActivity : FlutterActivity() {
    private val storageChannel = "com.venti1112.edgecube/storage"
    private val powerChannel = "com.venti1112.edgecube/power"
    private val serverChannel = "com.venti1112.edgecube/server"
    private val serverEventChannel = "com.venti1112.edgecube/server_events"
    private val systemMonitorChannel = "com.venti1112.edgecube/system_monitor"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 13+ 显示前台 Service 通知需要运行时授权；未授权也不影响保活，仅不显示通知。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1001)
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val serverManager = ServerProcessManager.getInstance(applicationContext)

        MethodChannel(messenger, storageChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "isGranted" -> result.success(isGranted())
                "request" -> {
                    requestAccess()
                    result.success(null)
                }
                "externalStorageRoot" ->
                    result.success(Environment.getExternalStorageDirectory()?.absolutePath)
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
                    result.success(RuntimeInstaller.availableVersions(applicationContext))

                "availablePhpRuntimes" ->
                    result.success(RuntimeInstaller.availablePhpRuntimes(applicationContext))

                "isRuntimeReady" -> {
                    val version = call.argument<String>("version")
                    if (version == null) {
                        result.error("BAD_ARGS", "缺少 version", null)
                    } else {
                        result.success(RuntimeInstaller.isInstalled(applicationContext, version))
                    }
                }

                "isRunning" -> result.success(serverManager.isRunning)

                "activeInstanceId" -> result.success(serverManager.activeInstanceId)

                "start" -> {
                    val instanceId = call.argument<String>("instanceId")
                    val workingDir = call.argument<String>("workingDir")
                    val version = call.argument<String>("version")
                    val runtime = call.argument<String>("runtime") ?: "java"
                    val jvmArgs = call.argument<List<String>>("jvmArgs") ?: emptyList()
                    val programArgs = call.argument<List<String>>("programArgs") ?: emptyList()
                    if (instanceId == null || workingDir == null || version == null) {
                        result.error("BAD_ARGS", "缺少 instanceId/workingDir/version", null)
                    } else {
                        val instanceName = call.argument<String>("instanceName") ?: instanceId
                        // 含解压，放后台线程；完成后回主线程返回结果。
                        thread {
                            try {
                                serverManager.start(
                                    instanceId, instanceName, workingDir, version, runtime, jvmArgs, programArgs,
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

        // 系统监控通道：设备内存、CPU 使用率、服务端进程内存。
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
    }

    private fun isGranted(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            // 低版本由运行时权限处理，此处视为已具备访问能力。
            true
        }
    }

    private fun requestAccess() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        // 优先跳转到本应用的「所有文件访问权限」页；失败则退回到列表页。
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:$packageName"),
            )
            startActivity(intent)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
        }
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
}

package com.venti1112.edgecube

import android.annotation.SuppressLint
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
                                    instanceId, instanceName, workingDir, version, jvmArgs, programArgs,
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
}

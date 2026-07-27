package com.venti1112.edgecube.channels

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import com.venti1112.edgecube.keepalive.KeepAliveManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 电源与保活通道：电池优化白名单、WakeLock/WifiLock 与状态悬浮窗开关、
 * 防息屏开关，以及返回键的「后台/退出」策略。
 */
internal object PowerChannel {

    private const val CHANNEL = "com.venti1112.edgecube/power"

    fun register(messenger: BinaryMessenger, activity: Activity) {
        val appContext = activity.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" ->
                    result.success(isIgnoringBatteryOptimizations(activity))
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations(activity)
                    result.success(null)
                }
                // —— WakeLock/WifiLock 与状态悬浮窗 ——
                "isWakeLockEnabled" ->
                    result.success(KeepAliveManager.isWakeLockEnabled(appContext))
                "setWakeLockEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    KeepAliveManager.setWakeLockEnabled(appContext, enabled)
                    result.success(null)
                }
                "isKeepScreenOnEnabled" ->
                    result.success(KeepAliveManager.isKeepScreenOnEnabled(appContext))
                "setKeepScreenOnEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    KeepAliveManager.setKeepScreenOnEnabled(appContext, enabled)
                    result.success(null)
                }
                "isOverlayEnabled" ->
                    result.success(KeepAliveManager.isOverlayEnabled(appContext))
                "setOverlayEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    KeepAliveManager.setOverlayEnabled(appContext, enabled)
                    result.success(null)
                }
                "canDrawOverlays" ->
                    result.success(KeepAliveManager.canDrawOverlays(appContext))
                "requestOverlayPermission" -> {
                    requestOverlayPermission(activity)
                    result.success(null)
                }
                "getOverlayOptions" ->
                    result.success(KeepAliveManager.overlayOptions(appContext).toMap())
                "setOverlayOptions" -> {
                    val map = call.arguments as? Map<*, *>
                    if (map == null) {
                        result.error("BAD_ARGS", "缺少悬浮窗设置", null)
                    } else {
                        KeepAliveManager.setOverlayOptions(appContext, map)
                        result.success(null)
                    }
                }
                // —— 返回键退出策略 ——
                "moveTaskToBack" -> {
                    // 服务端运行中按返回键：任务移到后台（等效 Home 键），
                    // Activity 与 Flutter 引擎保持存活，回前台后页面状态不丢失。
                    activity.moveTaskToBack(true)
                    result.success(null)
                }
                "exitApp" -> {
                    // 服务端未运行时按返回键：结束任务并彻底杀死进程，不留后台残留。
                    result.success(null)
                    activity.finishAndRemoveTask()
                    // 稍作延迟让通道回复送达、finish 动画启动后再终止进程。
                    Handler(Looper.getMainLooper()).postDelayed({
                        android.os.Process.killProcess(android.os.Process.myPid())
                    }, 150)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** 本应用是否已被加入电池优化白名单。低于 Android 6.0 无此机制，视为已忽略。 */
    private fun isIgnoringBatteryOptimizations(activity: Activity): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(activity.packageName)
    }

    /** 弹出系统对话框申请加入电池优化白名单；个别 ROM 不支持时退回到电池优化设置页。 */
    @SuppressLint("BatteryLife")
    private fun requestIgnoreBatteryOptimizations(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (isIgnoringBatteryOptimizations(activity)) return
        try {
            val intent = Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:${activity.packageName}"),
            )
            activity.startActivity(intent)
        } catch (e: Exception) {
            try {
                activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Exception) {
            }
        }
    }

    /** 跳转到本应用的悬浮窗权限设置页（SYSTEM_ALERT_WINDOW 只能由用户手动授予）。 */
    private fun requestOverlayPermission(activity: Activity) {
        if (KeepAliveManager.canDrawOverlays(activity.applicationContext)) return
        try {
            activity.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${activity.packageName}"),
                ),
            )
        } catch (_: Exception) {
            try {
                activity.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION))
            } catch (_: Exception) {
            }
        }
    }
}

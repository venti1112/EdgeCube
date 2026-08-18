package com.venti1112.edgecube.channels

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import com.venti1112.edgecube.keepalive.KeepAlivePrefs
import com.venti1112.edgecube.server.ServerProcessManager
import com.venti1112.edgecube.widget.ServerWidgetProvider
import com.venti1112.edgecube.widget.WidgetUpdater
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 桌面小组件通道：Dart 侧与原生侧的桥接。
 *
 * 提供：
 *  - `isSupported`：Android 8+ 返回 true（Android 7 或更低不支持 requestPinAppWidget）
 *  - `setEnabled`：用户在「设置 / 桌面小组件」页切换总开关；开启时同时通过
 *    PackageManager setComponentEnabledSetting 让 receiver 可被系统识别，关闭时禁用。
 *  - `setDisplayOptions`：把 Map 同步写入 [KeepAlivePrefs]，并触发一次小组件刷新。
 *  - `getDisplayOptions` / `isEnabled`：读回当前设置。
 *  - `setPlayerCount` / `setPublicAddress` / `setServerPort`：转发到 ServerProcessManager
 *    单实例，使其把快照写入 prefs 并触发 requestUpdate。
 *  - `requestPinWidget`：调用 AppWidgetManager.requestPinAppWidget（Android 8+）。
 */
internal object WidgetChannel {

    private const val CHANNEL = "com.venti1112.edgecube/widget"

    fun register(messenger: BinaryMessenger, context: Context) {
        val appContext = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" ->
                    result.success(isSupported(appContext))
                "isEnabled" ->
                    result.success(isEnabled(appContext))
                "setEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    setEnabled(appContext, enabled)
                    result.success(null)
                }
                "getDisplayOptions" ->
                    result.success(displayOptionsMap(appContext))
                "setDisplayOptions" -> {
                    val map = call.argument<Map<String, Any?>>("options")
                    if (map != null) {
                        KeepAlivePrefs.putWidgetDisplayOptions(appContext, map)
                        WidgetUpdater.requestUpdate(appContext)
                    }
                    result.success(null)
                }
                "getAppearance" ->
                    result.success(appearanceMap(appContext))
                "setAppearance" -> {
                    val map = call.argument<Map<String, Any?>>("appearance")
                    if (map != null) {
                        KeepAlivePrefs.putWidgetAppearance(appContext, map)
                        WidgetUpdater.requestUpdate(appContext)
                    }
                    result.success(null)
                }
                "setLocalAddress" -> {
                    val addr = call.argument<String?>("address")
                    ServerProcessManager.getInstance(appContext).setLocalAddressForWidget(addr)
                    result.success(null)
                }
                "setPlayerCount" -> {
                    val count = (call.argument<Int>("count") ?: 0)
                    ServerProcessManager.getInstance(appContext).setPlayerCount(count)
                    result.success(null)
                }
                "setPublicAddress" -> {
                    val addr = call.argument<String?>("address")
                    ServerProcessManager.getInstance(appContext).setPublicAddressForWidget(addr)
                    result.success(null)
                }
                "setServerPort" -> {
                    val port = call.argument<Int>("port") ?: 0
                    ServerProcessManager.getInstance(appContext).setServerPortForWidget(port)
                    result.success(null)
                }
                "pushStatus" -> {
                    // Dart 侧 ServerController.notifyListeners() 经 throttle 触发，
                    // 把最新 (status, instanceName) 一次性下发，使小组件即时刷新。
                    val status = call.argument<String>("status")
                    val name = call.argument<String>("instanceName")
                    KeepAlivePrefs.putWidgetSnapshot(
                        appContext,
                        status = status,
                        instanceName = name,
                    )
                    WidgetUpdater.requestUpdate(appContext)
                    result.success(null)
                }
                "requestUpdate" -> {
                    WidgetUpdater.requestUpdate(appContext)
                    result.success(null)
                }
                "requestPinWidget" ->
                    result.success(requestPin(appContext))
                else -> result.notImplemented()
            }
        }
    }

    /** Android 8+ 支持 AppWidgetManager.requestPinAppWidget。 */
    private fun isSupported(context: Context): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O

    /** 通过 receiver 组件 enabled 状态判定总开关是否开启。 */
    private fun isEnabled(context: Context): Boolean {
        if (!isSupported(context)) return false
        val pm = context.packageManager
        val component = ComponentName(context, ServerWidgetProvider::class.java)
        return pm.getComponentEnabledSetting(component) !=
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
    }

    /** 启用/禁用 receiver；同时写入 prefs 让 Dart 侧 UI 同步。 */
    private fun setEnabled(context: Context, enabled: Boolean) {
        if (!isSupported(context)) return
        val pm = context.packageManager
        val component = ComponentName(context, ServerWidgetProvider::class.java)
        val newState = if (enabled) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        try {
            pm.setComponentEnabledSetting(
                component,
                newState,
                PackageManager.DONT_KILL_APP,
            )
        } catch (_: Exception) {
        }
        KeepAlivePrefs.setWidgetEnabled(context, enabled)
        if (enabled) {
            WidgetUpdater.requestUpdate(context)
        }
    }

    private fun displayOptionsMap(context: Context): Map<String, Boolean> {
        val von = KeepAlivePrefs.widgetDisplayOptions(context)
        return mapOf(
            "showInstance" to von.showInstance,
            "showPlayers" to von.showPlayers,
            "showAddress" to von.showAddress,
            "showStats" to von.showStats,
            "showButtons" to von.showButtons,
        )
    }

    private fun appearanceMap(context: Context): Map<String, Int> {
        val appearance = KeepAlivePrefs.widgetAppearance(context)
        return mapOf(
            "bgColor" to appearance.bgColor,
            "bgOpacity" to appearance.bgOpacity,
            "textColor" to appearance.textColor,
            "textOpacity" to appearance.textOpacity,
        )
    }

    /** 调用 AppWidgetManager.requestPinAppWidget；不支持时返回 false。 */
    private fun requestPin(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        try {
            val mgr = AppWidgetManager.getInstance(context)
            if (!mgr.isRequestPinAppWidgetSupported) return false
            val provider = ComponentName(context, ServerWidgetProvider::class.java)
            val callback: PendingIntent? = null
            mgr.requestPinAppWidget(provider, null, callback)
            return true
        } catch (_: Exception) {
            return false
        }
    }
}

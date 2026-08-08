package com.venti1112.edgecube.keepalive

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import java.lang.ref.WeakReference

/**
 * 后台保活增强：CPU WakeLock、WifiLock、防息屏与状态悬浮窗，随服务端进程启停。
 *
 * 与前台 Service（[com.venti1112.edgecube.server.ServerService]）互补：
 * - WakeLock（PARTIAL）阻止锁屏后 CPU 深度休眠，避免服务端 tick 卡顿/玩家掉线；
 * - WifiLock（低延迟/高性能模式）阻止 Wi-Fi 进入省电休眠，保持连接稳定；
 * - 状态悬浮窗见 [StatusOverlay]，开关与设置持久化见 [KeepAlivePrefs]。
 */
object KeepAliveManager {

    private const val WAKE_LOCK_TAG = "EdgeCube:server"

    private val mainHandler = Handler(Looper.getMainLooper())

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    /** 服务端是否处于运行期（acquire 与 release 之间）。 */
    private var active = false
    private var instanceName: String = ""

    /** 当前前台 Activity 的弱引用，用于防息屏（FLAG_KEEP_SCREEN_ON 须挂在窗口上）。 */
    private var activityRef: WeakReference<Activity>? = null

    /** 熄屏页运行期间的强制常亮覆盖（不写偏好，随熄屏页进出）。 */
    private var keepScreenOnOverride = false

    /** 熄屏页运行期间的悬浮窗隐藏覆盖（不写偏好，随熄屏页进出）。 */
    private var overlayHiddenOverride = false

    // —— 开关读写（持久化见 KeepAlivePrefs；运行中修改立即生效）——

    /** 锁屏保活（WakeLock + WifiLock）是否启用；默认启用。 */
    fun isWakeLockEnabled(context: Context): Boolean =
        KeepAlivePrefs.wakeLockEnabled(context)

    /** 防息屏是否启用；默认关闭。仅在服务端运行期间生效。 */
    fun isKeepScreenOnEnabled(context: Context): Boolean =
        KeepAlivePrefs.keepScreenOnEnabled(context)

    /** 状态悬浮窗是否启用；默认关闭（需要用户授予悬浮窗权限）。 */
    fun isOverlayEnabled(context: Context): Boolean =
        KeepAlivePrefs.overlayEnabled(context)

    /** 读取悬浮窗展示与交互设置。 */
    fun overlayOptions(context: Context): OverlayOptions =
        KeepAlivePrefs.overlayOptions(context)

    /** 保存悬浮窗设置；悬浮窗正在显示时立即重建生效。 */
    @Synchronized
    fun setOverlayOptions(context: Context, map: Map<*, *>) {
        KeepAlivePrefs.putOverlayOptions(context, map)
        if (active && isOverlayEnabled(context) && !overlayHiddenOverride) {
            // 重建悬浮窗应用新样式（位置按保存的比例还原）。
            val app = context.applicationContext
            val name = instanceName
            mainHandler.post {
                StatusOverlay.hide(app)
                if (canDrawOverlays(app)) StatusOverlay.show(app, name)
            }
        }
    }

    /** 设置锁屏保活开关；服务端运行中立即生效。 */
    @Synchronized
    fun setWakeLockEnabled(context: Context, enabled: Boolean) {
        KeepAlivePrefs.setWakeLockEnabled(context, enabled)
        if (active) applyLocks(context, enabled)
    }

    /** 设置防息屏开关；服务端运行中立即生效。 */
    @Synchronized
    fun setKeepScreenOnEnabled(context: Context, enabled: Boolean) {
        KeepAlivePrefs.setKeepScreenOnEnabled(context, enabled)
        syncKeepScreenOn(context)
    }

    /** 设置熄屏页强制常亮覆盖（不持久化，不依赖服务端运行状态）；熄屏页关闭时置 false。 */
    @Synchronized
    fun setKeepScreenOnOverride(context: Context, enabled: Boolean) {
        keepScreenOnOverride = enabled
        syncKeepScreenOn(context)
    }

    /** 设置状态悬浮窗开关；服务端运行中立即生效。 */
    @Synchronized
    fun setOverlayEnabled(context: Context, enabled: Boolean) {
        KeepAlivePrefs.setOverlayEnabled(context, enabled)
        if (active) syncOverlay(context)
    }

    /** 设置熄屏页期间的悬浮窗隐藏覆盖（不持久化）；熄屏页关闭时置 false。 */
    @Synchronized
    fun setOverlayHidden(context: Context, hidden: Boolean) {
        overlayHiddenOverride = hidden
        syncOverlay(context)
    }

    /**
     * 绑定当前前台 Activity，用于防息屏（FLAG_KEEP_SCREEN_ON 须挂在窗口上）。
     * 由 [com.venti1112.edgecube.MainActivity.onResume] 调用；若服务端正在运行且已
     * 启用防息屏，立即应用。Activity 销毁后弱引用自动失效，无需显式解绑。
     */
    @Synchronized
    fun bindActivity(activity: Activity) {
        activityRef = WeakReference(activity)
        syncKeepScreenOn(activity)
    }

    /** 是否已授予悬浮窗（SYSTEM_ALERT_WINDOW）权限。 */
    fun canDrawOverlays(context: Context): Boolean =
        Settings.canDrawOverlays(context)

    // —— 生命周期（由 ServerService 调用）——

    /** 服务端启动：按开关获取锁并显示悬浮窗。可重复调用（更新实例名）。 */
    @Synchronized
    fun acquire(context: Context, name: String) {
        active = true
        instanceName = name
        applyLocks(context, isWakeLockEnabled(context))
        syncOverlay(context)
        syncKeepScreenOn(context)
    }

    /** 服务端停止：释放全部锁并移除悬浮窗。 */
    @Synchronized
    fun release(context: Context) {
        active = false
        applyLocks(context, false)
        syncOverlay(context)
        syncKeepScreenOn(context)
    }

    // —— WakeLock / WifiLock ——

    @SuppressLint("WakelockTimeout") // 服务端运行期间持续持有，随进程退出释放。
    private fun applyLocks(context: Context, enabled: Boolean) {
        val app = context.applicationContext
        if (enabled) {
            if (wakeLock == null) {
                try {
                    val pm = app.getSystemService(Context.POWER_SERVICE) as PowerManager
                    wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
                        .apply { acquire() }
                } catch (_: Exception) {
                    wakeLock = null
                }
            }
            if (wifiLock == null) {
                try {
                    val wm = app.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    @Suppress("DEPRECATION")
                    val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                    } else {
                        WifiManager.WIFI_MODE_FULL_HIGH_PERF
                    }
                    wifiLock = wm.createWifiLock(mode, WAKE_LOCK_TAG).apply { acquire() }
                } catch (_: Exception) {
                    wifiLock = null
                }
            }
        } else {
            try {
                wakeLock?.takeIf { it.isHeld }?.release()
            } catch (_: Exception) {
            }
            wakeLock = null
            try {
                wifiLock?.takeIf { it.isHeld }?.release()
            } catch (_: Exception) {
            }
            wifiLock = null
        }
    }

    // —— 防息屏（FLAG_KEEP_SCREEN_ON，须挂在 Activity 窗口上）——

    /**
     * 按覆盖标志与「防息屏」开关的服务端运行期状态，统一裁决是否挂屏幕常亮标志。
     * 熄屏页覆盖优先（即使服务端未在运行也会亮屏），其次防息屏开关仅在服务端
     * 运行期间生效。
     */
    private fun syncKeepScreenOn(context: Context) {
        val want = keepScreenOnOverride ||
            (active && isKeepScreenOnEnabled(context))
        applyKeepScreenOn(want)
    }

    /**
     * 在当前前台 Activity 的窗口上添加/移除 [WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON]。
     * 仅在该窗口可见时生效（App 在前台时），无需额外权限。
     * 服务端停止、开关关闭或熄屏页退出时清除标志，恢复正常息屏。
     */
    private fun applyKeepScreenOn(enabled: Boolean) {
        val activity = activityRef?.get()
        if (activity == null) {
            // Activity 尚未绑定（如服务端在 App 后台启动）：标志会在
            // 下次 onResume 经 bindActivity 补上。
            return
        }
        mainHandler.post {
            try {
                if (enabled) {
                    activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
            } catch (_: Exception) {
            }
        }
    }

    // —— 状态悬浮窗 ——

    /**
     * 按覆盖标志与「悬浮窗」开关统一裁决是否显示悬浮窗：
     * 仅服务端运行中 + 开关开启 + 未被熄屏页隐藏覆盖时显示。
     * 熄屏页覆盖优先（熄屏期间即使开关开启也隐藏，避免双层遮罩）。
     */
    private fun syncOverlay(context: Context) {
        val want = active && isOverlayEnabled(context) && !overlayHiddenOverride
        applyOverlay(context, want)
    }

    private fun applyOverlay(context: Context, enabled: Boolean) {
        val app = context.applicationContext
        val name = instanceName
        // WindowManager 只能在主线程操作。
        mainHandler.post {
            if (enabled) {
                if (!StatusOverlay.isShowing && canDrawOverlays(app)) {
                    StatusOverlay.show(app, name)
                }
            } else {
                StatusOverlay.hide(app)
            }
        }
    }
}

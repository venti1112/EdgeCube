package com.venti1112.edgecube.server

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import com.venti1112.edgecube.MainActivity
import java.lang.ref.WeakReference
import kotlin.concurrent.thread
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * 后台保活增强：CPU WakeLock、WifiLock 与状态悬浮窗，随服务端进程启停。
 *
 * 与前台 Service（[ServerService]）互补：
 * - WakeLock（PARTIAL）阻止锁屏后 CPU 深度休眠，避免服务端 tick 卡顿/玩家掉线；
 * - WifiLock（低延迟/高性能模式）阻止 Wi-Fi 进入省电休眠，保持连接稳定；
 * - 状态悬浮窗除随时展示运行状态外，部分 ROM 会将有可见悬浮窗的应用视为
 *   「用户可感知」，进一步降低被后台清理的概率。
 *
 * 悬浮窗支持自定义（见 [OverlayOptions]）：
 * - 展示 CPU / 设备内存 / 服务端内存占用（周期刷新）；
 * - 仅显示一个状态点，点颜色可绑定运行状态或某项占用率；
 * - 穿透模式：悬浮窗不响应任何触摸，点击/拖拽直接落到下层应用。
 *
 * 开关持久化在原生 SharedPreferences（而非 Dart 侧配置文件）：acquire 发生在
 * [ServerService] 的原生启动路径上，即使 Flutter 引擎被回收也须能同步读取。
 */
object KeepAliveManager {

    private const val PREFS = "keep_alive"
    private const val KEY_WAKE_LOCK = "wake_lock_enabled"
    private const val KEY_OVERLAY = "overlay_enabled"
    private const val KEY_OVERLAY_SHOW_CPU = "overlay_show_cpu"
    private const val KEY_OVERLAY_SHOW_MEM = "overlay_show_mem"
    private const val KEY_OVERLAY_SHOW_SERVER_MEM = "overlay_show_server_mem"
    private const val KEY_OVERLAY_DOT_ONLY = "overlay_dot_only"
    private const val KEY_OVERLAY_DOT_COLOR_SOURCE = "overlay_dot_color_source"
    private const val KEY_OVERLAY_CLICK_THROUGH = "overlay_click_through"
    private const val KEY_KEEP_SCREEN_ON = "keep_screen_on_enabled"
    // 悬浮窗位置：按「可移动范围的比例」（0..1）持久化，而非绝对像素。
    // 这样横竖屏切换（屏幕宽高互换）与不同分辨率下都能还原到等价位置，
    // 1.0 恒表示贴右/底边。
    private const val KEY_OVERLAY_POS_X_RATIO = "overlay_pos_x_ratio"
    private const val KEY_OVERLAY_POS_Y_RATIO = "overlay_pos_y_ratio"
    private const val WAKE_LOCK_TAG = "EdgeCube:server"

    /** 点颜色绑定：固定表示运行状态（绿色）。 */
    const val DOT_SOURCE_STATUS = "status"
    /** 点颜色绑定：CPU 使用率。 */
    const val DOT_SOURCE_CPU = "cpu"
    /** 点颜色绑定：设备内存占用率。 */
    const val DOT_SOURCE_MEM = "mem"
    /** 点颜色绑定：服务端内存占设备总内存比例。 */
    const val DOT_SOURCE_SERVER_MEM = "serverMem"

    /** 监控数据刷新间隔（毫秒）。 */
    private const val REFRESH_INTERVAL_MS = 2000L

    private val mainHandler = Handler(Looper.getMainLooper())

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    private var overlayView: View? = null
    private var dotView: View? = null
    private var labelView: TextView? = null
    private var refreshTick: Runnable? = null

    /** 服务端是否处于运行期（acquire 与 release 之间）。 */
    private var active = false
    private var instanceName: String = ""

    /** 当前前台 Activity 的弱引用，用于防息屏（FLAG_KEEP_SCREEN_ON 须挂在窗口上）。 */
    private var activityRef: WeakReference<Activity>? = null

    /** 悬浮窗展示与交互设置。 */
    data class OverlayOptions(
        /** 文本区显示 CPU 使用率。 */
        val showCpu: Boolean,
        /** 文本区显示设备内存占用率。 */
        val showMem: Boolean,
        /** 文本区显示服务端内存占用（绝对值）。 */
        val showServerMem: Boolean,
        /** 仅显示状态点（忽略文本区所有内容）。 */
        val dotOnly: Boolean,
        /** 点颜色绑定来源：DOT_SOURCE_* 之一。 */
        val dotColorSource: String,
        /** 穿透模式：悬浮窗不响应触摸，交互直接落到下层应用。 */
        val clickThrough: Boolean,
    ) {
        /** 是否需要周期读取系统数据（有监控项或点颜色绑定占用率）。 */
        val needsStats: Boolean
            get() = (!dotOnly && (showCpu || showMem || showServerMem)) ||
                dotColorSource != DOT_SOURCE_STATUS

        fun toMap(): Map<String, Any> = mapOf(
            "showCpu" to showCpu,
            "showMem" to showMem,
            "showServerMem" to showServerMem,
            "dotOnly" to dotOnly,
            "dotColorSource" to dotColorSource,
            "clickThrough" to clickThrough,
        )
    }

    // —— 开关读写（原生 SharedPreferences）——

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** 锁屏保活（WakeLock + WifiLock）是否启用；默认启用。 */
    fun isWakeLockEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_WAKE_LOCK, true)

    /** 防息屏是否启用；默认关闭。仅在服务端运行期间生效。 */
    fun isKeepScreenOnEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_KEEP_SCREEN_ON, false)

    /** 状态悬浮窗是否启用；默认关闭（需要用户授予悬浮窗权限）。 */
    fun isOverlayEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_OVERLAY, false)

    /** 读取悬浮窗展示与交互设置。 */
    fun overlayOptions(context: Context): OverlayOptions {
        val p = prefs(context)
        return OverlayOptions(
            showCpu = p.getBoolean(KEY_OVERLAY_SHOW_CPU, false),
            showMem = p.getBoolean(KEY_OVERLAY_SHOW_MEM, false),
            showServerMem = p.getBoolean(KEY_OVERLAY_SHOW_SERVER_MEM, false),
            dotOnly = p.getBoolean(KEY_OVERLAY_DOT_ONLY, false),
            dotColorSource =
                p.getString(KEY_OVERLAY_DOT_COLOR_SOURCE, DOT_SOURCE_STATUS)
                    ?: DOT_SOURCE_STATUS,
            clickThrough = p.getBoolean(KEY_OVERLAY_CLICK_THROUGH, false),
        )
    }

    /** 保存悬浮窗设置；悬浮窗正在显示时立即重建生效。 */
    @Synchronized
    fun setOverlayOptions(context: Context, map: Map<*, *>) {
        val editor = prefs(context).edit()
        (map["showCpu"] as? Boolean)?.let { editor.putBoolean(KEY_OVERLAY_SHOW_CPU, it) }
        (map["showMem"] as? Boolean)?.let { editor.putBoolean(KEY_OVERLAY_SHOW_MEM, it) }
        (map["showServerMem"] as? Boolean)?.let {
            editor.putBoolean(KEY_OVERLAY_SHOW_SERVER_MEM, it)
        }
        (map["dotOnly"] as? Boolean)?.let { editor.putBoolean(KEY_OVERLAY_DOT_ONLY, it) }
        (map["dotColorSource"] as? String)?.let {
            editor.putString(KEY_OVERLAY_DOT_COLOR_SOURCE, it)
        }
        (map["clickThrough"] as? Boolean)?.let {
            editor.putBoolean(KEY_OVERLAY_CLICK_THROUGH, it)
        }
        editor.apply()
        if (active && isOverlayEnabled(context)) {
            // 重建悬浮窗应用新样式（位置由 lastX/lastY 保留）。
            val app = context.applicationContext
            mainHandler.post {
                hideOverlay(app)
                if (canDrawOverlays(app)) showOverlay(app)
            }
        }
    }

    /** 设置锁屏保活开关；服务端运行中立即生效。 */
    @Synchronized
    fun setWakeLockEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_WAKE_LOCK, enabled).apply()
        if (active) applyLocks(context, enabled)
    }

    /** 设置防息屏开关；服务端运行中立即生效。 */
    @Synchronized
    fun setKeepScreenOnEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_KEEP_SCREEN_ON, enabled).apply()
        if (active) applyKeepScreenOn(context, enabled)
    }

    /**
     * 绑定当前前台 Activity，用于防息屏（FLAG_KEEP_SCREEN_ON 须挂在窗口上）。
     * 由 [MainActivity.onResume] 调用；若服务端正在运行且已启用防息屏，立即应用。
     * Activity 销毁后弱引用自动失效，无需显式解绑。
     */
    @Synchronized
    fun bindActivity(activity: Activity) {
        activityRef = WeakReference(activity)
        if (active && isKeepScreenOnEnabled(activity)) applyKeepScreenOn(activity, true)
    }

    /** 设置状态悬浮窗开关；服务端运行中立即生效。 */
    @Synchronized
    fun setOverlayEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_OVERLAY, enabled).apply()
        if (active) applyOverlay(context, enabled)
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
        applyOverlay(context, isOverlayEnabled(context))
        applyKeepScreenOn(context, isKeepScreenOnEnabled(context))
    }

    /** 服务端停止：释放全部锁并移除悬浮窗。 */
    @Synchronized
    fun release(context: Context) {
        active = false
        applyLocks(context, false)
        applyOverlay(context, false)
        applyKeepScreenOn(context, false)
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
     * 在当前前台 Activity 的窗口上添加/移除 [WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON]。
     * 仅在该窗口可见时生效（App 在前台时），无需额外权限。
     * 服务端停止或开关关闭时清除标志，恢复正常息屏。
     */
    private fun applyKeepScreenOn(context: Context, enabled: Boolean) {
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

    private fun applyOverlay(context: Context, enabled: Boolean) {
        val app = context.applicationContext
        // WindowManager 只能在主线程操作。
        mainHandler.post {
            if (enabled) {
                if (overlayView == null && canDrawOverlays(app)) showOverlay(app)
            } else {
                hideOverlay(app)
            }
        }
    }

    /** 构建并挂载胶囊形状态悬浮窗（状态点 + 可选文本，可拖动，点击回到 App）。 */
    private fun showOverlay(app: Context) {
        val opts = overlayOptions(app)
        val wm = app.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val density = app.resources.displayMetrics.density
        fun dp(v: Float) = (v * density).roundToInt()

        // 仅状态点模式下点稍大，便于辨认颜色。
        val dotSize = if (opts.dotOnly) dp(12f) else dp(8f)
        val dot = View(app).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xFF4CAF50.toInt())
            }
            layoutParams = LinearLayout.LayoutParams(dotSize, dotSize).apply {
                if (!opts.dotOnly) marginEnd = dp(6f)
            }
        }
        dotView = dot

        // 匿名子类：悬浮窗独立于 Activity，转屏时经 ViewRootImpl 收到配置变化
        // 回调，据此按保存的比例把窗口重摆到新屏幕尺寸下的等价位置。
        val capsule = object : LinearLayout(app) {
            override fun onConfigurationChanged(newConfig: Configuration?) {
                super.onConfigurationChanged(newConfig)
                mainHandler.post {
                    val view = overlayView ?: return@post
                    if (view !== this) return@post
                    val params = view.layoutParams as? WindowManager.LayoutParams
                        ?: return@post
                    if (applySavedPosition(app, view, params)) {
                        try {
                            wm.updateViewLayout(view, params)
                        } catch (_: Exception) {
                        }
                    }
                }
            }
        }.apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable().apply {
                cornerRadius = dp(16f).toFloat()
                setColor(0xE6303030.toInt())
            }
            addView(dot)
        }
        if (opts.dotOnly) {
            capsule.setPadding(dp(6f), dp(6f), dp(6f), dp(6f))
            labelView = null
        } else {
            capsule.setPadding(dp(12f), dp(6f), dp(12f), dp(6f))
            val label = TextView(app).apply {
                text = if (instanceName.isEmpty()) "EdgeCube" else instanceName
                setTextColor(Color.WHITE)
                textSize = 12f
                maxLines = 1
            }
            labelView = label
            capsule.addView(label)
        }

        @Suppress("DEPRECATION")
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            WindowManager.LayoutParams.TYPE_PHONE
        }
        // 穿透模式：NOT_TOUCHABLE 使全部触摸事件直接落到下层应用。
        var flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        if (opts.clickThrough) {
            flags = flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            flags,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(12f)
            y = dp(96f)
        }
        // 有保存位置则按比例还原（预量测取得窗口尺寸，避免先显示默认位置再跳动）。
        capsule.measure(
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
        )
        applySavedPosition(app, capsule, params)

        if (!opts.clickThrough) {
            attachDragHandler(app, wm, capsule, params)
        }

        try {
            wm.addView(capsule, params)
            overlayView = capsule
            if (opts.needsStats) startStatsRefresh(app, opts)
        } catch (_: Exception) {
            // 权限被收回或窗口令牌异常：静默降级，不影响服务端运行。
            overlayView = null
            dotView = null
            labelView = null
        }
    }

    /**
     * 把保存的位置比例换算成当前屏幕下的坐标写入 [params]；无保存位置返回 false。
     * 比例基于「可移动范围」（屏幕尺寸减窗口尺寸），并夹取到屏幕内。
     */
    private fun applySavedPosition(
        app: Context,
        view: View,
        params: WindowManager.LayoutParams,
    ): Boolean {
        val p = prefs(app)
        if (!p.contains(KEY_OVERLAY_POS_X_RATIO)) return false
        val rx = p.getFloat(KEY_OVERLAY_POS_X_RATIO, 0f)
        val ry = p.getFloat(KEY_OVERLAY_POS_Y_RATIO, 0f)
        val dm = app.resources.displayMetrics
        val w = if (view.width > 0) view.width else view.measuredWidth
        val h = if (view.height > 0) view.height else view.measuredHeight
        val maxX = (dm.widthPixels - w).coerceAtLeast(0)
        val maxY = (dm.heightPixels - h).coerceAtLeast(0)
        params.x = (rx * maxX).roundToInt().coerceIn(0, maxX)
        params.y = (ry * maxY).roundToInt().coerceIn(0, maxY)
        return true
    }

    /** 把当前位置按可移动范围换算成比例保存（拖动结束时调用）。 */
    private fun savePosition(
        app: Context,
        view: View,
        params: WindowManager.LayoutParams,
    ) {
        val dm = app.resources.displayMetrics
        val maxX = (dm.widthPixels - view.width).coerceAtLeast(1)
        val maxY = (dm.heightPixels - view.height).coerceAtLeast(1)
        prefs(app).edit()
            .putFloat(
                KEY_OVERLAY_POS_X_RATIO,
                (params.x.toFloat() / maxX).coerceIn(0f, 1f),
            )
            .putFloat(
                KEY_OVERLAY_POS_Y_RATIO,
                (params.y.toFloat() / maxY).coerceIn(0f, 1f),
            )
            .apply()
    }

    /** 拖动移动；位移小于 touch slop 视为点击，回到 App 主界面。 */
    private fun attachDragHandler(
        app: Context,
        wm: WindowManager,
        view: View,
        params: WindowManager.LayoutParams,
    ) {
        val slop = ViewConfiguration.get(app).scaledTouchSlop
        view.setOnTouchListener(object : View.OnTouchListener {
            private var startX = 0
            private var startY = 0
            private var downRawX = 0f
            private var downRawY = 0f

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        startX = params.x
                        startY = params.y
                        downRawX = event.rawX
                        downRawY = event.rawY
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        params.x = startX + (event.rawX - downRawX).roundToInt()
                        params.y = startY + (event.rawY - downRawY).roundToInt()
                        try {
                            wm.updateViewLayout(v, params)
                        } catch (_: Exception) {
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        val moved = abs(event.rawX - downRawX) > slop ||
                            abs(event.rawY - downRawY) > slop
                        if (moved) {
                            // 拖动结束：按屏幕比例持久化位置。
                            savePosition(app, v, params)
                        } else {
                            v.performClick()
                            try {
                                app.startActivity(
                                    Intent(app, MainActivity::class.java).addFlags(
                                        Intent.FLAG_ACTIVITY_NEW_TASK or
                                            Intent.FLAG_ACTIVITY_SINGLE_TOP,
                                    ),
                                )
                            } catch (_: Exception) {
                            }
                        }
                        return true
                    }
                }
                return false
            }
        })
    }

    private fun hideOverlay(app: Context) {
        stopStatsRefresh()
        val view = overlayView ?: return
        overlayView = null
        dotView = null
        labelView = null
        try {
            val wm = app.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            wm.removeView(view)
        } catch (_: Exception) {
        }
    }

    // —— 监控数据周期刷新 ——

    private fun startStatsRefresh(app: Context, opts: OverlayOptions) {
        stopStatsRefresh()
        val tick = object : Runnable {
            override fun run() {
                if (overlayView == null) return
                // /proc 读取（proot 模式含全 /proc 扫描）放后台线程，避免卡 UI。
                thread(name = "overlay-stats") {
                    val stats = collectStats(app, opts)
                    mainHandler.post {
                        if (overlayView != null) applyStats(opts, stats)
                    }
                }
                mainHandler.postDelayed(this, REFRESH_INTERVAL_MS)
            }
        }
        refreshTick = tick
        mainHandler.post(tick)
    }

    private fun stopStatsRefresh() {
        refreshTick?.let { mainHandler.removeCallbacks(it) }
        refreshTick = null
    }

    /** 一次监控采样：CPU%、设备内存%、服务端内存 MB 与其占总内存比例。 */
    private data class Stats(
        val cpuPercent: Double,       // -1 表示不可用
        val memPercent: Double,       // -1 表示不可用
        val serverMemMb: Long?,       // null 表示服务端未运行/不可读
        val serverMemPercent: Double, // -1 表示不可用
    )

    private fun collectStats(app: Context, opts: OverlayOptions): Stats {
        val needCpu = opts.showCpu || opts.dotColorSource == DOT_SOURCE_CPU
        val needMem = opts.showMem || opts.dotColorSource == DOT_SOURCE_MEM
        val needServer =
            opts.showServerMem || opts.dotColorSource == DOT_SOURCE_SERVER_MEM

        val cpu = if (needCpu) SystemStats.cpuUsage() else -1.0

        var memPercent = -1.0
        var totalMb = 0L
        if (needMem || needServer) {
            val mem = SystemStats.memInfo(app)
            totalMb = mem[0]
            if (needMem && totalMb > 0) {
                memPercent = mem[1].toDouble() / totalMb.toDouble() * 100.0
            }
        }

        var serverMb: Long? = null
        var serverPercent = -1.0
        if (needServer) {
            val manager = try {
                ServerProcessManager.getInstance(app)
            } catch (_: Exception) {
                null
            }
            serverMb = manager?.let {
                try {
                    SystemStats.serverMemMb(it)
                } catch (_: Exception) {
                    null
                }
            }
            if (serverMb != null) {
                // 与服务器页的「服务端内存」一致：占用率按配置的 JVM 最大堆
                // （-Xmx）计算；未配置 -Xmx（PHP/proot 等）回退按设备总内存。
                val maxHeap = manager?.maxHeapMb ?: -1
                val denominator = if (maxHeap > 0) maxHeap else totalMb
                if (denominator > 0) {
                    serverPercent =
                        serverMb.toDouble() / denominator.toDouble() * 100.0
                }
            }
        }
        return Stats(cpu, memPercent, serverMb, serverPercent)
    }

    /** 把采样结果应用到点颜色与文本。 */
    private fun applyStats(opts: OverlayOptions, stats: Stats) {
        // 点颜色：绑定占用率时按阈值分档；数据不可用为灰色。
        val percent = when (opts.dotColorSource) {
            DOT_SOURCE_CPU -> stats.cpuPercent
            DOT_SOURCE_MEM -> stats.memPercent
            DOT_SOURCE_SERVER_MEM -> stats.serverMemPercent
            else -> null // status：保持绿色，不更新。
        }
        if (percent != null) {
            // 分档阈值与服务器页监控卡一致（<65 正常 / 65–85 偏高 / ≥85 过高）。
            val color = when {
                percent < 0 -> 0xFF9E9E9E.toInt()   // 数据不可用：灰
                percent < 65 -> 0xFF4CAF50.toInt()  // 正常：绿
                percent < 85 -> 0xFFFF9800.toInt()  // 偏高：橙
                else -> 0xFFF44336.toInt()          // 过高：红
            }
            (dotView?.background as? GradientDrawable)?.setColor(color)
        }

        // 文本：按启用的监控项拼接；均未启用则维持实例名不动。
        val label = labelView ?: return
        val parts = mutableListOf<String>()
        if (opts.showCpu) {
            parts += if (stats.cpuPercent < 0) {
                "CPU --"
            } else {
                "CPU ${stats.cpuPercent.roundToInt()}%"
            }
        }
        if (opts.showMem) {
            parts += if (stats.memPercent < 0) {
                "MEM --"
            } else {
                "MEM ${stats.memPercent.roundToInt()}%"
            }
        }
        if (opts.showServerMem) {
            val mb = stats.serverMemMb
            parts += when {
                mb == null -> "SRV --"
                mb >= 1024 -> "SRV %.1fG".format(mb / 1024.0)
                else -> "SRV ${mb}M"
            }
        }
        if (parts.isNotEmpty()) label.text = parts.joinToString("  ")
    }
}

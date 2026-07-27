package com.venti1112.edgecube.keepalive

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import com.venti1112.edgecube.MainActivity
import com.venti1112.edgecube.server.ServerProcessManager
import com.venti1112.edgecube.server.SystemStats
import kotlin.concurrent.thread
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * 状态悬浮窗：胶囊形（状态点 + 可选文本），可拖动，点击回到 App。
 *
 * 除随时展示运行状态外，部分 ROM 会将有可见悬浮窗的应用视为「用户可感知」，
 * 进一步降低被后台清理的概率。展示与交互设置见 [OverlayOptions]；位置按
 * 「可移动范围的比例」持久化（见 [KeepAlivePrefs]），转屏/换分辨率后还原到
 * 等价位置。
 *
 * 所有方法必须在主线程调用（WindowManager 限制），由 [KeepAliveManager] 保证。
 */
internal object StatusOverlay {

    /** 监控数据刷新间隔（毫秒）。 */
    private const val REFRESH_INTERVAL_MS = 2000L

    private val mainHandler = Handler(Looper.getMainLooper())

    private var overlayView: View? = null
    private var dotView: View? = null
    private var labelView: TextView? = null
    private var refreshTick: Runnable? = null

    /** 悬浮窗当前是否已挂载。 */
    val isShowing: Boolean get() = overlayView != null

    /** 构建并挂载悬浮窗；[instanceName] 用作无监控项时的文本。 */
    fun show(app: Context, instanceName: String) {
        val opts = KeepAlivePrefs.overlayOptions(app)
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
                text = instanceName.ifEmpty { "EdgeCube" }
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

    /** 移除悬浮窗（未挂载时为空操作）。 */
    fun hide(app: Context) {
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

    // —— 位置持久化 ——

    /**
     * 把保存的位置比例换算成当前屏幕下的坐标写入 [params]；无保存位置返回 false。
     * 比例基于「可移动范围」（屏幕尺寸减窗口尺寸），并夹取到屏幕内。
     */
    private fun applySavedPosition(
        app: Context,
        view: View,
        params: WindowManager.LayoutParams,
    ): Boolean {
        val (rx, ry) = KeepAlivePrefs.overlayPositionRatio(app) ?: return false
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
        KeepAlivePrefs.setOverlayPositionRatio(
            app,
            params.x.toFloat() / maxX,
            params.y.toFloat() / maxY,
        )
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
        val needCpu = opts.showCpu || opts.dotColorSource == OverlayOptions.DOT_SOURCE_CPU
        val needMem = opts.showMem || opts.dotColorSource == OverlayOptions.DOT_SOURCE_MEM
        val needServer =
            opts.showServerMem || opts.dotColorSource == OverlayOptions.DOT_SOURCE_SERVER_MEM

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
            OverlayOptions.DOT_SOURCE_CPU -> stats.cpuPercent
            OverlayOptions.DOT_SOURCE_MEM -> stats.memPercent
            OverlayOptions.DOT_SOURCE_SERVER_MEM -> stats.serverMemPercent
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

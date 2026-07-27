package com.venti1112.edgecube.keepalive

import android.content.Context
import android.content.SharedPreferences

/**
 * 保活相关开关与悬浮窗设置的持久化。
 *
 * 存放在原生 SharedPreferences（而非 Dart 侧配置文件）：acquire 发生在
 * [com.venti1112.edgecube.server.ServerService] 的原生启动路径上，即使 Flutter
 * 引擎被回收也须能同步读取。
 */
internal object KeepAlivePrefs {

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

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** 锁屏保活（WakeLock + WifiLock）是否启用；默认启用。 */
    fun wakeLockEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_WAKE_LOCK, true)

    fun setWakeLockEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_WAKE_LOCK, enabled).apply()
    }

    /** 防息屏是否启用；默认关闭。仅在服务端运行期间生效。 */
    fun keepScreenOnEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_KEEP_SCREEN_ON, false)

    fun setKeepScreenOnEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_KEEP_SCREEN_ON, enabled).apply()
    }

    /** 状态悬浮窗是否启用；默认关闭（需要用户授予悬浮窗权限）。 */
    fun overlayEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_OVERLAY, false)

    fun setOverlayEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_OVERLAY, enabled).apply()
    }

    /** 读取悬浮窗展示与交互设置。 */
    fun overlayOptions(context: Context): OverlayOptions {
        val p = prefs(context)
        return OverlayOptions(
            showCpu = p.getBoolean(KEY_OVERLAY_SHOW_CPU, false),
            showMem = p.getBoolean(KEY_OVERLAY_SHOW_MEM, false),
            showServerMem = p.getBoolean(KEY_OVERLAY_SHOW_SERVER_MEM, false),
            dotOnly = p.getBoolean(KEY_OVERLAY_DOT_ONLY, false),
            dotColorSource =
                p.getString(KEY_OVERLAY_DOT_COLOR_SOURCE, OverlayOptions.DOT_SOURCE_STATUS)
                    ?: OverlayOptions.DOT_SOURCE_STATUS,
            clickThrough = p.getBoolean(KEY_OVERLAY_CLICK_THROUGH, false),
        )
    }

    /** 保存悬浮窗设置（来自 Dart 侧的 Map，仅覆盖出现的字段）。 */
    fun putOverlayOptions(context: Context, map: Map<*, *>) {
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
    }

    /** 读取保存的悬浮窗位置比例 (x, y)；从未保存过返回 null。 */
    fun overlayPositionRatio(context: Context): Pair<Float, Float>? {
        val p = prefs(context)
        if (!p.contains(KEY_OVERLAY_POS_X_RATIO)) return null
        return Pair(
            p.getFloat(KEY_OVERLAY_POS_X_RATIO, 0f),
            p.getFloat(KEY_OVERLAY_POS_Y_RATIO, 0f),
        )
    }

    /** 保存悬浮窗位置比例（拖动结束时调用）。 */
    fun setOverlayPositionRatio(context: Context, xRatio: Float, yRatio: Float) {
        prefs(context).edit()
            .putFloat(KEY_OVERLAY_POS_X_RATIO, xRatio.coerceIn(0f, 1f))
            .putFloat(KEY_OVERLAY_POS_Y_RATIO, yRatio.coerceIn(0f, 1f))
            .apply()
    }
}

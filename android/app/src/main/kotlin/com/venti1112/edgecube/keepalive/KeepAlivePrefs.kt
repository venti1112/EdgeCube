package com.venti1112.edgecube.keepalive

import android.content.Context
import android.content.SharedPreferences
import java.io.File

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

    // —— 桌面小组件快照（由 Dart 侧 ServerController 经 widget 通道写入， ——
    //   —— 供 AppWidgetProvider 渲染；服务端停止时也写最后一次状态）   ——
    // 与悬浮窗 key 同库：原生保活路径已持有 SharedPreferences 句柄，复用即可。
    private const val KEY_WIDGET_ENABLED = "widget_enabled"
    private const val KEY_WIDGET_SHOW_INSTANCE = "widget_show_instance"
    private const val KEY_WIDGET_SHOW_PLAYERS = "widget_show_players"
    private const val KEY_WIDGET_SHOW_ADDRESS = "widget_show_address"
    private const val KEY_WIDGET_SHOW_STATS = "widget_show_stats"
    private const val KEY_WIDGET_SHOW_BUTTONS = "widget_show_buttons"

    // 小组件外观（背景/文字颜色与不透明度，由 Dart 侧设置页写入）
    private const val KEY_WIDGET_BG_COLOR = "widget_bg_color"          // ARGB int，alpha 忽略
    private const val KEY_WIDGET_BG_OPACITY = "widget_bg_opacity"      // 0..100
    private const val KEY_WIDGET_TEXT_COLOR = "widget_text_color"      // ARGB int，alpha 忽略
    private const val KEY_WIDGET_TEXT_OPACITY = "widget_text_opacity"  // 0..100

    // 状态快照（Dart 侧每隔约 1s 或状态变化时写入）
    private const val KEY_SNAP_STATUS = "snap_status"          // stopped|preparing|starting|running|stopping
    private const val KEY_SNAP_INSTANCE_NAME = "snap_instance_name"
    private const val KEY_SNAP_PLAYER_COUNT = "snap_player_count"
    private const val KEY_SNAP_SERVER_PORT = "snap_server_port"
    private const val KEY_SNAP_PUBLIC_ADDRESS = "snap_public_address"
    private const val KEY_SNAP_LOCAL_ADDRESS = "snap_local_address"
    private const val KEY_SNAP_CPU = "snap_cpu"                 // -1 表示不可用
    private const val KEY_SNAP_MEM = "snap_mem"                  // -1 表示不可用
    private const val KEY_SNAP_SERVER_MEM = "snap_server_mem"   // MB，-1 表示不可用
    private const val KEY_SNAP_TIMESTAMP = "snap_timestamp"     // ms，最后一次写入时间
    private const val KEY_SNAP_PID = "snap_pid"                 // 服务端进程 PID，-1 表示未运行
    // 注意：PID 仅用于「App 进程被杀死后重启」时校验服务端子进程是否还活着
    // （同 UID 孤儿进程可能存活）；不用于杀进程（杀进程走 ServerProcessManager）。

    // 最近一次启动参数快照（WidgetProvider 用以无引擎启动）
    private const val KEY_LAST_INSTANCE_ID = "last_instance_id"
    private const val KEY_LAST_INSTANCE_NAME = "last_instance_name"
    private const val KEY_LAST_WORKING_DIR = "last_working_dir"
    private const val KEY_LAST_RUNTIME_ID = "last_runtime_id"
    private const val KEY_LAST_RUNTIME = "last_runtime"           // java|php|proot
    private const val KEY_LAST_RUNTIME_ARGS = "last_runtime_args" // \u241f 分隔（NUL 在 prefs 中受限）
    private const val KEY_LAST_PROGRAM_ARGS = "last_program_args"
    private const val KEY_LAST_COMPAT_MODE = "last_compat_mode"
    private const val KEY_LAST_DIRECT_EXECUTE = "last_direct_execute"
    private const val KEY_LAST_LINE_ENDING = "last_line_ending"

    /** 单元分隔符：用于在 SharedPreferences 中安全存储多行字符串数组。 */
    private const val ARGS_SEP = "\u241f"

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

    // ──────────────────────────────────────────────────────────────────────
    // 桌面小组件设置（用户在「设置 / 桌面小组件」页内做的选择）
    // ──────────────────────────────────────────────────────────────────────

    /** 桌面小组件总开关；默认关闭。 */
    fun widgetEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_WIDGET_ENABLED, false)

    fun setWidgetEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_WIDGET_ENABLED, enabled).apply()
    }

    /** 读取小组件展示选项。 */
    fun widgetDisplayOptions(context: Context): WidgetDisplayOptions =
        WidgetDisplayOptions(
            showInstance = prefs(context).getBoolean(KEY_WIDGET_SHOW_INSTANCE, true),
            showPlayers = prefs(context).getBoolean(KEY_WIDGET_SHOW_PLAYERS, true),
            showAddress = prefs(context).getBoolean(KEY_WIDGET_SHOW_ADDRESS, true),
            showStats = prefs(context).getBoolean(KEY_WIDGET_SHOW_STATS, false),
            showButtons = prefs(context).getBoolean(KEY_WIDGET_SHOW_BUTTONS, true),
        )

    /** 由 Dart 侧一次性写入展示选项 Map（仅覆盖出现的字段）。 */
    fun putWidgetDisplayOptions(context: Context, map: Map<*, *>) {
        val editor = prefs(context).edit()
        (map["showInstance"] as? Boolean)?.let { editor.putBoolean(KEY_WIDGET_SHOW_INSTANCE, it) }
        (map["showPlayers"] as? Boolean)?.let { editor.putBoolean(KEY_WIDGET_SHOW_PLAYERS, it) }
        (map["showAddress"] as? Boolean)?.let { editor.putBoolean(KEY_WIDGET_SHOW_ADDRESS, it) }
        (map["showStats"] as? Boolean)?.let { editor.putBoolean(KEY_WIDGET_SHOW_STATS, it) }
        (map["showButtons"] as? Boolean)?.let { editor.putBoolean(KEY_WIDGET_SHOW_BUTTONS, it) }
        editor.apply()
    }

    /** 读取小组件外观设置（背景/文字颜色 + 各自不透明度）。 */
    fun widgetAppearance(context: Context): WidgetAppearance {
        val p = prefs(context)
        return WidgetAppearance(
            bgColor = p.getInt(KEY_WIDGET_BG_COLOR, WidgetAppearance.DEFAULT_BG_COLOR),
            bgOpacity = p.getInt(KEY_WIDGET_BG_OPACITY, 100).coerceIn(0, 100),
            textColor = p.getInt(KEY_WIDGET_TEXT_COLOR, WidgetAppearance.DEFAULT_TEXT_COLOR),
            textOpacity = p.getInt(KEY_WIDGET_TEXT_OPACITY, 100).coerceIn(0, 100),
        )
    }

    /** 由 Dart 侧写入外观设置 Map（仅覆盖出现的字段）。 */
    fun putWidgetAppearance(context: Context, map: Map<*, *>) {
        val editor = prefs(context).edit()
        (map["bgColor"] as? Int)?.let { editor.putInt(KEY_WIDGET_BG_COLOR, it) }
        (map["bgOpacity"] as? Int)?.let { editor.putInt(KEY_WIDGET_BG_OPACITY, it) }
        (map["textColor"] as? Int)?.let { editor.putInt(KEY_WIDGET_TEXT_COLOR, it) }
        (map["textOpacity"] as? Int)?.let { editor.putInt(KEY_WIDGET_TEXT_OPACITY, it) }
        editor.apply()
    }

    // ──────────────────────────────────────────────────────────────────────
    // 状态快照（Dart 侧缓存一份，使 AppWidgetProvider 渲染时无需走 Flutter 引擎)
    // ──────────────────────────────────────────────────────────────────────

    /** 读取小组件渲染需要的完整状态快照。 */
    fun widgetSnapshot(context: Context): WidgetSnapshot {
        val p = prefs(context)
        return WidgetSnapshot(
            status = p.getString(KEY_SNAP_STATUS, "stopped") ?: "stopped",
            instanceName = p.getString(KEY_SNAP_INSTANCE_NAME, "") ?: "",
            playerCount = p.getInt(KEY_SNAP_PLAYER_COUNT, 0),
            serverPort = p.getInt(KEY_SNAP_SERVER_PORT, 0),
            publicAddress = p.getString(KEY_SNAP_PUBLIC_ADDRESS, null),
            localAddress = p.getString(KEY_SNAP_LOCAL_ADDRESS, null),
            cpu = p.getFloat(KEY_SNAP_CPU, -1f),
            mem = p.getFloat(KEY_SNAP_MEM, -1f),
            serverMem = p.getFloat(KEY_SNAP_SERVER_MEM, -1f),
            timestamp = p.getLong(KEY_SNAP_TIMESTAMP, 0L),
        )
    }

    /** Dart 侧/cache 缓存的状态写入。每字段 null 时跳过，便于增量更新。 */
    fun putWidgetSnapshot(
        context: Context,
        status: String? = null,
        instanceName: String? = null,
        playerCount: Int? = null,
        serverPort: Int? = null,
        publicAddress: String? = null,
        localAddress: String? = null,
        cpu: Float? = null,
        mem: Float? = null,
        serverMem: Float? = null,
        pid: Int? = null,
    ) {
        val editor = prefs(context).edit()
        if (status != null) editor.putString(KEY_SNAP_STATUS, status)
        if (instanceName != null) editor.putString(KEY_SNAP_INSTANCE_NAME, instanceName)
        if (playerCount != null) editor.putInt(KEY_SNAP_PLAYER_COUNT, playerCount.coerceAtLeast(0))
        if (serverPort != null) editor.putInt(KEY_SNAP_SERVER_PORT, serverPort)
        if (publicAddress != null) editor.putString(KEY_SNAP_PUBLIC_ADDRESS, publicAddress)
        if (localAddress != null) editor.putString(KEY_SNAP_LOCAL_ADDRESS, localAddress)
        if (cpu != null) editor.putFloat(KEY_SNAP_CPU, cpu)
        if (mem != null) editor.putFloat(KEY_SNAP_MEM, mem)
        if (serverMem != null) editor.putFloat(KEY_SNAP_SERVER_MEM, serverMem)
        if (pid != null) editor.putInt(KEY_SNAP_PID, pid)
        editor.putLong(KEY_SNAP_TIMESTAMP, System.currentTimeMillis())
        editor.apply()
    }

    /** 清空状态快照为「已停止」（Dart 侧停止时由 ServerProcessManager 调用）。 */
    fun clearWidgetSnapshot(context: Context) {
        prefs(context).edit()
            .putString(KEY_SNAP_STATUS, "stopped")
            .putInt(KEY_SNAP_PLAYER_COUNT, 0)
            .putInt(KEY_SNAP_SERVER_PORT, 0)
            .remove(KEY_SNAP_PUBLIC_ADDRESS)
            .remove(KEY_SNAP_LOCAL_ADDRESS)
            .putFloat(KEY_SNAP_CPU, -1f)
            .putFloat(KEY_SNAP_MEM, -1f)
            .putFloat(KEY_SNAP_SERVER_MEM, -1f)
            .remove(KEY_SNAP_PID)
            .putLong(KEY_SNAP_TIMESTAMP, System.currentTimeMillis())
            .apply()
    }

    /**
     * App 进程被杀死后重启时校正小组件状态快照。
     *
     * 快照更新依赖 App 进程内的 ServerProcessManager 回调；进程被直接杀掉时
     * 回调没有机会执行，快照可能停留在「运行中」。此时如果服务端子进程（同一
     * App 派生的 PTY 子进程）已随进程消亡，则把快照清成「已停止」；若子进程
     * 作为孤儿仍存活（同 UID 未被系统回收），则保留快照——服务端确实还在跑。
     *
     * 返回是否需要（已）刷新小组件。由 MainActivity.onCreate 在每次进程冷启动
     * 时调用。
     */
    fun correctSnapshotAfterProcessRestart(context: Context): Boolean {
        val p = prefs(context)
        val pid = p.getInt(KEY_SNAP_PID, -1)
        if (pid <= 0) return false
        // 进程仍存活（含被回收后 pid 复用为同 UID 进程的极端情况）：快照可信。
        if (isMyUidProcessAlive(pid)) return false
        clearWidgetSnapshot(context)
        return true
    }

    /**
     * 校验 pid 是否为本 UID 的存活进程。通过 /proc/<pid>/status 的 Uid 行判断：
     * 进程不存在或已被回收后 pid 复用为其它 UID 的进程时返回 false。
     */
    private fun isMyUidProcessAlive(pid: Int): Boolean = try {
        val uid = android.os.Process.myUid()
        File("/proc/$pid/status").readLines()
            .firstOrNull { it.startsWith("Uid:") }
            ?.substringAfter("Uid:")
            ?.trim()
            ?.split(Regex("\\s+"))
            ?.firstOrNull()
            ?.toIntOrNull() == uid
    } catch (_: Exception) {
        false
    }

    // ──────────────────────────────────────────────────────────────────────
    // 最近一次启动参数快照（用于无 Flutter 引擎时的自动启动）
    // ──────────────────────────────────────────────────────────────────────

    /** 读取最近一次启动参数；未运行过服务端时 [LastStartArgs.instanceId] 为 null。 */
    fun lastStartArgs(context: Context): LastStartArgs {
        val p = prefs(context)
        val id = p.getString(KEY_LAST_INSTANCE_ID, null) ?: return LastStartArgs(null)
        val runtime = p.getString(KEY_LAST_RUNTIME, null) ?: "java"
        val runtimeArgsStr = p.getString(KEY_LAST_RUNTIME_ARGS, null) ?: ""
        val programArgsStr = p.getString(KEY_LAST_PROGRAM_ARGS, null) ?: ""
        val lineEnding = p.getString(KEY_LAST_LINE_ENDING, null) ?: "\n"
        return LastStartArgs(
            instanceId = id,
            instanceName = p.getString(KEY_LAST_INSTANCE_NAME, null) ?: id,
            workingDir = p.getString(KEY_LAST_WORKING_DIR, null),
            runtimeId = p.getString(KEY_LAST_RUNTIME_ID, null),
            runtime = runtime,
            runtimeArgs = runtimeArgsStr.split(ARGS_SEP).filter { it.isNotEmpty() },
            programArgs = programArgsStr.split(ARGS_SEP).filter { it.isNotEmpty() },
            compatMode = p.getBoolean(KEY_LAST_COMPAT_MODE, false),
            directExecute = p.getBoolean(KEY_LAST_DIRECT_EXECUTE, false),
            lineEnding = lineEnding,
        )
    }

    /** 保存最近一次启动参数（供 WidgetProvider 与 BootReceiver 共用）。 */
    fun putLastStartArgs(
        context: Context,
        instanceId: String,
        instanceName: String,
        workingDir: String,
        runtimeId: String,
        runtime: String,
        runtimeArgs: List<String>,
        programArgs: List<String>,
        compatMode: Boolean,
        directExecute: Boolean,
        lineEnding: String,
    ) {
        val sep = ARGS_SEP
        prefs(context).edit()
            .putString(KEY_LAST_INSTANCE_ID, instanceId)
            .putString(KEY_LAST_INSTANCE_NAME, instanceName)
            .putString(KEY_LAST_WORKING_DIR, workingDir)
            .putString(KEY_LAST_RUNTIME_ID, runtimeId)
            .putString(KEY_LAST_RUNTIME, runtime)
            .putString(KEY_LAST_RUNTIME_ARGS, runtimeArgs.joinToString(sep))
            .putString(KEY_LAST_PROGRAM_ARGS, programArgs.joinToString(sep))
            .putBoolean(KEY_LAST_COMPAT_MODE, compatMode)
            .putBoolean(KEY_LAST_DIRECT_EXECUTE, directExecute)
            .putString(KEY_LAST_LINE_ENDING, lineEnding)
            .apply()
    }

    /** 清除最近一次启动参数（用户在设置里「忘记实例」时调用）。 */
    fun clearLastStartArgs(context: Context) {
        prefs(context).edit()
            .remove(KEY_LAST_INSTANCE_ID)
            .remove(KEY_LAST_INSTANCE_NAME)
            .remove(KEY_LAST_WORKING_DIR)
            .remove(KEY_LAST_RUNTIME_ID)
            .remove(KEY_LAST_RUNTIME)
            .remove(KEY_LAST_RUNTIME_ARGS)
            .remove(KEY_LAST_PROGRAM_ARGS)
            .remove(KEY_LAST_COMPAT_MODE)
            .remove(KEY_LAST_DIRECT_EXECUTE)
            .remove(KEY_LAST_LINE_ENDING)
            .apply()
    }
}

// ──────────────────────────────────────────────────────────────────────────
// 数据类
// ──────────────────────────────────────────────────────────────────────────

/** 小组件渲染时的状态快照。 */
data class WidgetSnapshot(
    /** stopped / preparing / starting / running / stopping */
    val status: String,
    val instanceName: String,
    val playerCount: Int,
    val serverPort: Int,
    /** 公网/外网地址，停止时为 null。 */
    val publicAddress: String?,
    /** 内网地址（无公网地址时兜底显示），未获取到时为 null。 */
    val localAddress: String?,
    /** CPU 占用率，-1 表示不可用。 */
    val cpu: Float,
    /** 设备内存占用率，-1 表示不可用。 */
    val mem: Float,
    /** 服务端内存占用（MB），-1 表示不可用。 */
    val serverMem: Float,
    /** 写入时间戳（ms）。 */
    val timestamp: Long,
) {
    val isRunning: Boolean get() = status == "running"
    val isBusy: Boolean get() = status == "preparing" || status == "starting" || status == "stopping"
}

/** 用户在设置页选择的展示选项。 */
data class WidgetDisplayOptions(
    val showInstance: Boolean,
    val showPlayers: Boolean,
    val showAddress: Boolean,
    val showStats: Boolean,
    val showButtons: Boolean,
)

/** 小组件外观：背景/文字颜色（ARGB，alpha 忽略）与各自不透明度（0..100）。 */
data class WidgetAppearance(
    val bgColor: Int,
    val bgOpacity: Int,
    val textColor: Int,
    val textOpacity: Int,
) {
    companion object {
        /** 默认背景：深灰胶囊（与原固定背景 #E6303030 一致）。 */
        const val DEFAULT_BG_COLOR = 0xFF303030.toInt()
        const val DEFAULT_TEXT_COLOR = 0xFFFFFFFF.toInt()
    }

    /** 背景最终颜色：把 [bgOpacity] 换算为 alpha。 */
    val bgArgb: Int get() = withOpacity(bgColor, bgOpacity)

    /** 文字最终颜色：把 [textOpacity] 换算为 alpha。 */
    val textArgb: Int get() = withOpacity(textColor, textOpacity)

    private fun withOpacity(argb: Int, opacity: Int): Int {
        val a = opacity.coerceIn(0, 100) * 255 / 100
        return (argb and 0x00FFFFFF) or (a shl 24)
    }
}

/** 缓存的最近一次启动参数。 */
data class LastStartArgs(
    val instanceId: String?,
    val instanceName: String? = null,
    val workingDir: String? = null,
    val runtimeId: String? = null,
    val runtime: String = "java",
    val runtimeArgs: List<String> = emptyList(),
    val programArgs: List<String> = emptyList(),
    val compatMode: Boolean = false,
    val directExecute: Boolean = false,
    val lineEnding: String = "\n",
) {
    /** 是否有完整的启动参数缓存。 */
    val isComplete: Boolean get() = instanceId != null &&
        workingDir != null && runtimeId != null
}

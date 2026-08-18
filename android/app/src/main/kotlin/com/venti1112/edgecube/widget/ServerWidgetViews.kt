package com.venti1112.edgecube.widget

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import com.venti1112.edgecube.MainActivity
import com.venti1112.edgecube.R
import com.venti1112.edgecube.keepalive.KeepAlivePrefs
import com.venti1112.edgecube.keepalive.WidgetDisplayOptions
import com.venti1112.edgecube.keepalive.WidgetSnapshot
import com.venti1112.edgecube.server.ServerProcessManager
import com.venti1112.edgecube.server.SystemStats
import kotlin.math.roundToInt

/**
 * 把 [KeepAlivePrefs.widgetSnapshot] 渲染为可供 AppWidgetManager 使用的 [RemoteViews]。
 *
 * 注意 RemoteViews 支持的视图与操作有限：
 * - 直接构造实例无法，只能通过 [RemoteViews]."setImageViewResource" / "setTextViewText"
 *   / "setOnClickPendingIntent" 等以 view id 寻址。
 * - 状态点用三张 drawable 之一（亮/橙/灰）切换图标资源即可。
 * - 按钮（启停）的 PendingIntent action 与 [ServerWidgetProvider] 的
 *   自定义 action 对齐。
 */
internal object ServerWidgetViews {

    fun build(context: Context): RemoteViews {
        val app = context.applicationContext
        val snap = KeepAlivePrefs.widgetSnapshot(app)
        val opts = KeepAlivePrefs.widgetDisplayOptions(app)
        val hasLast = KeepAlivePrefs.lastStartArgs(app).isComplete

        val views = RemoteViews(app.packageName, R.layout.widget_server)

        // 外观：背景/文字颜色与不透明度（用户可在设置页自定义）。
        // 注意 setBackgroundColor 会替换布局中的圆角背景资源；Android 12+ 的
        // 启动器会为小组件统一施加系统圆角遮罩，低版本上则为直角。
        val appearance = KeepAlivePrefs.widgetAppearance(app)
        views.setInt(R.id.widget_root, "setBackgroundColor", appearance.bgArgb)
        views.setTextColor(R.id.widget_title, appearance.textArgb)
        views.setTextColor(R.id.widget_subtitle, appearance.textArgb)

        // 状态点：按状态改变图标资源。
        val dotRes = when {
            snap.isRunning -> R.drawable.widget_dot_running
            snap.isBusy -> R.drawable.widget_dot_busy
            else -> R.drawable.widget_dot_stopped
        }
        views.setImageViewResource(R.id.widget_dot, dotRes)

        // 标题（首行）：实例名 / fallback 为「EdgeCube」。
        val titleText = if (opts.showInstance && snap.instanceName.isNotEmpty()) {
            snap.instanceName
        } else {
            app.getString(R.string.widget_default_title)
        }
        views.setTextViewText(R.id.widget_title, titleText)

        // 副标题（次行）：玩家数 + 公网地址 + CPU·MEM，按用户勾选项拼装。
        val subtitle = buildSubtitle(app, snap, opts)
        views.setTextViewText(R.id.widget_subtitle, subtitle)
        views.setViewVisibility(
            R.id.widget_subtitle,
            if (subtitle.isNullOrEmpty()) View.GONE else View.VISIBLE,
        )

        // 启停按钮：根据状态切换图标 + 设置 PendingIntent action。
        val isRunning = snap.isRunning
        val isBusy = snap.isBusy
        val running = ServerProcessManager.getInstance(app).isRunning
        val actionRes: Int
        val actionIntent: String
        val actionDesc: String
        when {
            isRunning || isBusy -> {
                actionRes = R.drawable.widget_button_stop
                actionIntent = ServerWidgetProvider.ACTION_STOP
                actionDesc = app.getString(R.string.widget_action_stop)
            }
            hasLast -> {
                actionRes = R.drawable.widget_button_start
                actionIntent = ServerWidgetProvider.ACTION_START
                actionDesc = app.getString(R.string.widget_action_start)
            }
            else -> {
                // 无缓存启动参数：按钮退化为「打开 App」。
                actionRes = R.drawable.widget_button_start
                actionIntent = ServerWidgetProvider.ACTION_OPEN
                actionDesc = app.getString(R.string.widget_action_start)
            }
        }
        views.setImageViewResource(R.id.widget_action_button, actionRes)
        views.setContentDescription(R.id.widget_action_button, actionDesc)
        // 启停按钮图标跟随文字颜色，保持整体一致。
        views.setInt(R.id.widget_action_button, "setColorFilter", appearance.textArgb)
        if (opts.showButtons) {
            views.setViewVisibility(R.id.widget_action_button, View.VISIBLE)
            views.setOnClickPendingIntent(
                R.id.widget_action_button,
                pendingAction(app, ServerWidgetProvider::class.java, actionIntent, 1),
            )
        } else {
            views.setViewVisibility(R.id.widget_action_button, View.GONE)
        }

        // 整体点击 → 打开 MainActivity。各内部按钮的点击事件会覆盖其区域，
        // 点击空白处即落到根容器，触发打开 App。
        views.setOnClickPendingIntent(
            R.id.widget_root,
            pendingOpenApp(app),
        )

        return views
    }

    /** 拼接副标题文本：玩家 / 地址 / CPU·MEM。 */
    private fun buildSubtitle(
        context: Context,
        snap: WidgetSnapshot,
        opts: WidgetDisplayOptions,
    ): String {
        val parts = mutableListOf<String>()

        if (opts.showPlayers && (snap.isRunning || snap.isBusy)) {
            // 在线玩家数；非运行时（starting/preparing/stopping）也展示以免空。
            parts += context.getString(R.string.widget_label_players, snap.playerCount)
        }

        if (opts.showAddress && snap.isRunning) {
            // 地址显示：优先公网地址（STUN/UPnP/DDNS），无可用公网地址时
            // 回退到内网地址，保证小组件始终能给用户一个可连接的入口。
            val address = snap.publicAddress ?: snap.localAddress
            if (!address.isNullOrEmpty()) {
                parts += context.getString(R.string.widget_label_address, address)
            }
        }

        if (opts.showStats && snap.isRunning) {
            // 状态点为「运行中」时再采集 CPU/MEM，避免 onUpdate 在停止时还要扫 /proc 浪费。
            val cpu = SystemStats.cpuUsage()
            val mem = SystemStats.memInfo(context)
            val memPercent = if (mem[0] > 0)
                (mem[1].toDouble() / mem[0].toDouble() * 100.0) else -1.0
            when {
                cpu >= 0 && memPercent >= 0 ->
                    parts += context.getString(
                        R.string.widget_label_cpu_mem,
                        cpu.roundToInt(),
                        memPercent.roundToInt(),
                    )
                cpu >= 0 ->
                    parts += context.getString(R.string.widget_label_cpu, cpu.roundToInt())
                memPercent >= 0 ->
                    parts += context.getString(R.string.widget_label_mem, memPercent.roundToInt())
            }
        }

        return parts.joinToString("  ·  ")
    }

    private fun pendingAction(
        context: Context,
        clazz: Class<*>,
        action: String,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(context, clazz).apply {
            this.action = action
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getBroadcast(context, requestCode, intent, flags)
    }

    private fun pendingOpenApp(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getActivity(context, 0, intent, flags)
    }
}

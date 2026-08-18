package com.venti1112.edgecube.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.venti1112.edgecube.MainActivity
import com.venti1112.edgecube.R
import com.venti1112.edgecube.server.ServerProcessManager

/**
 * 桌面小组件入口：4×1 胶囊，展示服务端状态 + 启停按钮。
 *
 * - [onUpdate]：每次系统刷新、状态变化（[WidgetUpdater.requestUpdate] 主动调用）
 *   时触发，把当前快照渲染到 [RemoteViews]。
 * - [onReceive] 处理三条自定义 action：
 *   - [ACTION_OPEN] → 启动 MainActivity（与点击整体区域等效，但允许从按钮回弹）；
 *   - [ACTION_START] → 调用 [ServerProcessManager.startFromWidgetSnapshot]；
 *   - [ACTION_STOP] → 调用 [ServerProcessManager.stopFromWidget]。
 *
 * 注意：start/stop 走 ServerProcessManager 单例，由其内部拉起 [ServerService]
 * 前台保活；小组件本身不持有任何进程级引用。
 */
class ServerWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        // 一次构建 RemoteViews，应用到所有 ID（widget 资源都共享）。
        // ServerWidgetViews.build 已在 WidgetUpdater 中复用；委托给静态构建方法以保持单一路径。
        for (id in appWidgetIds) {
            val views = ServerWidgetViews.build(context)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_START -> {
                // 启动：异步进行；启动结果会经 ServerProcessManager 触发 requestUpdate。
                val result = ServerProcessManager.getInstance(context).startFromWidgetSnapshot()
                if (result != null) {
                    // 启动失败，立即刷新一次以反映「已停止」真实状态。
                    WidgetUpdater.requestUpdate(context)
                }
            }
            ACTION_STOP -> {
                ServerProcessManager.getInstance(context).stopFromWidget()
                // stop 异步；ServerProcessManager 退出后会 requestUpdate。
            }
            ACTION_OPEN -> {
                // 与点击整体区域相同：打开 App。Android 会自动给整体区域挂
                // MainActivity 的 PendingIntent，这里作为按钮的备用入口存在。
                openApp(context)
            }
        }
    }

    private fun openApp(context: Context) {
        try {
            val intent = Intent(context, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
            context.startActivity(intent)
        } catch (_: Exception) {
        }
    }

    companion object {
        const val ACTION_OPEN = "com.venti1112.edgecube.widget.action.OPEN"
        const val ACTION_START = "com.venti1112.edgecube.widget.action.START"
        const val ACTION_STOP = "com.venti1112.edgecube.widget.action.STOP"
    }
}

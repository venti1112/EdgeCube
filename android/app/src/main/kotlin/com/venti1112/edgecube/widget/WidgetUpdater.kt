package com.venti1112.edgecube.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context

/**
 * 触发桌面小组件刷新。
 *
 * 由 [com.venti1112.edgecube.server.ServerProcessManager] 在状态变化时调用，
 * 封装在此避免外部模块直接引用小组件 ComponentName。
 */
internal object WidgetUpdater {

    /** 触发已安装在桌面上的全部 EdgeCube 小组件重建。 */
    fun requestUpdate(context: Context) {
        val app = context.applicationContext
        val manager = AppWidgetManager.getInstance(app)
        val provider = ComponentName(app, ServerWidgetProvider::class.java)
        try {
            manager.updateAppWidget(provider, ServerWidgetViews.build(app))
        } catch (_: Exception) {
            // 用户从未把小组件放在桌面：返回空 ID 列表，静默。
        }
    }
}

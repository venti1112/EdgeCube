package com.venti1112.edgecube.keepalive

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

    companion object {
        /** 点颜色绑定：固定表示运行状态（绿色）。 */
        const val DOT_SOURCE_STATUS = "status"
        /** 点颜色绑定：CPU 使用率。 */
        const val DOT_SOURCE_CPU = "cpu"
        /** 点颜色绑定：设备内存占用率。 */
        const val DOT_SOURCE_MEM = "mem"
        /** 点颜色绑定：服务端内存占设备总内存比例。 */
        const val DOT_SOURCE_SERVER_MEM = "serverMem"
    }
}

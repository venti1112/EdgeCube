package com.venti1112.edgecube.channels

import android.content.Context
import com.venti1112.edgecube.server.ServerProcessManager
import com.venti1112.edgecube.system.DeviceInfo
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 系统监控通道：设备内存 + CPU 使用率 + 服务端进程内存 + 设备信息
 * （采集实现见 [DeviceInfo]）。
 */
internal object SystemMonitorChannel {

    private const val CHANNEL = "com.venti1112.edgecube/system_monitor"

    fun register(messenger: BinaryMessenger, context: Context) {
        val serverManager = ServerProcessManager.getInstance(context)
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSystemInfo" -> {
                    // /proc 读取（proot 模式含全 /proc 扫描）放后台线程。
                    ChannelIo.runAsync(result, "MONITOR_ERR") {
                        DeviceInfo.systemInfo(context, serverManager)
                    }
                }
                "getDeviceInfo" -> {
                    ChannelIo.runAsync(result, "DEVICE_INFO_ERR") {
                        DeviceInfo.deviceInfo()
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

package com.venti1112.edgecube.system

import android.content.Context
import android.os.Build
import com.venti1112.edgecube.server.ServerProcessManager
import com.venti1112.edgecube.server.SystemStats
import java.io.BufferedReader
import java.io.FileInputStream
import java.io.InputStreamReader

/**
 * 系统监控与设备信息采集：设备内存 + CPU 使用率 + 服务端进程内存，
 * 以及 SoC 型号 / 架构 / 制造商 / 型号（用于崩溃报告）。
 */
object DeviceInfo {

    /** 一次系统监控采样，供服务器页监控卡展示。 */
    fun systemInfo(context: Context, serverManager: ServerProcessManager): Map<String, Any?> {
        val memInfo = SystemStats.memInfo(context)
        val cpuUsage = SystemStats.cpuUsage()
        val serverMemMb = SystemStats.serverMemMb(serverManager)

        val map = HashMap<String, Any?>()
        map["totalMemMb"] = memInfo[0]     // MemTotal (MB)
        map["usedMemMb"] = memInfo[1]      // Used (MB)
        map["availMemMb"] = memInfo[2]     // MemAvailable (MB)
        map["cpuUsage"] = cpuUsage          // 0.0–100.0；不可用时 -1
        map["serverMemMb"] = serverMemMb   // 服务端 RSS MB；未运行则为 null
        return map
    }

    /**
     * 返回设备硬件信息，用于崩溃报告。
     * SoC 型号从 /proc/cpuinfo 的 Hardware / Processor 字段读取。
     */
    fun deviceInfo(): Map<String, Any?> {
        val map = HashMap<String, Any?>()
        map["socModel"] = readSocModel()
        map["architecture"] = Build.SUPPORTED_ABIS?.firstOrNull() ?: "unknown"
        map["manufacturer"] = Build.MANUFACTURER ?: "unknown"
        map["model"] = Build.MODEL ?: "unknown"
        map["androidVersion"] = Build.VERSION.RELEASE ?: "unknown"
        map["securityPatch"] = Build.VERSION.SECURITY_PATCH ?: "unknown"
        return map
    }

    /**
     * 高通 soc_id 到芯片营销名的映射（来源于 Linux 内核 qcom,ids.h）。
     * 当 /sys/devices/soc0/soc_id 返回数字时，用此表转换为可读名称。
     */
    private val qualcommSocIdMap: Map<String, String> = mapOf(
        // Snapdragon 8 系列
        "339" to "Snapdragon 865",
        "356" to "Snapdragon 870",
        "439" to "Snapdragon 888",
        "457" to "Snapdragon 8 Gen 1",
        "519" to "Snapdragon 8 Gen 2",
        "557" to "Snapdragon 8 Gen 3",
        "618" to "Snapdragon 8 Elite",
        "660" to "Snapdragon 8 Elite Gen 5",
        // Snapdragon 7 系列
        "459" to "Snapdragon 778G",
        "506" to "Snapdragon 7 Gen 1",
        "547" to "Snapdragon 7+ Gen 2",
        "636" to "Snapdragon 7 Gen 3",
        // Snapdragon 6 系列
        "507" to "Snapdragon 695",
        "640" to "Snapdragon 6 Gen 1",
        // Snapdragon X 系列
        "555" to "Snapdragon X Elite",
        // 其他常见
        "530" to "Snapdragon 8+ Gen 1",
        "531" to "Snapdragon 8+ Gen 1",
        "534" to "Snapdragon 8s Gen 3",
    )

    /**
     * 读取 SoC 型号，按优先级尝试多种来源：
     * 1. /proc/cpuinfo 的 Hardware 字段（常见于高通设备）
     * 2. /proc/cpuinfo 的 Processor 字段
     * 3. /proc/cpuinfo 的 model name 字段（常见于 x86 设备）
     * 4. /sys/devices/soc0/machine（sysfs，常含真实芯片名）
     * 5. /sys/devices/soc0/soc_id（高通 soc_id 编码，通过映射表转换）
     * 6. Build.HARDWARE（始终可用，但高通设备只返回 "qcom"）
     */
    private fun readSocModel(): String {
        var hardware = ""
        var processor = ""
        var modelName = ""
        try {
            BufferedReader(InputStreamReader(FileInputStream("/proc/cpuinfo"))).use { reader ->
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    val l = line ?: continue
                    when {
                        l.startsWith("Hardware") && hardware.isEmpty() ->
                            hardware = l.substringAfter(':').trim()
                        l.startsWith("Processor") && processor.isEmpty() ->
                            processor = l.substringAfter(':').trim()
                        l.startsWith("model name") && modelName.isEmpty() ->
                            modelName = l.substringAfter(':').trim()
                    }
                }
            }
        } catch (_: Exception) {
            // 读取失败继续兑底
        }

        // cpuinfo 字段中优先级最高的直接返回
        if (hardware.isNotEmpty()) return hardware
        if (processor.isNotEmpty()) return processor
        if (modelName.isNotEmpty()) return modelName

        // sysfs：常含可读的芯片名（如 "Snapdragon 8 Gen 2"）
        val socMachine = readSysfsTrimmed("/sys/devices/soc0/machine")
        if (!socMachine.isNullOrEmpty() && socMachine != "Unknown") return socMachine

        // soc_id 是数字时，通过映射表转换为可读名称
        val socId = readSysfsTrimmed("/sys/devices/soc0/soc_id")
        if (!socId.isNullOrEmpty()) {
            val mapped = qualcommSocIdMap[socId]
            if (mapped != null) return mapped
            // 不在映射表中，尝试返回原始 soc_id（如果不是纯数字则直接返回）
            if (!socId.all { it.isDigit() }) return socId
        }

        // 最终兑底：Build.HARDWARE，但跳过高通的泛化值 "qcom"
        val hw = Build.HARDWARE
        if (!hw.isNullOrEmpty() && hw != "qcom") return hw

        // 如果所有可读来源都失败，但 soc_id 是数字，也返回它（好过 unknown）
        if (!socId.isNullOrEmpty()) return socId

        return "unknown"
    }

    /** 读取单行 sysfs 文件并去除首尾空白，失败返回 null。 */
    private fun readSysfsTrimmed(path: String): String? {
        return try {
            BufferedReader(InputStreamReader(FileInputStream(path))).use {
                it.readLine()?.trim()?.takeIf { s -> s.isNotEmpty() }
            }
        } catch (_: Exception) {
            null
        }
    }
}

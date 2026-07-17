package com.venti1112.edgecube.server

import android.app.ActivityManager
import android.content.Context
import java.io.BufferedReader
import java.io.File
import java.io.FileInputStream
import java.io.InputStreamReader

/**
 * 系统资源读取工具：设备内存、CPU 使用率、进程 RSS。
 *
 * 供 system_monitor 通道（[com.venti1112.edgecube.MainActivity]）与状态悬浮窗
 * （[KeepAliveManager]）共用；后者独立于 Activity 生命周期运行，故这些读取
 * 逻辑不能作为 Activity 的私有方法存在。
 */
object SystemStats {

    /**
     * 从 /proc/meminfo 读取内存信息。
     * 返回 [totalMb, usedMb, availMb]。
     */
    fun memInfo(context: Context): LongArray {
        var totalKb = 0L
        var availKb = 0L
        var buffersKb = 0L
        var cachedKb = 0L
        try {
            BufferedReader(InputStreamReader(FileInputStream("/proc/meminfo"))).use { reader ->
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    val l = line ?: continue
                    when {
                        l.startsWith("MemTotal:") ->
                            totalKb = l.extractKbValue()
                        l.startsWith("MemAvailable:") ->
                            availKb = l.extractKbValue()
                        l.startsWith("Buffers:") ->
                            buffersKb = l.extractKbValue()
                        l.startsWith("Cached:") ->
                            cachedKb = l.extractKbValue()
                    }
                }
            }
        } catch (_: Exception) {
            // 读取失败时使用 ActivityManager 兑底
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val info = ActivityManager.MemoryInfo()
            am.getMemoryInfo(info)
            return longArrayOf(
                info.totalMem / (1024 * 1024),
                (info.totalMem - info.availMem) / (1024 * 1024),
                info.availMem / (1024 * 1024),
            )
        }

        // 若 MemAvailable 不存在（极老内核），用 Buffers + Cached 估算
        if (availKb == 0L && totalKb > 0L) {
            availKb = buffersKb + cachedKb
        }
        val usedKb = totalKb - availKb
        return longArrayOf(totalKb / 1024, usedKb / 1024, availKb / 1024)
    }

    /** 从 /proc/meminfo 的一行中提取 kB 数值。 */
    private fun String.extractKbValue(): Long {
        // 格式："MemTotal:       12345678 kB"
        val parts = this.trim().split("\\s+".toRegex())
        return parts.getOrNull(1)?.toLongOrNull() ?: 0L
    }

    /**
     * 通过读取各 CPU 核心的当前频率与最大/最小频率计算系统全局 CPU 使用率。
     * CPU% = (curFreq - minFreq) / (maxFreq - minFreq) × 100
     * 对所有核心取平均值。
     * 读取路径：
     *   /sys/devices/system/cpu/cpu[X]/cpufreq/cpuinfo_max_freq
     *   /sys/devices/system/cpu/cpu[X]/cpufreq/cpuinfo_min_freq
     *   /sys/devices/system/cpu/cpu[X]/cpufreq/scaling_cur_freq
     */
    fun cpuUsage(): Double {
        val cpuBase = File("/sys/devices/system/cpu")
        val cpuDirs = cpuBase.listFiles { f ->
            f.isDirectory && f.name.startsWith("cpu") &&
                    f.name.length > 3 && f.name.substring(3).all { it.isDigit() }
        } ?: return -1.0
        if (cpuDirs.isEmpty()) return -1.0

        var totalPercent = 0.0
        var validCores = 0

        for (cpuDir in cpuDirs) {
            val freqDir = File(cpuDir, "cpufreq")
            if (!freqDir.isDirectory) continue

            val maxFreq = readLongFromFile(File(freqDir, "cpuinfo_max_freq"))
            val minFreq = readLongFromFile(File(freqDir, "cpuinfo_min_freq"))
            val curFreq = readLongFromFile(File(freqDir, "scaling_cur_freq"))

            if (maxFreq < 0 || minFreq < 0 || curFreq < 0) continue

            val range = maxFreq - minFreq
            val percent = if (range > 0) {
                ((curFreq - minFreq).toDouble() / range.toDouble()) * 100.0
            } else {
                // 最大最小频率相同，说明是固定频率，根据当前频率判断
                if (curFreq >= maxFreq) 100.0 else 0.0
            }

            totalPercent += percent.coerceIn(0.0, 100.0)
            validCores++
        }

        return if (validCores > 0) {
            (totalPercent / validCores).coerceIn(0.0, 100.0)
        } else {
            -1.0
        }
    }

    /** 读取文件中的长整型数值；失败返回 -1。 */
    private fun readLongFromFile(file: File): Long {
        return try {
            BufferedReader(InputStreamReader(FileInputStream(file))).use {
                it.readLine()?.trim()?.toLongOrNull() ?: -1
            }
        } catch (_: Exception) {
            -1
        }
    }

    /**
     * 读取指定 PID 进程的 RSS（驻留内存，单位 KB）。
     * 从 /proc/<pid>/stat 第 24 个字段（1-indexed）读取页数，乘以页大小。
     */
    fun processRssKb(pid: Int): Long? {
        return try {
            val line = BufferedReader(
                InputStreamReader(FileInputStream("/proc/$pid/stat"))
            ).use { it.readLine() } ?: return null

            // 进程名可能含空格和括号，从最后一个 ')' 之后开始切分
            val closeParen = line.lastIndexOf(')')
            if (closeParen < 0) return null
            val fields = line.substring(closeParen + 2).trim().split(" ")
            // ')' 之后第 1 个字段是 state(index 0)，RSS 是 index 21
            if (fields.size < 22) return null
            val rssPages = fields[21].toLongOrNull() ?: return null
            val pageSizeKb = 4L  // Linux 页大小 4KB
            rssPages * pageSizeKb
        } catch (_: Exception) {
            null
        }
    }

    /**
     * 累加 proot 容器内所有进程的 RSS（KB）——包括 proot 自身及其跟踪的所有 tracee。
     *
     * proot 基于 ptrace 跟踪模式：proot 是 tracer，容器内所有进程是 tracee。
     * 每个被跟踪进程的 /proc/<pid>/status 中都包含 `TracerPid: <proot_pid>`。
     *
     * 之所以扫描 /proc 下各 PID 的 status 文件，而非递归遍历
     * /proc/<pid>/task/<pid>/children：后者依赖内核配置 CONFIG_PROC_CHILDREN，
     * 很多 Android 内核未启用，导致只能读到 proot 自身的几 MB，找不到实际工作
     * 负载进程（java/php/node…）。TracerPid 方案只需单次扫描全部 /proc 项，
     * O(n) 且不依赖内核配置。
     */
    fun processTreeRssKb(rootPid: Int): Long {
        var totalKb = 0L
        // 累加 proot 自身 RSS（TracerPid 为 0，不会被下面的扫描命中）
        totalKb += processRssKb(rootPid) ?: 0L

        // 扫描 /proc/*/status，找 TracerPid == rootPid 的进程
        val procDir = File("/proc")
        val pidDirs = procDir.listFiles { f ->
            f.isDirectory && f.name.all { it.isDigit() } && f.name.isNotEmpty()
        } ?: return totalKb

        for (dir in pidDirs) {
            val pid = dir.name.toIntOrNull() ?: continue
            if (pid == rootPid) continue // 已单独累加
            try {
                var tracerPid = -1  // -1 = 未读取
                var vmRssKb = 0L
                BufferedReader(
                    InputStreamReader(FileInputStream(File(dir, "status")))
                ).use { reader ->
                    var line: String?
                    while (reader.readLine().also { line = it } != null) {
                        when {
                            line!!.startsWith("TracerPid:") -> {
                                tracerPid = line.substringAfter(":").trim()
                                    .toIntOrNull() ?: 0
                                // TracerPid 在 status 文件中位于 VmRSS 之前；
                                // 若不是我们的 proot，无需继续读 VmRSS。
                                if (tracerPid != rootPid) break
                            }
                            line.startsWith("VmRSS:") -> {
                                vmRssKb = line.substringAfter(":").trim()
                                    .split(" ")[0].toLongOrNull() ?: 0L
                                break
                            }
                        }
                    }
                }
                if (tracerPid == rootPid) {
                    totalKb += vmRssKb
                }
            } catch (_: Exception) {
                // 进程可能已退出，忽略
            }
        }
        return totalKb
    }

    /**
     * 读取服务端进程当前内存占用（MB）；未运行返回 null。
     * proot 模式下累加整个进程树，原生模式读单进程 RSS。
     */
    fun serverMemMb(manager: ServerProcessManager): Long? {
        val pid = manager.pid
        if (pid <= 0 || !manager.isRunning) return null
        val rssKb = if (manager.isProotLaunch) {
            processTreeRssKb(pid)
        } else {
            processRssKb(pid) ?: 0L
        }
        return if (rssKb > 0) rssKb / 1024 else null
    }
}

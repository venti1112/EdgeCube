package com.venti1112.edgecube.server

import java.io.File

/**
 * 探测 JRE 内 libjli.so / libjvm.so 的位置并构建 LD_LIBRARY_PATH。
 *
 * 用递归探测而非硬编码路径，自适应各架构与各 JDK 版本的不同布局：
 *   JDK 17+ : lib/libjli.so              lib/server/libjvm.so
 *   JDK 8   : lib/<arch>/jli/libjli.so   lib/<arch>/server/libjvm.so
 * （<arch> 随架构而异：aarch64 / arm / amd64 …，故不硬编码）
 */
object JreLayout {

    /** 探测结果：libjli 绝对路径 + 适配该 JRE 的 LD_LIBRARY_PATH。 */
    data class Resolved(val libjli: File, val ldLibraryPath: String)

    /**
     * 一次遍历 JRE 目录，定位 libjli.so 与 libjvm.so（优先 server），并收集所有含 .so 的目录。
     * @throws IllegalStateException 找不到 libjli.so 时
     */
    fun resolve(jreDir: File, nativeLibraryDir: String): Resolved {
        var libjli: File? = null
        var libjvm: File? = null
        val soDirs = LinkedHashSet<String>()

        jreDir.walkTopDown().forEach { f ->
            if (f.isFile && f.name.endsWith(".so")) {
                f.parentFile?.absolutePath?.let { soDirs.add(it) }
                when (f.name) {
                    "libjli.so" -> if (libjli == null) libjli = f
                    // server 版优先于 client / 其它位置
                    "libjvm.so" -> if (libjvm == null || f.parentFile?.name == "server") libjvm = f
                }
            }
        }

        val jli = libjli ?: throw IllegalStateException("未找到 libjli.so，JRE 可能损坏")

        // libjvm(server) 与 libjli 目录置前，其余 .so 目录其后，末尾追加 nativeLibraryDir。
        val ordered = LinkedHashSet<String>()
        libjvm?.parentFile?.absolutePath?.let { ordered.add(it) }
        jli.parentFile?.absolutePath?.let { ordered.add(it) }
        ordered.addAll(soDirs)
        ordered.add(nativeLibraryDir)

        return Resolved(jli, ordered.joinToString(":"))
    }
}

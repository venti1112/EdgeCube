package com.venti1112.edgecube.proot

import android.content.Context
import android.system.Os
import java.io.File

/**
 * proot bootstrap 管理：把随 APK 打包的 proot 及其依赖暴露为「正常的 Linux 路径」。
 *
 * 设计来源：tiny_container 项目的 `Global.kt`（setupBootstrapIfRequired /
 * setupEnvironment），裁剪掉图形界面（X11/VNC/音频）相关部分，只保留命令行
 * 运行所需的最小集。
 *
 * 关键点：
 *  - proot 本体与依赖（busybox/tar/zstd/talloc…）以 `.so` 伪装可执行文件的形式
 *    打包在 `jniLibs/arm64-v8a/`，安装后位于 `applicationInfo.nativeLibraryDir`。
 *    命名约定沿用 tiny_container：`lib__bin__<name>__.so` 编码了原始 `/bin/<name>`
 *    路径，`lib__lib__<soname>__.so` 编码原始 `/lib/<soname>` 路径。
 *  - bootstrap 目录（`filesDir/bootstrap/{bin,lib}`）通过 symlink 暴露这些 .so，
 *    使 proot 在构造子进程 PATH、解释器路径时拿到「正常的 Linux 路径」。
 *
 * 必须随 APK 打包的原生库（来自 tiny_container releases 的 jniLibs.zip）：
 *  - lib__bin__proot-classic__.so       proot 可执行文件（带 tiny_computer 补丁）
 *  - lib__bin__busybox__.so             busybox（提供 sh/tar/sed/cat/…）
 *  - lib__bin__tar__.so                 GNU tar（支持 --preserve-permissions）
 *  - lib__bin__zstd__.so                zstd 解压
 *  - libproot-loader-aarch64-5.1.107-68.so    proot 的 ELF 注入 loader（64 位）
 *  - libproot-loader32-aarch64-5.1.107-68.so  proot 的 ELF 注入 loader（32 位）
 *  - libtalloc.so.2 / libzstd.so.1 / libz.so.1 / liblzma.so.5 / libacl.so /
 *    libattr.so / libpcre2-8.so / libiconv.so / libandroid-selinux.so /
 *    libbusybox.so.1.37.0   proot/busybox/tar 的运行时依赖
 *
 *  详见 README「proot 集成」一节。
 */
object ProotBootstrap {

    /** 每当 bootstrap 内容/布局变化时递增，触发老版本重建。 */
    private const val BOOTSTRAP_VERSION = 1

    /** proot 变体：目前只支持 classic（tiny_container 的默认值）。 */
    private const val PROOT_VARIANT = "proot-classic"

    /** bootstrap 目录：暴露 native libs 为正常 Linux 路径的 symlink 集合。 */
    fun bootstrapDir(context: Context): File = File(context.filesDir, "bootstrap")

    /** bootstrap 内 proot 可执行文件的绝对路径。 */
    fun prootBin(context: Context): File = File(bootstrapDir(context), "bin/proot")

    /**
     * 确保 bootstrap 已就位：在 filesDir/bootstrap/{bin,lib} 下创建指向
     * nativeLibraryDir 中各 .so 的 symlink。版本号变化或缺失时重建。
     */
    @Synchronized
    fun ensureBootstrap(context: Context) {
        val nativeDir = context.applicationInfo.nativeLibraryDir
        val bootstrap = bootstrapDir(context)
        val binDir = File(bootstrap, "bin")
        val libDir = File(bootstrap, "lib")
        binDir.mkdirs()
        libDir.mkdirs()

        // 校验关键原生库存在
        val prootSo = File(nativeDir, "lib__bin__${PROOT_VARIANT}__.so")
        if (!prootSo.exists()) {
            throw IllegalStateException(
                "未找到 proot 二进制（${prootSo.name}）。请从 tiny_container releases 下载 " +
                    "jniLibs.zip 解压到 android/app/src/main/jniLibs/arm64-v8a/。详见 README「proot 集成」一节。"
            )
        }

        if (readBootstrapVersion(context) == BOOTSTRAP_VERSION) {
            // 已就位且版本匹配——快速校验关键 symlink 存在即可
            if (File(binDir, "proot").exists() && File(binDir, "busybox").exists()) return
        }

        // bin/ 下的可执行文件 symlink
        val binEntries = listOf(
            "proot" to "lib__bin__${PROOT_VARIANT}__.so",
            "proot-classic" to "lib__bin__${PROOT_VARIANT}__.so",
            "busybox" to "lib__bin__busybox__.so",
            "sh" to "lib__bin__busybox__.so",
            "tar" to "lib__bin__tar__.so",
            "zstd" to "lib__bin__zstd__.so",
            // busybox 提供的常用工具（proot 内部脚本与交互 shell 都会用到）
            "cat" to "lib__bin__busybox__.so",
            "sed" to "lib__bin__busybox__.so",
            "rm" to "lib__bin__busybox__.so",
            "mkdir" to "lib__bin__busybox__.so",
            "ln" to "lib__bin__busybox__.so",
            "chmod" to "lib__bin__busybox__.so",
            "chown" to "lib__bin__busybox__.so",
            "id" to "lib__bin__busybox__.so",
            "uname" to "lib__bin__busybox__.so",
            "grep" to "lib__bin__busybox__.so",
            "gzip" to "lib__bin__busybox__.so",
            "xz" to "lib__bin__busybox__.so",
        )
        for ((linkName, soName) in binEntries) {
            val link = File(binDir, linkName)
            val target = File(nativeDir, soName)
            if (!target.exists()) continue // 缺失的库跳过，让调用方在使用时报错
            link.delete()
            try {
                Os.symlink(target.absolutePath, link.absolutePath)
            } catch (_: Throwable) {
                // 已存在或权限问题：尝试删除后重试一次
                link.delete()
                try { Os.symlink(target.absolutePath, link.absolutePath) } catch (_: Throwable) {}
            }
        }

        // bin/ 下的 proot loader symlink（proot 通过 PROOT_LOADER 环境变量定位）
        val loaderEntries = listOf(
            "loader" to "libproot-loader-aarch64-5.1.107-68.so",
            "loader32" to "libproot-loader32-aarch64-5.1.107-68.so",
        )
        for ((linkName, soName) in loaderEntries) {
            val link = File(binDir, linkName)
            val target = File(nativeDir, soName)
            if (!target.exists()) continue
            link.delete()
            try { Os.symlink(target.absolutePath, link.absolutePath) } catch (_: Throwable) {}
        }

        // lib/ 下的运行时依赖 symlink（proot/busybox/tar 启动时按 SONAME 查找）
        val libEntries = listOf(
            "libtalloc.so.2" to "lib__lib__libtalloc.so.2.4.4__.so",
            "libzstd.so.1" to "lib__lib__libzstd.so.1.5.7__.so",
            "libz.so.1" to "lib__lib__libz.so.1.3.2__.so",
            "liblzma.so.5" to "lib__lib__liblzma.so.5.8.3__.so",
            "libacl.so" to "lib__lib__libacl.so__.so",
            "libattr.so" to "lib__lib__libattr.so__.so",
            "libpcre2-8.so" to "lib__lib__libpcre2-8.so__.so",
            "libiconv.so" to "lib__lib__libiconv.so__.so",
            "libandroid-selinux.so" to "lib__lib__libandroid-selinux.so__.so",
            "libbusybox.so.1.37.0" to "lib__lib__libbusybox.so.1.37.0__.so",
        )
        for ((linkName, soName) in libEntries) {
            val link = File(libDir, linkName)
            val target = File(nativeDir, soName)
            if (!target.exists()) continue
            link.delete()
            try { Os.symlink(target.absolutePath, link.absolutePath) } catch (_: Throwable) {}
        }

        writeBootstrapVersion(context, BOOTSTRAP_VERSION)
    }

    /**
     * 构造 proot 进程的基础环境变量。
     *
     * 关键变量：
     *  - PROOT_LOADER / PROOT_LOADER_32：proot 用作 ELF 注入的 loader，必须指向
     *    nativeLibraryDir 下的对应 .so（与 tiny_container 一致）。
     *  - PROOT_TMP_DIR：proot 自身临时目录，必须可写。
     *  - LD_LIBRARY_PATH：包含 bootstrap/lib（依赖 .so 所在）与 nativeLibraryDir。
     *  - PATH：包含 bootstrap/bin（proot/busybox/tar 等）。
     */
    fun baseHostEnv(context: Context): Map<String, String> {
        val nativeDir = context.applicationInfo.nativeLibraryDir
        val bootstrap = bootstrapDir(context).absolutePath
        val prootTmp = File(context.cacheDir, "proot_tmp").apply { mkdirs() }.absolutePath

        val env = HashMap<String, String>()
        env["PROOT_LOADER"] = "$nativeDir/libproot-loader-aarch64-5.1.107-68.so"
        env["PROOT_LOADER_32"] = "$nativeDir/libproot-loader32-aarch64-5.1.107-68.so"
        env["PROOT_TMP_DIR"] = prootTmp
        env["LD_LIBRARY_PATH"] = "$bootstrap/lib:$nativeDir"
        env["PATH"] = "$bootstrap/bin:/system/bin:/system/xbin"
        env["TMPDIR"] = context.cacheDir.absolutePath
        env["HOME"] = context.filesDir.absolutePath
        env["LANG"] = "zh_CN.UTF-8"
        env["TERM"] = "xterm-256color"
        return env
    }

    // —— bootstrap 版本号文件（替代 SharedPreferences）——
    // 记录当前 bootstrap 布局版本，版本不匹配时触发重建。

    private fun bootstrapVersionFile(context: Context): File =
        File(context.filesDir, "proot_bootstrap_version")

    private fun readBootstrapVersion(context: Context): Int {
        val file = bootstrapVersionFile(context)
        if (!file.exists()) return 0
        return try {
            file.readText().trim().toIntOrNull() ?: 0
        } catch (_: Throwable) {
            0
        }
    }

    private fun writeBootstrapVersion(context: Context, version: Int) {
        bootstrapVersionFile(context).writeText(version.toString())
    }
}

package com.venti1112.edgecube.localservice

import android.content.Context
import android.system.Os
import java.io.File

/**
 * proot 工具链的「正常 Linux 路径」视图。
 *
 * proot/busybox/tar/zstd 与 loader 以 `.so` 伪装可执行文件的形式打进
 * `jniLibs/arm64-v8a/`，安装后位于 `applicationInfo.nativeLibraryDir`。
 * 命名约定沿用 V1：`lib__bin__<name>__.so` 对应 `/bin/<name>`，
 * `lib__lib__<soname>__.so` 对应 `/lib/<soname>`。
 *
 * `filesDir/local-service/bootstrap/{bin,lib}` 用 symlink 把这些 .so 暴露成
 * 正常路径，proot 构造子进程路径、解释器路径时会用到。
 */
object ProotBootstrap {

    /** bootstrap 布局变化时递增，触发老版本重建。 */
    private const val BOOTSTRAP_VERSION = 1

    private const val PROOT_VARIANT = "proot-classic"

    fun bootstrapDir(context: Context): File =
        File(LocalServicePaths.baseDir(context), "bootstrap")

    fun prootBin(context: Context): File = File(bootstrapDir(context), "bin/proot")

    /**
     * 确保 bootstrap 就位。缺失关键 .so 时抛出可读错误——这通常意味着
     * 构建时没有拉取原生依赖包（`android/native-deps.properties`）。
     */
    @Synchronized
    fun ensureBootstrap(context: Context) {
        val nativeDir = context.applicationInfo.nativeLibraryDir
        val bootstrap = bootstrapDir(context)
        val binDir = File(bootstrap, "bin").apply { mkdirs() }
        val libDir = File(bootstrap, "lib").apply { mkdirs() }

        val prootSo = File(nativeDir, "lib__bin__${PROOT_VARIANT}__.so")
        if (!prootSo.isFile) {
            throw IllegalStateException(
                "APK 中缺少 proot（${prootSo.name}）。" +
                    "请检查原生依赖是否随构建打入（android/native-deps.properties）。",
            )
        }

        if (readVersion(context) == BOOTSTRAP_VERSION &&
            File(binDir, "proot").exists() &&
            File(binDir, "tar").exists() &&
            File(libDir, "libtalloc.so.2").exists()
        ) {
            return
        }

        val binEntries = listOf(
            "proot" to "lib__bin__${PROOT_VARIANT}__.so",
            "busybox" to "lib__bin__busybox__.so",
            "sh" to "lib__bin__busybox__.so",
            "tar" to "lib__bin__tar__.so",
            "zstd" to "lib__bin__zstd__.so",
        )
        for ((linkName, soName) in binEntries) {
            symlink(File(binDir, linkName), File(nativeDir, soName))
        }

        // PROOT_LOADER / PROOT_LOADER_32 指向的 ELF 注入 loader
        symlink(
            File(binDir, "loader"),
            File(nativeDir, "libproot-loader-aarch64-5.1.107-68.so"),
        )
        symlink(
            File(binDir, "loader32"),
            File(nativeDir, "libproot-loader32-aarch64-5.1.107-68.so"),
        )

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
            symlink(File(libDir, linkName), File(nativeDir, soName))
        }

        File(bootstrap, "version").writeText(BOOTSTRAP_VERSION.toString())
    }

    /**
     * proot 进程的基础环境：loader、临时目录、动态库搜索路径。
     *
     * 这些是**宿主**路径，供 proot 本身使用；进入容器后由调用方覆盖
     * `PATH`/`HOME` 等面向 guest 的变量。
     */
    fun baseHostEnv(context: Context): MutableMap<String, String> {
        val nativeDir = context.applicationInfo.nativeLibraryDir
        val bootstrap = bootstrapDir(context).absolutePath
        val prootTmp = File(context.cacheDir, "proot_tmp").apply { mkdirs() }.absolutePath

        return mutableMapOf(
            "PROOT_LOADER" to "$nativeDir/libproot-loader-aarch64-5.1.107-68.so",
            "PROOT_LOADER_32" to "$nativeDir/libproot-loader32-aarch64-5.1.107-68.so",
            "PROOT_TMP_DIR" to prootTmp,
            "LD_LIBRARY_PATH" to "$bootstrap/lib:$nativeDir",
            "PATH" to "$bootstrap/bin:/system/bin:/system/xbin",
            "TMPDIR" to context.cacheDir.absolutePath,
            "HOME" to LocalServicePaths.baseDir(context).absolutePath,
            "LANG" to "C.UTF-8",
            "TERM" to "xterm-256color",
        )
    }

    /**
     * 把 daemon 可执行文件从 nativeLibraryDir 复制到持久目录。
     *
     * jniLibs 里的名字是 `lib__bin__edgecube-daemon__.so`（以 .so 结尾才会被
     * 解压到 nativeLibraryDir 并获得可执行权限）；复制到 filesDir 后以正常名字
     * 运行，同时让 rootfs 只需 bind 一个目录。
     */
    @Synchronized
    fun stageDaemonBinary(context: Context): File {
        val nativeDir = context.applicationInfo.nativeLibraryDir
        val source = File(nativeDir, "lib__bin__edgecube-daemon__.so")
        if (!source.isFile) {
            throw IllegalStateException(
                "APK 中缺少 daemon 可执行文件（${source.name}）。" +
                    "请确认构建时已把 daemon 放入 jniLibs。",
            )
        }
        val dest = File(LocalServicePaths.baseDir(context), "bin/edgecube-daemon")
        dest.parentFile?.mkdirs()
        if (!dest.isFile || dest.length() != source.length() ||
            dest.lastModified() < source.lastModified()
        ) {
            source.inputStream().use { input ->
                dest.outputStream().use { output -> input.copyTo(output, 1024 * 1024) }
            }
        }
        dest.setExecutable(true, false)
        return dest
    }

    private fun symlink(link: File, target: File) {
        if (!target.exists()) return
        link.delete()
        try {
            Os.symlink(target.absolutePath, link.absolutePath)
        } catch (_: Throwable) {
            link.delete()
            try {
                Os.symlink(target.absolutePath, link.absolutePath)
            } catch (_: Throwable) {
                // 保留缺失：真正用到时会报错，此处不吞掉启动流程
            }
        }
    }

    private fun readVersion(context: Context): Int {
        val file = File(bootstrapDir(context), "version")
        return try {
            file.readText().trim().toIntOrNull() ?: 0
        } catch (_: Throwable) {
            0
        }
    }
}

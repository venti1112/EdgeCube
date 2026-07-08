package com.venti1112.edgecube.server

import android.content.Context
import android.os.Environment
import android.system.Os
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import org.json.JSONObject

/**
 * proot 容器环境管理器：在 Android 上以无 root 方式运行 Linux rootfs。
 *
 * 设计来源：tiny_container 项目的 `Global.kt`（setupBootstrapIfRequired /
 * setupEnvironment）/ `ContainerManageViewModel.kt`（rootfs 解压与 passwd 修补） /
 * `ContainerMainViewModel.kt`（boot_command 拼装），裁剪掉图形界面（X11/VNC/音频）
 * 相关部分，只保留命令行运行所需的最小集。
 *
 * 关键点：
 *  - proot 本体与依赖（busybox/tar/zstd/talloc…）以 `.so` 伪装可执行文件的形式
 *    打包在 `jniLibs/arm64-v8a/`，安装后位于 `applicationInfo.nativeLibraryDir`。
 *    命名约定沿用 tiny_container：`lib__bin__<name>__.so` 编码了原始 `/bin/<name>`
 *    路径，`lib__lib__<soname>__.so` 编码原始 `/lib/<soname>` 路径。
 *  - bootstrap 目录（`filesDir/bootstrap/{bin,lib}`）通过 symlink 暴露这些 .so，
 *    使 proot 在构造子进程 PATH、解释器路径时拿到「正常的 Linux 路径」。
 *  - rootfs 存放在 `filesDir/proot_rootfs/<id>/`，用户导入 `rootfs.tar.zst` 解压得到。
 *  - 服务端工作目录通过 bind 挂载到容器内 `/mnt/server`，cwd 设为该路径，使 Java
 *    在容器内看到的 server.jar / world / plugins 等文件实际位于 Android 可写存储。
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
object ProotEnvironment {

    /** bootstrap 目录：暴露 native libs 为正常 Linux 路径的 symlink 集合。 */
    fun bootstrapDir(context: Context): File = File(context.filesDir, "bootstrap")

    /** rootfs 根目录：其下每个子目录是一个独立的 Linux 容器根。 */
    fun rootfsBaseDir(context: Context): File = File(context.filesDir, "proot_rootfs")

    /** 指定 id 的 rootfs 目录。 */
    fun rootfsDir(context: Context, id: String): File = File(rootfsBaseDir(context), id)

    /** 每当 bootstrap 内容/布局变化时递增，触发老版本重建。 */
    private const val BOOTSTRAP_VERSION = 1

    /** proot 变体：目前只支持 classic（tiny_container 的默认值）。 */
    private const val PROOT_VARIANT = "proot-classic"

    /** 容器内服务端工作目录的挂载点。 */
    const val GUEST_SERVER_DIR = "/mnt/server"

    /** 容器内 Android 共享存储的挂载点。 */
    const val GUEST_SDCARD_DIR = "/mnt/sdcard"

    /** 已安装 rootfs 的描述。 */
    data class ProotRootfs(
        val id: String,
        val dir: File,
        val sizeBytes: Long,
        /**
         * rootfs 内 java 可执行文件的绝对路径（容器视角）。
         * 为 null 表示 rootfs 尚未安装 OpenJDK——可进入 shell 自行 apt install，
         * 此时服务端启动会在 [buildServerCommand] 报错。
         */
        val javaBin: String?,
    )

    /** proot 启动命令的完整描述。 */
    data class ProotCommand(
        val cmd: String,
        val argv: List<String>,
        val env: Map<String, String>,
        val cwd: String,
    )

    /** 是否已安装任意 rootfs。 */
    fun hasRootfs(context: Context): Boolean {
        val base = rootfsBaseDir(context)
        if (!base.isDirectory) return false
        return base.listFiles()?.any { it.isDirectory && !it.name.startsWith(".") } == true
    }

    /** 列出所有已安装的 rootfs。 */
    fun installedRootfs(context: Context): List<ProotRootfs> {
        val base = rootfsBaseDir(context)
        if (!base.isDirectory) return emptyList()
        val result = mutableListOf<ProotRootfs>()
        for (child in base.listFiles() ?: emptyArray()) {
            if (!child.isDirectory || child.name.startsWith(".")) continue
            // 必须看起来像个 rootfs（含 /bin/sh 或 /usr/bin/sh）
            val sh = File(child, "bin/sh")
            if (!sh.exists() && !File(child, "usr/bin/sh").exists()) continue
            // size 与 javaBin 优先读缓存（导入时已计算），避免每次列表都遍历
            // 整个 rootfs（几万文件）导致 UI 卡顿。
            val size = readOrComputeSize(context, child.name, child)
            val javaBin = readOrComputeJavaBin(context, child.name, child)
            result.add(ProotRootfs(child.name, child, size, javaBin))
        }
        return result.sortedBy { it.id }
    }

    /** 取指定 id 的 rootfs；不存在或无效返回 null。 */
    fun installedRootfs(context: Context, id: String): ProotRootfs? {
        // 直接查目标目录，不遍历所有 rootfs（避免 buildServerCommand /
        // buildShellCommand 每次启动都对所有 rootfs 计算 size）。
        val dir = rootfsDir(context, id)
        if (!dir.isDirectory) return null
        val sh = File(dir, "bin/sh")
        if (!sh.exists() && !File(dir, "usr/bin/sh").exists()) return null
        val size = readOrComputeSize(context, id, dir)
        val javaBin = readOrComputeJavaBin(context, id, dir)
        return ProotRootfs(id, dir, size, javaBin)
    }

    // —— 元数据缓存（size / javaBin）——
    // rootfs 含数万文件，每次列表/查询都 walkTopDown 计算大小会导致严重卡顿。
    // 导入时计算一次写入 JSON 文件，后续直接读缓存。
    // 应用已全面转向文件式 JSON 配置，不再使用 SharedPreferences。

    private fun metaFile(context: Context): File =
        File(context.filesDir, "proot_meta.json")

    /** 读取整个元数据表；文件缺失或损坏时返回空表。 */
    @Synchronized
    private fun readMeta(context: Context): JSONObject {
        val file = metaFile(context)
        if (!file.exists()) return JSONObject()
        return try {
            val raw = file.readText()
            if (raw.isBlank()) JSONObject() else JSONObject(raw)
        } catch (_: Throwable) {
            JSONObject()
        }
    }

    /** 原子写入整个元数据表（临时文件 + rename，避免中途崩溃损坏）。 */
    @Synchronized
    private fun writeMeta(context: Context, meta: JSONObject) {
        val file = metaFile(context)
        val tmp = File(file.parentFile, "proot_meta.json.tmp")
        tmp.writeText(meta.toString())
        tmp.renameTo(file)
    }

    private fun readOrComputeSize(context: Context, id: String, dir: File): Long {
        val meta = readMeta(context)
        val entry = meta.optJSONObject(id)
        if (entry != null && entry.has("size")) return entry.getLong("size")
        val s = dirSize(dir)
        val updated = readMeta(context)
        val item = updated.optJSONObject(id) ?: JSONObject()
        item.put("size", s)
        updated.put(id, item)
        writeMeta(context, updated)
        return s
    }

    private fun readOrComputeJavaBin(context: Context, id: String, dir: File): String? {
        val meta = readMeta(context)
        val entry = meta.optJSONObject(id)
        if (entry != null && entry.has("java")) {
            return entry.optString("java").takeIf { it.isNotEmpty() }
        }
        val j = detectJavaBin(dir)
        val updated = readMeta(context)
        val item = updated.optJSONObject(id) ?: JSONObject()
        // 空字符串表示「已检测但无 Java」，避免重复探测；调用方见空串视为 null。
        item.put("java", j ?: "")
        updated.put(id, item)
        writeMeta(context, updated)
        return j
    }

    private fun cacheMeta(context: Context, id: String, size: Long, javaBin: String?) {
        val meta = readMeta(context)
        val item = meta.optJSONObject(id) ?: JSONObject()
        item.put("size", size)
        item.put("java", javaBin ?: "")
        meta.put(id, item)
        writeMeta(context, meta)
    }

    private fun clearMeta(context: Context, id: String) {
        val meta = readMeta(context)
        if (meta.has(id)) {
            meta.remove(id)
            writeMeta(context, meta)
        }
    }

    /**
     * 导入 rootfs.tar.zst（或 .tar.xz / .tar.gz）：用 proot --link2symlink 包住
     * busybox/GNU tar 解压到临时目录，成功后原子重命名到目标目录。
     *
     * @param id 用户指定的 rootfs 标识（用作目录名）；为空时从文件名推导。
     * @param onProgress 可选进度回调 (已处理字节数, 总字节数)；总字节数未知时为 -1。
     */
    fun importRootfs(
        context: Context,
        tarballPath: String,
        id: String? = null,
        onProgress: ((Long, Long) -> Unit)? = null,
    ): ProotRootfs {
        val tarball = File(tarballPath)
        if (!tarball.isFile) throw IllegalArgumentException("文件不存在：$tarballPath")

        val rootfsId = (id?.takeIf { it.isNotBlank() } ?: tarball.nameWithoutExtension)
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .takeIf { it.isNotBlank() } ?: throw IllegalArgumentException("无法推导 rootfs id")

        ensureBootstrap(context)

        val target = rootfsDir(context, rootfsId)
        if (target.exists()) throw IllegalStateException("ROOTFS_EXISTS")

        val tmpDir = File(rootfsBaseDir(context), ".$rootfsId.tmp")
        tmpDir.deleteRecursively()
        tmpDir.mkdirs()

        val bootstrapBin = File(bootstrapDir(context), "bin")
        val prootBin = File(bootstrapBin, "proot")
        val tarBin = File(bootstrapBin, "tar")

        // proot 包住 tar：--link2symlink 把硬链接转为符号链接（Android fs 不支持硬链接），
        // --delay-directory-restore + --preserve-permissions 保证权限位正确。
        val cmd = listOf(
            prootBin.absolutePath,
            "--link2symlink",
            tarBin.absolutePath,
            "-xf", tarball.absolutePath,
            "-C", tmpDir.absolutePath,
            "--delay-directory-restore",
            "--preserve-permissions",
        )

        val env = baseHostEnv(context)
        val pb = ProcessBuilder(cmd)
        pb.redirectErrorStream(true)
        pb.environment().clear()
        pb.environment().putAll(env)
        val proc = pb.start()

        // tar 输出多为进度/警告；逐行读取避免缓冲区满死锁。可解出的字节数由文件大小近似。
        val totalBytes = tarball.length()
        var lastReported = 0L
        try {
            BufferedReader(InputStreamReader(proc.inputStream, Charsets.UTF_8)).use { reader ->
                while (true) {
                    val line = reader.readLine() ?: break
                    // tar -v 模式未启用，这里基本只有警告；偶发触发进度回调。
                    if (onProgress != null && System.nanoTime() - lastReported > 500_000_000L) {
                        onProgress(-1L, totalBytes)
                        lastReported = System.nanoTime()
                    }
                    // 丢弃行内容，避免占用内存；真实错误由 exitCode 捕获。
                    @Suppress("UNUSED_VARIABLE") val ignored = line
                }
            }
        } finally {
            // 进度收尾
            onProgress?.invoke(totalBytes, totalBytes)
        }

        val code = proc.waitFor()
        if (code != 0) {
            tmpDir.deleteRecursively()
            throw IllegalStateException("解压失败（退出码 $code），请确认文件是有效的 rootfs.tar.zst")
        }

        // 修补 passwd/shadow/group/gshadow：移除 aid_* 条目并加入当前 app 身份
        // （来自 proot-distro 的做法，保证容器内 id 命令与文件归属正常）。
        fixPasswdForAndroid(tmpDir)
        // 写入 DNS 解析配置：proot 不自动继承 Android DNS，必须显式提供，
        // 否则容器内 apt/Minecraft 等所有域名解析都会失败。
        ensureResolvConf(tmpDir)

        // 原子替换
        if (!tmpDir.renameTo(target)) {
            tmpDir.deleteRecursively()
            throw IllegalStateException("无法重命名临时目录到目标目录")
        }

        return installedRootfs(context, rootfsId)
            ?: throw IllegalStateException("导入后未检测到有效 rootfs")
    }

    /** 删除指定 rootfs。 */
    fun deleteRootfs(context: Context, id: String) {
        rootfsDir(context, id).deleteRecursively()
        // 清除元数据缓存，避免残留的 size/javaBin 指向已删除的 rootfs。
        clearMeta(context, id)
    }

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

    /**
     * 构造「在 rootfs 内运行服务端 Java」的 proot 命令。
     *
     * 服务端工作目录（[workingDir]，Android 路径）会被 bind 到容器内
     * [GUEST_SERVER_DIR]，proot 的 cwd 设为该挂载点。Java 本体来自 rootfs
     * （[ProotRootfs.javaBin]），故运行的是原版、未打补丁的 OpenJDK。
     *
     * @param jvmArgs JVM 参数（如 -Xmx2G -jar server.jar nogui）
     * @param programArgs 程序参数（如 --no-wizard）
     */
    fun buildServerCommand(
        context: Context,
        rootfsId: String,
        workingDir: String,
        jvmArgs: List<String>,
        programArgs: List<String>,
    ): ProotCommand {
        val rootfs = installedRootfs(context, rootfsId)
            ?: throw IllegalStateException("proot rootfs '$rootfsId' 未安装，请先在「管理 → 运行环境」导入 rootfs.tar.zst")
        val javaBin = rootfs.javaBin
            ?: throw IllegalStateException(
                "rootfs '$rootfsId' 内未安装 OpenJDK。请进入 proot shell 执行：" +
                    " apt update && apt install -y openjdk-17-jre-headless"
            )
        val work = File(workingDir)
        if (!work.isDirectory) throw IllegalStateException("工作目录不存在：$workingDir")

        ensureBootstrap(context)
        // 每次启动前确保 DNS 配置存在（apt 等操作可能清空 resolv.conf）
        ensureResolvConf(rootfs.dir)

        val prootBin = File(bootstrapDir(context), "bin/proot").absolutePath
        val argv = mutableListOf<String>()
        argv.add(prootBin)
        argv.add("--rootfs=${rootfs.dir.absolutePath}")
        argv.add("--cwd=$GUEST_SERVER_DIR")
        argv.add("--link2symlink")
        // -0：伪造 root 身份（proot-distro 标准做法）。Minecraft 服务端常尝试
        // chmod/eula.txt 写入等操作，伪造 root 可避免权限相关失败。
        argv.add("-0")
        // 必备文件系统 bind：dev/proc/sys 是任何 Linux 程序的硬依赖
        argv.add("--bind=/dev")
        argv.add("--bind=/proc")
        argv.add("--bind=/sys")
        // /dev/urandom -> /dev/random：Java SecureRandom 在容器内偶发读 /dev/random 阻塞
        argv.add("--bind=/dev/urandom:/dev/random")
        // 服务端工作目录：bind 到容器内固定挂载点，cwd 即此处
        argv.add("--bind=${work.absolutePath}:$GUEST_SERVER_DIR")
        // Android 共享存储：让容器内可读写 /mnt/sdcard（与 tiny_container 一致）
        val sdcard = Environment.getExternalStorageDirectory()
        if (sdcard != null && sdcard.isDirectory) {
            argv.add("--bind=${sdcard.absolutePath}:$GUEST_SDCARD_DIR")
        }
        // tmpfs 替代不可写的 /tmp：用 app cacheDir 作为容器 /tmp
        val tmpDir = File(context.cacheDir, "proot_tmp")
        tmpDir.mkdirs()
        argv.add("--bind=${tmpDir.absolutePath}:/tmp")
        argv.add("--bind=${tmpDir.absolutePath}:/run")

        // 容器内执行的命令：原版 java
        argv.add(javaBin)
        // JVM 崩溃时把 hs_err 写到 stderr（PTY 从设备），父进程能收到
        argv.add("-XX:ErrorFile=/proc/self/fd/2")
        // 容器内 /tmp 已 bind，可直接用
        argv.add("-Djava.io.tmpdir=/tmp")
        argv.addAll(jvmArgs)
        argv.addAll(programArgs)

        val env = baseHostEnv(context)
        return ProotCommand(prootBin, argv, env, work.absolutePath)
    }

    /**
     * 构造「进入 rootfs 交互式 shell」的 proot 命令。
     *
     * 默认进入容器内用户 home（/root 或 /home/<user>），可通过 [cwd] 指定容器内
     * 绝对路径。优先使用 `/bin/bash`（minbase 已包含），不存在时回退 `/bin/sh`。
     *
     * @param cwd 容器内绝对路径（如 /root、/mnt/server）；为空时用 /root。
     */
    fun buildShellCommand(
        context: Context,
        rootfsId: String,
        cwd: String? = null,
    ): ProotCommand {
        val rootfs = installedRootfs(context, rootfsId)
            ?: throw IllegalStateException("proot rootfs '$rootfsId' 未安装")
        ensureBootstrap(context)
        // 每次进入 shell 前确保 DNS 配置存在（apt 等操作可能清空 resolv.conf）
        ensureResolvConf(rootfs.dir)

        val prootBin = File(bootstrapDir(context), "bin/proot").absolutePath
        val guestCwd = cwd?.takeIf { it.isNotBlank() } ?: "/root"

        val argv = mutableListOf<String>()
        argv.add(prootBin)
        argv.add("--rootfs=${rootfs.dir.absolutePath}")
        argv.add("--cwd=$guestCwd")
        argv.add("--link2symlink")
        // -0：伪造 root 身份，使 shell 内 apt install / dpkg 等包管理操作可行
        // （proot 不真正提权，仅让 getuid 等系统调用返回 0，文件实际仍以 app uid 写入）。
        argv.add("-0")
        argv.add("--bind=/dev")
        argv.add("--bind=/proc")
        argv.add("--bind=/sys")
        argv.add("--bind=/dev/urandom:/dev/random")
        val sdcard = Environment.getExternalStorageDirectory()
        if (sdcard != null && sdcard.isDirectory) {
            argv.add("--bind=${sdcard.absolutePath}:$GUEST_SDCARD_DIR")
        }
        val tmpDir = File(context.cacheDir, "proot_tmp")
        tmpDir.mkdirs()
        argv.add("--bind=${tmpDir.absolutePath}:/tmp")
        argv.add("--bind=${tmpDir.absolutePath}:/run")

        // 优先 bash（更好用），不存在则回退 sh
        val shellBin = if (File(rootfs.dir, "bin/bash").exists()) "/bin/bash" else "/bin/sh"
        argv.add(shellBin)
        argv.add("-i")

        val env = baseHostEnv(context)
        // 交互 shell 内给出更友好的提示符与终端类型
        val envWithShell = env.toMutableMap()
        envWithShell["TERM"] = "xterm-256color"
        envWithShell["LANG"] = "zh_CN.UTF-8"
        envWithShell["HOME"] = guestCwd
        envWithShell["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return ProotCommand(prootBin, argv, envWithShell, guestCwd)
    }

    // ──────────────────────────────────────────────────────
    // 内部辅助
    // ──────────────────────────────────────────────────────

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
    private fun baseHostEnv(context: Context): Map<String, String> {
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

    /**
     * 确保 rootfs 内 /etc/resolv.conf 存在且含可用 DNS。
     *
     * proot 不自动继承 Android 系统的 DNS 配置（Android 没有 /etc/resolv.conf），
     * 若不在 rootfs 内显式写入，容器内所有域名解析都会失败（apt update、
     * Mojang 服务器连接等）。
     *
     * 策略：尝试从 Android 系统属性读取当前 DNS（net.dns1 / net.dns2），
     * 失败或为空时回退到公共 DNS（阿里 + 腾讯 + Google，兼顾国内外网络）。
     */
    private fun ensureResolvConf(rootfsDir: File) {
        val resolvConf = File(rootfsDir, "etc/resolv.conf")
        // 收集 DNS 服务器列表
        val dnsServers = mutableListOf<String>()
        // 尝试读取 Android 系统属性 net.dns1 / net.dns2（部分机型有效）
        for (prop in listOf("net.dns1", "net.dns2")) {
            val value = getSystemProperty(prop)?.takeIf { it.isNotBlank() && it != "0.0.0.0" }
            if (value != null) dnsServers.add(value)
        }
        // 回退：公共 DNS（阿里 + 腾讯 + Google，覆盖国内外）
        if (dnsServers.isEmpty()) {
            dnsServers.addAll(listOf("223.5.5.5", "119.29.29.29", "8.8.8.8"))
        }
        val content = buildString {
            dnsServers.distinct().forEach { appendLine("nameserver $it") }
        }
        // 仅在内容变化时写入，避免每次启动都触发文件修改
        val existing = if (resolvConf.exists()) resolvConf.readText() else ""
        if (existing != content) {
            resolvConf.parentFile?.mkdirs()
            resolvConf.writeText(content)
        }
    }

    /** 反射读取 Android 系统属性（避免直接依赖 android.os.SystemProperties 隐藏 API）。 */
    private fun getSystemProperty(name: String): String? = try {
        val cls = Class.forName("android.os.SystemProperties")
        val method = cls.getMethod("get", String::class.java)
        method.invoke(null, name) as? String
    } catch (e: Exception) {
        null
    }

    /**
     * 探测 rootfs 内的 java 可执行文件路径（容器视角的绝对路径）。
     * 优先 /usr/bin/java，回退到 /usr/lib/jvm/<jdk>/bin/java 的首个匹配。
     * 未找到时返回 null（不抛异常），允许导入无 Java 的 rootfs 后再进 shell 安装。
     */
    private fun detectJavaBin(rootfsDir: File): String? {
        val candidates = listOf(
            "/usr/bin/java",
            "/usr/local/bin/java",
            "/opt/java/bin/java",
        )
        for (c in candidates) {
            if (File(rootfsDir, c.removePrefix("/")).exists()) return c
        }
        // 扫描 /usr/lib/jvm/<jdk>/bin/java
        val jvmBase = File(rootfsDir, "usr/lib/jvm")
        if (jvmBase.isDirectory) {
            jvmBase.listFiles()?.forEach { jdk ->
                if (jdk.isDirectory) {
                    val java = File(jdk, "bin/java")
                    if (java.exists()) return "/usr/lib/jvm/${jdk.name}/bin/java"
                }
            }
        }
        // 扫描 /usr/lib/jvm-*/bin/java（debian 风格扁平布局）
        val usrLib = File(rootfsDir, "usr/lib")
        if (usrLib.isDirectory) {
            usrLib.listFiles()?.forEach { dir ->
                if (dir.isDirectory && dir.name.startsWith("jvm-")) {
                    val java = File(dir, "bin/java")
                    if (java.exists()) return "/usr/lib/${dir.name}/bin/java"
                }
            }
        }
        return null
    }

    /**
     * 修补 rootfs 的 passwd/shadow/group/gshadow：移除 aid_* 条目并加入当前
     * app 身份（来自 proot-distro 的做法）。
     *
     * Android 上每个 app 有独立的 uid（如 u0_a123），在容器内表现为非 0 的数字。
     * 默认 rootfs 的 passwd 没有 aid_* 条目，导致 `id` 命令报错、文件归属异常。
     */
    private fun fixPasswdForAndroid(rootfsDir: File) {
        val uid = android.os.Process.myUid()
        val gid = uid // app 的 gid 通常等于 uid
        val username = "aid_${uid}"

        val files = listOf("etc/passwd", "etc/shadow", "etc/group", "etc/gshadow")
        for (path in files) {
            val f = File(rootfsDir, path)
            if (!f.exists()) continue
            try {
                val lines = f.readLines()
                    .filterNot { it.startsWith("aid_") }
                    .toMutableList()
                when (path) {
                    "etc/passwd" -> lines.add("$username:x:$uid:$gid:Android:/:/sbin/nologin")
                    "etc/shadow" -> lines.add("$username:*:18446:0:99999:7:::")
                    "etc/group" -> lines.add("$username:x:$gid:")
                    "etc/gshadow" -> lines.add("$username:*::")
                }
                f.writeText(lines.joinToString("\n") + "\n")
            } catch (_: Throwable) {
                // 修补失败不阻断导入——容器仍可运行，仅 id 命令异常
            }
        }
    }

    /** 递归计算目录总字节数（用于展示）。 */
    private fun dirSize(dir: File): Long {
        var size = 0L
        dir.walkTopDown().forEach { f ->
            if (f.isFile) size += f.length()
        }
        return size
    }
}

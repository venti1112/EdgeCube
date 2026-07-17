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
 *  - 服务端工作目录通过 bind 挂载到容器内 `/mnt/server`，cwd 设为该路径，使容器内
 *    看到的 server.jar / world / plugins 等文件实际位于 Android 可写存储。
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
 *
 * ## 多环境支持（formatVersion=2）
 *
 * 每个 rootfs 在根目录可携带 `edgecube-rootfs.json` 清单，声明环境类型
 * （java/php/node/python/generic…）与主程序路径。EdgeCube 导入时直接读取该清单，
 * 不再扫描文件系统判断 Java 路径。缺失清单的 rootfs 视为 `generic` 纯容器，
 * 启动时必须由用户在实例配置中提供完整启动命令（[buildGenericCommand]）。
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

    /** rootfs 内的元数据清单文件名（位于 rootfs 根目录）。 */
    const val MANIFEST_FILE = "edgecube-rootfs.json"

    /** 已识别的环境类型常量。未携带清单的 rootfs 视为 [ENV_GENERIC]。 */
    const val ENV_JAVA = "java"
    const val ENV_PHP = "php"
    const val ENV_NODE = "node"
    const val ENV_PYTHON = "python"
    /** box64：ARM64 上运行 x86_64 二进制的模拟器，envMainBin 为 /usr/local/bin/box64。 */
    const val ENV_BOX64 = "box64"
    /** .NET (ASP.NET Core)：运行时通过 Microsoft 源安装 aspnetcore-runtime，envMainBin 为 /usr/bin/dotnet。 */
    const val ENV_DOTNET = "dotnet"
    /** 纯容器：rootfs 无清单或 envType=generic；用户须提供完整启动命令。 */
    const val ENV_GENERIC = "generic"

    /**
     * rootfs 内嵌入的元数据清单（[MANIFEST_FILE]）。
     *
     * - [formatVersion]：清单格式版本，目前固定为 2。
     * - [envType]：环境类型（java/php/node/python/box64/dotnet/generic/…），决定默认启动方式。
     * - [envName]：展示名（如 "OpenJDK 21"），用于 UI。
     * - [envVersionName]：运行时版本字符串（如 "21.0.5+11"）。
     * - [envMainBin]：环境主程序的容器内绝对路径（如 "/usr/bin/java"）；
     *   generic 时为空串，表示不预定义主程序。
     * - [envArgs]：主程序固定前缀参数（如 java 的 ["-jar"]）；generic 时为空数组。
     * - [serverFileHint]：服务端文件扩展名提示（如 ".jar"、".phar"、".js"），
     *   用于 UI 在实例目录中筛选可作为服务端的文件。
     * - [description]：人类可读的描述。
     * - [buildDate]：构建日期字符串（YYYYMMDD）。
     */
    data class RootfsManifest(
        val formatVersion: Int,
        val envType: String,
        val envName: String,
        val envVersionName: String,
        val envMainBin: String,
        val envArgs: List<String>,
        val serverFileHint: String,
        val description: String,
        val buildDate: String,
    ) {
        /** 是否为纯容器（无预定义主程序）。 */
        val isGeneric: Boolean get() = envType == ENV_GENERIC || envMainBin.isBlank()
    }

    /** 已安装 rootfs 的描述。 */
    data class ProotRootfs(
        val id: String,
        val dir: File,
        /**
         * rootfs 内嵌的元数据清单；rootfs 未携带清单时为 null（视为 generic 纯容器）。
         *
         * 调用方据此判断：
         *  - 非空且 [RootfsManifest.envMainBin] 非空：按元数据 envType 启动主程序。
         *  - null 或 envMainBin 为空：纯容器，须由用户提供完整启动命令。
         */
        val manifest: RootfsManifest?,
    ) {
        /** 兼容旧调用方：返回主程序路径（容器视角），无则 null。 */
        val envMainBin: String? get() = manifest?.envMainBin?.takeIf { it.isNotBlank() }

        /** 环境类型；无清单时为 [ENV_GENERIC]。 */
        val envType: String get() = manifest?.envType ?: ENV_GENERIC

        /** 是否为纯容器（无主程序）。 */
        val isGeneric: Boolean get() = manifest?.isGeneric ?: true
    }

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
            // 元数据直接读 rootfs 内的 edgecube-rootfs.json。
            val manifest = readManifest(child)
            result.add(ProotRootfs(child.name, child, manifest))
        }
        return result.sortedBy { it.id }
    }

    /** 取指定 id 的 rootfs；不存在或无效返回 null。 */
    fun installedRootfs(context: Context, id: String): ProotRootfs? {
        val dir = rootfsDir(context, id)
        if (!dir.isDirectory) return null
        val sh = File(dir, "bin/sh")
        if (!sh.exists() && !File(dir, "usr/bin/sh").exists()) return null
        val manifest = readManifest(dir)
        return ProotRootfs(id, dir, manifest)
    }

    // —— 元数据清单（rootfs 内嵌）——

    /**
     * 读取 rootfs 根目录下的 [MANIFEST_FILE]。
     *
     * 文件不存在或解析失败时返回 null（调用方据此把 rootfs 视为 generic 纯容器）。
     * 不再扫描文件系统判断 Java 路径——一切以清单为准。
     */
    fun readManifest(rootfsDir: File): RootfsManifest? {
        val file = File(rootfsDir, MANIFEST_FILE)
        if (!file.isFile) return null
        return try {
            val raw = file.readText()
            if (raw.isBlank()) return null
            parseManifest(JSONObject(raw))
        } catch (_: Throwable) {
            null
        }
    }

    /** 解析清单 JSON 为 [RootfsManifest]；字段缺失时给安全默认值。 */
    private fun parseManifest(root: JSONObject): RootfsManifest {
        val formatVersion = root.optInt("formatVersion", 1)
        val envType = root.optString("envType").takeIf { it.isNotEmpty() } ?: ENV_GENERIC
        val envMainBin = root.optString("envMainBin")
        // envArgs：JSON 数组，逐项取字符串；缺失或类型不符时空数组
        val envArgs = mutableListOf<String>()
        root.optJSONArray("envArgs")?.let { arr ->
            for (i in 0 until arr.length()) {
                arr.optString(i).takeIf { it.isNotEmpty() }?.let { envArgs.add(it) }
            }
        }
        return RootfsManifest(
            formatVersion = formatVersion,
            envType = envType,
            envName = root.optString("envName").takeIf { it.isNotEmpty() }
                ?: envType.replaceFirstChar { it.uppercase() },
            envVersionName = root.optString("envVersionName"),
            envMainBin = envMainBin,
            envArgs = envArgs,
            serverFileHint = root.optString("serverFileHint"),
            description = root.optString("description"),
            buildDate = root.optString("buildDate"),
        )
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
        ensureResolvConf(context, tmpDir)

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
     * 构造「在 rootfs 内运行服务端」的 proot 命令。
     *
     * 根据 rootfs 元数据 [RootfsManifest.envType] 决定启动方式：
     *  - java：执行 [RootfsManifest.envMainBin]（如 /usr/bin/java），附加 -XX:ErrorFile
     *    与 -Djava.io.tmpdir 等容器内可用的 JVM 标准参数，再追加 [runtimeArgs] 与 [programArgs]。
     *  - php / node / python / box64 / dotnet：执行 envMainBin，附加 envArgs（如有）+ programArgs。
     *    box64 的 envMainBin 为 /usr/local/bin/box64，programArgs 为 x86_64 服务端文件。
     *    dotnet 的 envMainBin 为 /usr/bin/dotnet，programArgs 为 .dll 文件。
     *  - generic（无清单或 envMainBin 为空）：调用方必须改用 [buildGenericCommand]
     *    并提供完整启动命令；本方法对 generic rootfs 抛出 [IllegalStateException]。
     *
     * 服务端工作目录（[workingDir]，Android 路径）会被 bind 到容器内
     * [GUEST_SERVER_DIR]，proot 的 cwd 设为该挂载点。运行时本体（Java/PHP/…）
     * 来自 rootfs，故运行的是 rootfs 内未打补丁的原版。
     *
     * @param runtimeArgs 运行时参数（如 -Xmx2G）；非 java 环境也会原样追加到主程序后。
     * @param programArgs 程序参数（如 -jar server.jar nogui；或脚本文件路径 + 参数）。
     */
    fun buildServerCommand(
        context: Context,
        rootfsId: String,
        workingDir: String,
        runtimeArgs: List<String>,
        programArgs: List<String>,
    ): ProotCommand {
        val rootfs = installedRootfs(context, rootfsId)
            ?: throw IllegalStateException("proot rootfs '$rootfsId' 未安装，请先在「管理 → 运行环境」导入 rootfs.tar.zst")
        val manifest = rootfs.manifest
        if (manifest == null || manifest.isGeneric) {
            throw IllegalStateException(
                "rootfs '$rootfsId' 是纯容器（无元数据或 envType=generic），" +
                    "请在实例配置中填写完整的启动命令，或导入带元数据的环境 rootfs。"
            )
        }
        val envMainBin = manifest.envMainBin
            ?: throw IllegalStateException("rootfs '$rootfsId' 元数据缺少 envMainBin")
        val work = File(workingDir)
        if (!work.isDirectory) throw IllegalStateException("工作目录不存在：$workingDir")

        ensureBootstrap(context)
        // 每次启动前确保 DNS 配置存在（apt 等操作可能清空 resolv.conf）
        ensureResolvConf(context, rootfs.dir)

        val prootBin = File(bootstrapDir(context), "bin/proot").absolutePath
        val argv = mutableListOf<String>()
        argv.add(prootBin)
        argv.add("--rootfs=${rootfs.dir.absolutePath}")
        argv.add("--cwd=$GUEST_SERVER_DIR")
        argv.add("--link2symlink")
        // -0：伪造 root 身份（proot-distro 标准做法）。服务端常尝试
        // chmod/eula.txt 写入等操作，伪造 root 可避免权限相关失败。
        argv.add("-0")
        // 必备文件系统 bind：dev/proc/sys 是任何 Linux 程序的硬依赖
        argv.add("--bind=/dev")
        argv.add("--bind=/proc")
        argv.add("--bind=/sys")
        // /dev/urandom -> /dev/random：SecureRandom 在容器内偶发读 /dev/random 阻塞
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

        // 容器内执行的命令：环境主程序（如 /usr/bin/java、/usr/bin/php、…）
        argv.add(envMainBin)

        when (manifest.envType) {
            ENV_JAVA -> {
                // JVM 崩溃时把 hs_err 写到 stderr（PTY 从设备），父进程能收到
                argv.add("-XX:ErrorFile=/proc/self/fd/2")
                // 容器内 /tmp 已 bind，可直接用
                argv.add("-Djava.io.tmpdir=/tmp")
            }
            else -> {
                // php/node/python/box64/dotnet 等：附加清单声明的固定前缀参数。
                // box64 的 envMainBin 是 /usr/local/bin/box64，programArgs 是 x86_64 文件。
                // dotnet 的 envMainBin 是 /usr/bin/dotnet，programArgs 是 .dll 文件。
            }
        }
        // 清单声明的固定前缀参数（如 php/node 等的启动前缀）。
        // Java 环境**跳过** envArgs：java 的 `-jar` 必须紧邻 jar 文件、位于所有 JVM
        // 参数（如 -Xmx）之后，而 envArgs 是在 runtimeArgs 之前追加的——放在这里会得到
        // `java -jar -Xmx2G server.jar`，JVM 会把 -Xmx2G 当作 jar 文件名而失败。
        // Java 的 `-jar` 改由调用方在 programArgs 中于正确位置（runtimeArgs 之后、jar 之前）
        // 提供（见 server_page 的 `['-jar', file, 'nogui']`），与原生启动路径一致。
        // 现代 Forge/NeoForge（1.17+）走 @argfile，argfile 内已含主类，也不需要 -jar。
        val hasArgfile = runtimeArgs.any { it.startsWith("@") }
        if (!hasArgfile && manifest.envType != ENV_JAVA) {
            argv.addAll(manifest.envArgs)
        }
        // 调用方传入的运行时参数（如 -Xmx2G、@libraries/.../unix_args.txt）
        argv.addAll(runtimeArgs)
        // 调用方传入的程序参数（如 server.jar nogui）
        argv.addAll(programArgs)

        val env = baseHostEnv(context).toMutableMap()
        // buildGenericCommand 和 buildShellCommand 均已覆盖 PATH，
        // buildServerCommand 同样需要容器内 PATH，否则 JVM 内 JLine
        // 尝试执行 "sh" 时会在宿主 PATH 中查找，而宿主路径在容器内不可见。
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOME"] = "/root"
        return ProotCommand(prootBin, argv, env, work.absolutePath)
    }

    /**
     * 构造「在纯容器 rootfs 内运行用户自定义命令」的 proot 命令。
     *
     * 用于无元数据或 envType=generic 的 rootfs：用户须在实例配置中提供完整启动命令
     * （含主程序路径与所有参数），由本方法在容器内 [GUEST_SERVER_DIR] 下执行。
     *
     * [command] 已含主程序路径（容器内绝对路径，如 /usr/bin/python3 /mnt/server/main.py），
     * 用 busybox sh -c 包裹以支持 shell 语法（管道、引号、变量展开等）。
     */
    fun buildGenericCommand(
        context: Context,
        rootfsId: String,
        workingDir: String,
        command: String,
    ): ProotCommand {
        val rootfs = installedRootfs(context, rootfsId)
            ?: throw IllegalStateException("proot rootfs '$rootfsId' 未安装")
        val work = File(workingDir)
        if (!work.isDirectory) throw IllegalStateException("工作目录不存在：$workingDir")
        if (command.isBlank()) throw IllegalStateException("纯容器环境必须提供启动命令")

        ensureBootstrap(context)
        ensureResolvConf(context, rootfs.dir)

        val prootBin = File(bootstrapDir(context), "bin/proot").absolutePath
        val argv = mutableListOf<String>()
        argv.add(prootBin)
        argv.add("--rootfs=${rootfs.dir.absolutePath}")
        argv.add("--cwd=$GUEST_SERVER_DIR")
        argv.add("--link2symlink")
        argv.add("-0")
        argv.add("--bind=/dev")
        argv.add("--bind=/proc")
        argv.add("--bind=/sys")
        argv.add("--bind=/dev/urandom:/dev/random")
        argv.add("--bind=${work.absolutePath}:$GUEST_SERVER_DIR")
        val sdcard = Environment.getExternalStorageDirectory()
        if (sdcard != null && sdcard.isDirectory) {
            argv.add("--bind=${sdcard.absolutePath}:$GUEST_SDCARD_DIR")
        }
        val tmpDir = File(context.cacheDir, "proot_tmp")
        tmpDir.mkdirs()
        argv.add("--bind=${tmpDir.absolutePath}:/tmp")
        argv.add("--bind=${tmpDir.absolutePath}:/run")

        // 用 rootfs 内的 sh -c 包裹用户命令：支持 shell 语法（管道/重定向/引号）。
        // 优先 /bin/bash（更友好），否则回退 /bin/sh。
        val shellBin = if (File(rootfs.dir, "bin/bash").exists()) "/bin/bash" else "/bin/sh"
        argv.add(shellBin)
        argv.add("-c")
        argv.add(command)

        val env = baseHostEnv(context).toMutableMap()
        // 用户命令可能调用容器内系统工具（chmod / cp / ls 等），PATH 必须包含
        // 容器内标准目录；baseHostEnv 的 PATH 只含 bootstrap/bin 与 /system/bin，
        // 会导致 sh -c "chmod ..." 报「未找到命令」。
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOME"] = "/root"
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
        ensureResolvConf(context, rootfs.dir)

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
     * 策略：优先使用用户在「网络设置」中配置的自定义 DNS（默认 8.8.8.8,1.1.1.1），
     * 从 `<filesDir>/config/network.json` 的 `customDns` 字段读取。
     * 始终覆盖写入，确保 rootfs 自带的 DNS 配置被替换。
     */
    private fun ensureResolvConf(context: Context, rootfsDir: File) {
        val resolvConf = File(rootfsDir, "etc/resolv.conf")
        val dnsServers = loadCustomDnsServers(context)
        val content = buildString {
            dnsServers.forEach { appendLine("nameserver $it") }
        }
        resolvConf.parentFile?.mkdirs()
        resolvConf.writeText(content)
    }

    /**
     * 更新所有已安装 rootfs 的 /etc/resolv.conf。
     * 用户在「网络设置」中更改 DNS 后立即调用，使所有已导入的 rootfs 即时生效。
     */
    fun updateAllRootfsDns(context: Context) {
        val rootfsList = installedRootfs(context)
        for (rootfs in rootfsList) {
            ensureResolvConf(context, rootfs.dir)
        }
    }

    /**
     * 从 `<filesDir>/config/network.json` 读取用户配置的自定义 DNS 服务器列表。
     *
     * Dart 侧 [NetworkStore] 将 DNS 存为逗号分隔字符串（`customDns` 字段），
     * 默认值 "8.8.8.8,1.1.1.1"。此处直接读取该 JSON 文件，避免通过 MethodChannel
     * 传参的额外开销。
     */
    fun loadCustomDnsServers(context: Context): List<String> {
        val defaultDns = listOf("8.8.8.8", "1.1.1.1")
        return try {
            val configFile = File(context.filesDir, "config/network.json")
            if (!configFile.isFile) return defaultDns
            val raw = configFile.readText()
            if (raw.isBlank()) return defaultDns
            val json = JSONObject(raw)
            val dnsStr = json.optString("customDns").takeIf { it.isNotBlank() }
                ?: return defaultDns
            val servers = dnsStr.split(",")
                .map { it.trim() }
                .filter { it.isNotEmpty() }
            if (servers.isEmpty()) defaultDns else servers
        } catch (_: Throwable) {
            defaultDns
        }
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
}

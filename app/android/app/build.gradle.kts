import java.net.URI
import java.security.MessageDigest
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

fun sha256Of(file: java.io.File): String {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().use { input ->
        val buffer = ByteArray(64 * 1024)
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            digest.update(buffer, 0, read)
        }
    }
    return digest.digest().joinToString("") { "%02x".format(it) }
}

// ─── 原生依赖：proot 工具链（由「构建原生依赖」工作流从源码构建）───
// native-deps.properties 锁定 Release 资产与 sha256；下载后解压到
// build/native-deps/jniLibs/<abi>/，作为额外的 jniLibs 源目录参与打包。
val nativeDepsPropertiesFile = rootProject.file("native-deps.properties")
val nativeDepsJniDir = layout.buildDirectory.dir("native-deps/jniLibs").get().asFile
val nativeDepsLocalZipEnv = providers.environmentVariable("EDGECUBE_NATIVE_DEPS_ZIP")

val fetchNativeDeps = tasks.register("fetchNativeDeps") {
    group = "build"
    description = "下载并校验原生依赖包（proot/busybox/tar/zstd）"

    val props = Properties()
    if (nativeDepsPropertiesFile.isFile) {
        nativeDepsPropertiesFile.inputStream().use { props.load(it) }
    }
    val repo = props.getProperty("repo").orEmpty()
    val tag = props.getProperty("tag").orEmpty()
    val asset = props.getProperty("asset").orEmpty()
    val sha256 = props.getProperty("sha256").orEmpty()
    val localZipPath = nativeDepsLocalZipEnv.orNull.orEmpty()
    val localZip = localZipPath.takeIf { it.isNotBlank() }?.let { file(it) }

    inputs.property("repo", repo)
    inputs.property("tag", tag)
    inputs.property("asset", asset)
    inputs.property("sha256", sha256)
    if (localZip != null) {
        inputs.file(localZip).withPropertyName("localZip").optional()
    }
    outputs.dir(nativeDepsJniDir)

    doLast {
        if (localZip != null && !localZip.isFile) {
            throw GradleException("EDGECUBE_NATIVE_DEPS_ZIP 指向的文件不存在：${localZip.absolutePath}")
        }
        if (localZip == null &&
            (repo.isBlank() || tag.isBlank() || asset.isBlank() || sha256.isBlank())
        ) {
            throw GradleException(
                """
                缺少 android/native-deps.properties 中的 repo/tag/asset/sha256。
                请先运行 GitHub Actions 的「构建原生依赖」工作流，
                再把 Release 资产的 sha256 填入该文件。
                """.trimIndent(),
            )
        }

        val expected = localZip?.let { sha256Of(it) } ?: sha256
        val marker = File(nativeDepsJniDir, ".sha256")
        if (marker.isFile && marker.readText().trim() == expected) return@doLast

        nativeDepsJniDir.deleteRecursively()
        nativeDepsJniDir.mkdirs()
        val zipFile = localZip ?: layout.buildDirectory.dir("tmp/native-deps/$asset").get().asFile.also { out ->
            out.parentFile.mkdirs()
            val url = "https://github.com/$repo/releases/download/$tag/$asset"
            logger.lifecycle("下载原生依赖：$url")
            URI(url).toURL().openStream().use { input ->
                out.outputStream().use { input.copyTo(it) }
            }
            val actual = sha256Of(out)
            if (!actual.equals(sha256, ignoreCase = true)) {
                out.delete()
                throw GradleException("原生依赖 SHA256 不匹配：期望 $sha256，实际 $actual")
            }
        }

        copy {
            from(zipTree(zipFile))
            into(nativeDepsJniDir)
        }
        if (localZip == null) zipFile.delete()

        val required = listOf(
            "lib__bin__proot-classic__.so",
            "lib__bin__busybox__.so",
            "lib__bin__tar__.so",
            "lib__bin__zstd__.so",
            "libproot-loader-aarch64-5.1.107-68.so",
        )
        val missing = required.filterNot { File(nativeDepsJniDir, "arm64-v8a/$it").isFile }
        if (missing.isNotEmpty()) {
            nativeDepsJniDir.deleteRecursively()
            throw GradleException("原生依赖包缺少文件：${missing.joinToString()}")
        }
        marker.writeText(expected)
    }
}

// ─── 内置 rootfs：Debian 12 arm64 minbase（由「构建 rootfs」工作流产出）───
// 默认不解压，APK 只带压缩包；首次启动本地服务时由 Kotlin 侧解压到 filesDir。
val rootfsPropertiesFile = rootProject.file("rootfs.properties")
val rootfsAssetsDir = layout.buildDirectory.dir("rootfs-assets").get().asFile
val rootfsLocalAssetEnv = providers.environmentVariable("EDGECUBE_ROOTFS_ASSET")
val rootfsLocalVersionEnv = providers.environmentVariable("EDGECUBE_ROOTFS_VERSION")

val fetchRootfs = tasks.register("fetchRootfs") {
    group = "build"
    description = "下载并校验内置 rootfs 压缩包"

    val props = Properties()
    if (rootfsPropertiesFile.isFile) {
        rootfsPropertiesFile.inputStream().use { props.load(it) }
    }
    val repo = props.getProperty("repo").orEmpty()
    val tag = props.getProperty("tag").orEmpty()
    val asset = props.getProperty("asset").orEmpty()
    val sha256 = props.getProperty("sha256").orEmpty()
    val version = props.getProperty("version").orEmpty()
    val localAssetPath = rootfsLocalAssetEnv.orNull.orEmpty()
    val localAsset = localAssetPath.takeIf { it.isNotBlank() }?.let { file(it) }
    val localVersion = rootfsLocalVersionEnv.orNull.orEmpty()

    inputs.property("repo", repo)
    inputs.property("tag", tag)
    inputs.property("asset", asset)
    inputs.property("sha256", sha256)
    inputs.property("version", version)
    if (localAsset != null) {
        inputs.file(localAsset).withPropertyName("localRootfs").optional()
    }
    outputs.dir(rootfsAssetsDir)

    doLast {
        // 本地覆盖：直接用现成的 tar.zst，便于离线构建与联调
        if (localAsset != null) {
            if (!localAsset.isFile) {
                throw GradleException("EDGECUBE_ROOTFS_ASSET 指向的文件不存在：${localAsset.absolutePath}")
            }
            val digest = sha256Of(localAsset)
            val localInfoVersion = localVersion.ifBlank { version.ifBlank { "local" } }
            val marker = File(rootfsAssetsDir, ".sha256")
            if (marker.isFile && marker.readText().trim() == digest) return@doLast
            rootfsAssetsDir.deleteRecursively()
            val dir = File(rootfsAssetsDir, "rootfs").apply { mkdirs() }
            localAsset.copyTo(File(dir, localAsset.name), overwrite = true)
            File(dir, "rootfs-info.json").writeText(
                """{"version":"$localInfoVersion","sha256":"$digest","asset":"${localAsset.name}"}""",
            )
            marker.writeText(digest)
            return@doLast
        }

        if (repo.isBlank() || tag.isBlank() || asset.isBlank() ||
            sha256.isBlank() || version.isBlank()
        ) {
            throw GradleException(
                """
                缺少 android/rootfs.properties 中的 repo/tag/asset/sha256/version。
                请先运行 GitHub Actions 的「构建 rootfs」工作流，
                再把 Release 资产的 sha256 与版本号填入该文件。
                （本地联调可用 EDGECUBE_ROOTFS_ASSET 直接指定 tar.zst）
                """.trimIndent(),
            )
        }

        val rootfsDir = File(rootfsAssetsDir, "rootfs")
        val marker = File(rootfsAssetsDir, ".sha256")
        if (marker.isFile && marker.readText().trim() == sha256 &&
            File(rootfsDir, asset).isFile && File(rootfsDir, "rootfs-info.json").isFile
        ) {
            return@doLast
        }

        rootfsAssetsDir.deleteRecursively()
        rootfsDir.mkdirs()
        val download = layout.buildDirectory.dir("tmp/rootfs/$asset").get().asFile
        download.parentFile.mkdirs()

        val url = "https://github.com/$repo/releases/download/$tag/$asset"
        logger.lifecycle("下载内置 rootfs：$url")
        URI(url).toURL().openStream().use { input ->
            download.outputStream().use { input.copyTo(it) }
        }

        val actual = sha256Of(download)
        if (!actual.equals(sha256, ignoreCase = true)) {
            download.delete()
            throw GradleException("rootfs SHA256 不匹配：期望 $sha256，实际 $actual")
        }

        download.copyTo(File(rootfsDir, asset), overwrite = true)
        download.delete()
        File(rootfsDir, "rootfs-info.json").writeText(
            """{"version":"$version","sha256":"$sha256","asset":"$asset"}""",
        )
        marker.writeText(sha256)
    }
}

// ─── daemon 可执行文件 ───
// 由 CI 在 Debian（glibc）环境里交叉编译，路径通过 EDGECUBE_DAEMON_BINARY 指定；
// 本地放 build/daemon/edgecube-daemon 也可。以 lib__bin__*.so 命名进入 jniLibs，
// 安装后才会被解压到 nativeLibraryDir 并获得可执行权限。
val daemonJniDir = layout.buildDirectory.dir("daemon-jniLibs").get().asFile
val daemonBinaryEnv = providers.environmentVariable("EDGECUBE_DAEMON_BINARY")

val stageDaemonBinary = tasks.register("stageDaemonBinary") {
    group = "build"
    description = "把交叉编译好的 daemon 可执行文件放进 jniLibs"

    val overridePath = daemonBinaryEnv.orNull.orEmpty()
    val sourceFile = if (overridePath.isNotBlank()) {
        file(overridePath)
    } else {
        layout.buildDirectory.file("daemon/edgecube-daemon").get().asFile
    }
    inputs.file(sourceFile).withPropertyName("daemonBinary").optional()
    outputs.dir(daemonJniDir)

    doLast {
        if (!sourceFile.isFile) {
            throw GradleException(
                """
                缺少 daemon 可执行文件: ${sourceFile.absolutePath}
                Android 构建需要先在 Debian/glibc 环境交叉编译 daemon：
                  cargo build --release --target aarch64-unknown-linux-gnu
                然后设置 EDGECUBE_DAEMON_BINARY 指向该文件，或把它复制到
                  android/app/build/daemon/edgecube-daemon
                """.trimIndent(),
            )
        }
        daemonJniDir.deleteRecursively()
        val dest = File(daemonJniDir, "arm64-v8a/lib__bin__edgecube-daemon__.so")
        dest.parentFile.mkdirs()
        sourceFile.copyTo(dest, overwrite = true)
    }
}

android {
    namespace = "com.venti1112.edgecube"
    compileSdk {
        version = release(37) {
            minorApiLevel = 1
        }
    }
    buildToolsVersion = "37.0.0"
    // 本地服务不编译 NDK 原生代码；这个版本只用于 AGP 的 jniLibs 处理。
    ndkVersion = "30.0.16248370"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.venti1112.edgecube"
        minSdk = 24
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as? String ?: ""
            keyPassword = keystoreProperties["keyPassword"] as? String ?: ""
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as? String ?: ""
            enableV1Signing = false
            enableV2Signing = true
            enableV3Signing = true
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
        debug {
            signingConfig = signingConfigs.getByName("release")
        }
    }

    androidResources {
        // tar.zst 已经是压缩格式，再压一遍没有收益
        noCompress += "tar.zst"
    }

    packaging {
        // nativeLibraryDir 里必须是真实文件：proot 与 daemon 都要能 exec
        jniLibs {
            useLegacyPackaging = true
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDir(nativeDepsJniDir)
            jniLibs.srcDir(daemonJniDir)
            assets.srcDir(rootfsAssetsDir)
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// AGP 在 afterEvaluate 之后才登记 preBuild；用 matching + configureEach 才安全。
tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn(fetchNativeDeps, fetchRootfs, stageDaemonBinary)
}

import java.net.URI
import java.security.MessageDigest
import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

// ─── Rust：libedgecube_pty.so（portable-pty PTY 桥）+ libedgecube_tools.so ────
//（workspace：rust/ 下含 edgecube-pty 与 edgecube-tools 两个 crate）

val dartRoot = rootProject.projectDir.parentFile
val rustCrateDir = dartRoot.resolve("rust")

// 目标 ABI 需与 `rustup target list --installed` 一致（无 i686，故不含 x86）。
val rustAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")
// cargo-ndk -o 输出 jniLibs 目录结构：<dir>/<abi>/lib*.so
val rustJniLibs = rootProject.layout.buildDirectory.dir("rust/jniLibs").get().asFile

val cargoBuild = tasks.register<Exec>("cargoBuild") {
    group = "build"
    description = "交叉编译 libedgecube_pty.so 与 libedgecube_tools.so（${rustAbis.joinToString()}）到 build/rust/jniLibs"

    inputs.files(
        fileTree(rustCrateDir) {
            include(
                "Cargo.toml",
                "Cargo.lock",
                "*/Cargo.toml",
                "src/**/*.rs",
                "tests/**/*.rs",
                "*/src/**/*.rs",
                "*/tests/**/*.rs",
                "*/build.rs",
                "*/pthread_stub.c",
            )
        },
    )
    outputs.dir(rustJniLibs)

    val outDir = rustJniLibs
    val args = buildList {
        addAll(listOf("cargo", "ndk"))
        rustAbis.forEach { addAll(listOf("-t", it)) }
        addAll(
            listOf(
                "-P", "24",
                "-o", outDir.absolutePath,
                "build", "--release",
                "--manifest-path", rustCrateDir.resolve("Cargo.toml").absolutePath,
            ),
        )
    }
    commandLine(args)
    workingDir = rustCrateDir

    doFirst {
        outDir.deleteRecursively()
        outDir.mkdirs()
        val probe = ProcessBuilder("cargo", "--version")
            .redirectErrorStream(true)
            .start()
        if (probe.waitFor() != 0) {
            throw GradleException(
                """
                找不到 cargo，无法构建 Rust JNI 库（libedgecube_pty.so / libedgecube_tools.so）。
                请先安装 Rust 与 cargo-ndk：
                  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
                  cargo install cargo-ndk
                并确认 Android NDK 已安装（local.properties 的 sdk.dir / ndkVersion=${android.ndkVersion}）。
                """.trimIndent(),
            )
        }
        val ndk = android.ndkDirectory
        if (!ndk.isDirectory) {
            throw GradleException("Android NDK 未就位：${ndk}（安装 NDK ${android.ndkVersion} 后重试）")
        }
        // 镜像预置的 ANDROID_NDK_ROOT 指向默认 NDK，与 ndkVersion 不一致时
        // cargo-ndk 会告警；这里显式统一为构建使用的 NDK。
        environment("ANDROID_NDK_HOME", ndk.absolutePath)
        environment("ANDROID_NDK_ROOT", ndk.absolutePath)
    }
}

// ─── 原生依赖：proot 工具链 + PHP CLI（由「构建原生依赖」工作流从源码构建）───
// android/native-deps.properties 锁定 Release 资产与 sha256；下载后解压到
// build/native-deps/jniLibs/<abi>/，作为额外的 jniLibs 源目录参与打包。
val nativeDepsPropertiesFile = rootProject.file("native-deps.properties")
val nativeDepsJniDir = rootProject.layout.buildDirectory.dir("native-deps/jniLibs").get().asFile

val fetchNativeDeps = tasks.register("fetchNativeDeps") {
    group = "build"
    description = "下载并校验原生依赖包（proot/PHP）"

    val props = Properties()
    if (nativeDepsPropertiesFile.isFile) {
        nativeDepsPropertiesFile.inputStream().use { props.load(it) }
    }
    val repo = props.getProperty("repo").orEmpty()
    val tag = props.getProperty("tag").orEmpty()
    val asset = props.getProperty("asset").orEmpty()
    val sha256 = props.getProperty("sha256").orEmpty()

    inputs.property("repo", repo)
    inputs.property("tag", tag)
    inputs.property("asset", asset)
    inputs.property("sha256", sha256)
    outputs.dir(nativeDepsJniDir)

    doLast {
        if (repo.isBlank() || tag.isBlank() || asset.isBlank() || sha256.isBlank()) {
            throw GradleException(
                """
                android/native-deps.properties 缺少 repo/tag/asset/sha256。
                请先运行 GitHub Actions 的「构建原生依赖」工作流，
                再把 Release 资产的 sha256 填入该文件。
                """.trimIndent(),
            )
        }

        val marker = File(nativeDepsJniDir, ".sha256")
        if (marker.isFile && marker.readText().trim() == sha256) return@doLast

        nativeDepsJniDir.deleteRecursively()
        nativeDepsJniDir.mkdirs()
        val zipFile = rootProject.layout.buildDirectory
            .dir("tmp/native-deps/$asset").get().asFile
        zipFile.parentFile.mkdirs()

        val url = "https://github.com/$repo/releases/download/$tag/$asset"
        logger.lifecycle("下载原生依赖：$url")
        URI(url).toURL().openStream().use { input ->
            zipFile.outputStream().use { input.copyTo(it) }
        }

        val digest = MessageDigest.getInstance("SHA-256")
        zipFile.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        val actual = digest.digest().joinToString("") { "%02x".format(it) }
        if (!actual.equals(sha256, ignoreCase = true)) {
            zipFile.delete()
            throw GradleException("原生依赖 SHA256 不匹配：期望 $sha256，实际 $actual")
        }

        copy {
            from(zipTree(zipFile))
            into(nativeDepsJniDir)
        }
        zipFile.delete()

        val required = listOf(
            "libphp-cli.so",
            "lib__bin__proot-classic__.so",
            "lib__bin__busybox__.so",
            "libproot-loader-aarch64-5.1.107-68.so",
        )
        val missing = required.filterNot { File(nativeDepsJniDir, "arm64-v8a/$it").isFile }
        if (missing.isNotEmpty()) {
            nativeDepsJniDir.deleteRecursively()
            throw GradleException("原生依赖包缺少文件：${missing.joinToString()}")
        }
        marker.writeText(sha256)
    }
}

android {
    namespace = "com.venti1112.edgecube"
    compileSdk {
        version = release(37) {
            minorApiLevel = 2
        }
    }
    buildToolsVersion = "37.0.0"
    ndkVersion = "30.0.16248370"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
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
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "4.1.2"
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
        resources {
            excludes += setOf(
                "**/*.dll",
                "**/*.dylib",
            )
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDir(rustJniLibs)
            jniLibs.srcDir(nativeDepsJniDir)
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// AGP 在 afterEvaluate 之后才把 preBuild 之类的任务登记进来，
// 用 matching+configureEach 而不是 named：后者在登记前调用会直接抛。
tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn(cargoBuild, fetchNativeDeps)
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.core:core-ktx:1.19.0")
}

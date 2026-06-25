import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.venti1112.edgecube"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // SFTP（MINA SSHD）用到的 java.nio.file.* 在 minSdk 24 需要 core library desugaring。
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
            // 启用 R8 混淆时的 keep 规则（见 proguard-rules.pro）。
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
        // Apache 库（ftpserver/mina/ftplet 等）的 JAR 内含同名元数据文件，
        // 合并时冲突，排除这些不运行时不需要的文件。
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/*.kotlin_module",
                // zstd-jni/lz4-java 等 JAR 包含全平台原生库，排除非 Android 的 .dll/.dylib
                "**/*.dll",
                "**/*.dylib",
            )
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

dependencies {
    implementation("org.apache.commons:commons-compress:1.26.0")
    implementation("org.tukaani:xz:1.9")
    // zstd / lz4 / rar 解压支持（配合 commons-compress）。
    implementation("com.github.luben:zstd-jni:1.5.6-6")
    implementation("org.lz4:lz4-java:1.8.0")
    // commons-codec：FramedLZ4CompressorInputStream 依赖 XXHash32 校验。
    implementation("commons-codec:commons-codec:1.16.1")
    // junrar 依赖 slf4j-api；提供静态绑定实现以避免 R8 缺失类错误。
    implementation("org.slf4j:slf4j-api:1.7.36")
    implementation("org.slf4j:slf4j-jdk14:1.7.36")
    implementation("com.github.junrar:junrar:7.5.5")
    // FTP 服务器（ftpserver-core 依赖 mina-core 与 slf4j，slf4j 已引入）。
    implementation("org.apache.ftpserver:ftpserver-core:1.2.0")
    // SSH/SFTP 服务器（Apache MINA SSHD；与 FTP 的 Apache FTPServer 是相互独立的库）。
    // sshd-sftp 提供 SFTP 子系统；SSH 终端的 shell 通道桥接到自带 PTY（见 ssh/EcPtyInvertedShell.kt）。
    implementation("org.apache.sshd:sshd-core:2.15.0")
    implementation("org.apache.sshd:sshd-sftp:2.15.0")
    // Android 内置的是裁剪版 BouncyCastle，缺 EdDSA 等算法；显式打包补齐 SSH 握手所需算法
    // 与 host key 序列化（bcpkix）。SshServerManager 启动时会强制注册此 provider。
    implementation("org.bouncycastle:bcprov-jdk18on:1.78.1")
    implementation("org.bouncycastle:bcpkix-jdk18on:1.78.1")
    // core library desugaring 运行时库（配合上面的 isCoreLibraryDesugaringEnabled）。
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.2")
    implementation("androidx.core:core-ktx:1.13.1")
}

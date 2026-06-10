plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.venti1112.edgecube"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.venti1112.edgecube"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 为分发了 JRE 的三种 ABI 编译 liblaunch，与 assets/runtimes 下的 bin-<arch> 对应。
        ndk {
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86_64"))
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // 把 cpp/CMakeLists.txt 接入构建，产出 liblaunch.so 到 lib/<abi>/。
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    // useLegacyPackaging=true → 安装时把 native 库解压成真实文件，
    // 这样 nativeLibraryDir 下才有可被 ProcessBuilder 执行的 liblaunch.so。
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    // assets 里的 JRE 已是 tar.xz（XZ 压缩），禁止 AGP 再压一遍：
    // 既省不下体积，又会拖慢构建、阻止运行时直接流式读取。
    androidResources {
        noCompress += "tar.xz"
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
    // 解压 assets 里的 JRE（FCL 产物为 .tar.xz）。
    implementation("org.apache.commons:commons-compress:1.26.0")
    implementation("org.tukaani:xz:1.9")
    // 前台 Service 通知（NotificationCompat / ContextCompat）。Flutter 经 implementation
    // 传递引入但对 app 代码不可见，故显式声明。
    implementation("androidx.core:core-ktx:1.13.1")
}

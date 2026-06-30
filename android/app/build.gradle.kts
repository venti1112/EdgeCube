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
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/*.kotlin_module",
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
    implementation("org.apache.commons:commons-compress:1.28.0")
    implementation("org.tukaani:xz:1.12")
    implementation("com.github.luben:zstd-jni:1.5.7-11")
    implementation("org.lz4:lz4-java:1.8.0")
    implementation("commons-codec:commons-codec:1.22.0")
    implementation("org.slf4j:slf4j-api:2.0.18")
    implementation("org.slf4j:slf4j-jdk14:2.0.18")
    implementation("com.github.junrar:junrar:7.6.0")
    implementation("org.apache.ftpserver:ftpserver-core:1.2.1")
    implementation("org.apache.sshd:sshd-core:2.18.0")
    implementation("org.apache.sshd:sshd-sftp:2.18.0")
    implementation("org.bouncycastle:bcprov-jdk18on:1.84")
    implementation("org.bouncycastle:bcpkix-jdk18on:1.84")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.core:core-ktx:1.19.0")
}

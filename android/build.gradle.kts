allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// 全局固定工具链版本
gradle.beforeProject {
    val flutterExt = extensions.findByName("flutter")
    if (flutterExt != null) {
        try {
            var klass: Class<*>? = flutterExt.javaClass
            var field: java.lang.reflect.Field? = null
            while (klass != null && field == null) {
                try { field = klass.getDeclaredField("ndkVersion") }
                catch (e: NoSuchFieldException) { klass = klass.superclass }
            }
            if (field != null) {
                field.isAccessible = true
                field.set(flutterExt, "30.0.15729638")
            }
        } catch (e: Exception) {
            logger.warn("无法反射修改 flutter.ndkVersion: ${e.message}")
        }
    }

    plugins.withId("com.android.application") {
        extensions.findByType<com.android.build.api.dsl.ApplicationExtension>()?.apply {
            buildToolsVersion = "37.0.0"
            externalNativeBuild { cmake { version = "4.1.2" } }
        }
    }
    plugins.withId("com.android.library") {
        extensions.findByType<com.android.build.api.dsl.LibraryExtension>()?.apply {
            buildToolsVersion = "37.0.0"
            externalNativeBuild { cmake { version = "4.1.2" } }
        }
    }
    afterEvaluate {
        val libExt = extensions.findByType<com.android.build.api.dsl.LibraryExtension>()
        if (libExt != null) {
            libExt.compileSdk = 37
            libExt.compileSdkMinor = 1
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

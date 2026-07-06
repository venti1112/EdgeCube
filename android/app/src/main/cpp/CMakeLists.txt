cmake_minimum_required(VERSION 3.18.1)

project("edgecube_launch" C)

set(CMAKE_C_STANDARD 11)

# 这是一个可执行文件
add_executable(launch launcher.c)

# 关键技巧：把可执行文件的产物命名为 "liblaunch.so"。
# Android Gradle 插件按 *.so 收集 native 产物并打进 lib/<abi>/，安装后位于
# applicationInfo.nativeLibraryDir —— Android 允许从该目录执行 ELF。
# 文件后缀是 .so 不影响它是可执行 ELF：内核按 PT_INTERP 来 exec，与扩展名无关。
set_target_properties(launch PROPERTIES
        PREFIX "lib"
        SUFFIX ".so"
        OUTPUT_NAME "launch")

# PIE 在现代 NDK 是默认；显式声明以确保生成可被内核 exec 的 PT_INTERP。
target_compile_options(launch PRIVATE -fPIE)
target_link_options(launch PRIVATE -fPIE -pie)

# dl：dlopen/dlsym；log：__android_log_print（方便用 logcat 看启动器日志）。
target_link_libraries(launch dl log)

# LD_PRELOAD 标签修复库：拦截 malloc/free 以恢复 Android 堆指针标签
add_library(tagfix SHARED tagfix.c)
target_link_libraries(tagfix dl log)

# ─── libfrpcloader.so ─── frpc 启动器（dlopen 数据目录里的 libfrpc.so）
# 与 liblaunch.so 同构，但更简单：libfrpc.so 是 Go c-shared 自包含库，
# 运行期无额外 .so 依赖，故无需预加载、无需 tagfix。
add_executable(frpcloader frpcloader.c)

set_target_properties(frpcloader PROPERTIES
        PREFIX "lib"
        SUFFIX ".so"
        OUTPUT_NAME "frpcloader")

target_compile_options(frpcloader PRIVATE -fPIE)
target_link_options(frpcloader PRIVATE -fPIE -pie)
target_link_libraries(frpcloader dl log)

# ─── libdragonflyloader.so ─── Dragonfly 启动器（dlopen 数据目录里的 libdragonfly.so）
# 与 libfrpcloader.so 同构：Go c-shared 自包含库，运行期无额外 .so 依赖。
add_executable(dragonflyloader dragonflyloader.c)

set_target_properties(dragonflyloader PROPERTIES
        PREFIX "lib"
        SUFFIX ".so"
        OUTPUT_NAME "dragonflyloader")

target_compile_options(dragonflyloader PRIVATE -fPIE)
target_link_options(dragonflyloader PRIVATE -fPIE -pie)
target_link_libraries(dragonflyloader dl log)

# ─── libecpty.so ─── 伪终端（PTY）子进程启动器（普通 JNI 共享库）
# 与上面几个「伪装成 .so 的可执行文件」不同，这是真正的 JNI 共享库，
# 由 Kotlin 侧 System.loadLibrary("ecpty") 加载，提供 fork+/dev/ptmx 创建
# 带控制终端的子进程的能力（改编自 Termux 的 termux.c）。
add_library(ecpty SHARED ecpty.c)
target_link_libraries(ecpty log)

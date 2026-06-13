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

# ─── libphploader.so ─── PHP 启动器（dlopen libphpwrapper.so，与 liblaunch.so 同构）
add_executable(phploader phploader.c)

set_target_properties(phploader PROPERTIES
        PREFIX "lib"
        SUFFIX ".so"
        OUTPUT_NAME "phploader")

target_compile_options(phploader PRIVATE -fPIE)
target_link_options(phploader PRIVATE -fPIE -pie)
target_link_libraries(phploader dl log)

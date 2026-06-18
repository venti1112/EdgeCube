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

# ─── libtsrm_cache.so ─── PHP ZTS TLS 变量提供者
# 作为主可执行文件的 NEEDED 依赖，在进程启动时加载，
# 使 _tsrm_ls_cache 在初始 TLS 块中分配，IE 访问模型合法。
add_library(tsrm_cache SHARED tsrm_cache.c)
# -fno-emulated-tls：强制使用原生 TLS（非 emutls）。
# NDK 对 API < 29 默认使用 emutls，但 libphp.so 以原生 TLS 引用
# _tsrm_ls_cache，两者符号名不匹配（emutls 生成 __emutls_v._tsrm_ls_cache）。
# 注：旧写法 `-mllvm -emulated-tls=0` 在 NDK 28 的 Clang 19 下已不被识别
# （LLVM 移除了该内部选项），改用等价的 driver 标志 -fno-emulated-tls；
# 实测两者产物一致：_tsrm_ls_cache 为 Type=TLS 的原生 TLS 符号。
target_compile_options(tsrm_cache PRIVATE -ftls-model=initial-exec -fno-emulated-tls)

# ─── libphploader.so ─── PHP 启动器（dlopen libphpwrapper.so，与 liblaunch.so 同构）
add_executable(phploader phploader.c)

set_target_properties(phploader PROPERTIES
        PREFIX "lib"
        SUFFIX ".so"
        OUTPUT_NAME "phploader")

target_compile_options(phploader PRIVATE -fPIE)
target_link_options(phploader PRIVATE -fPIE -pie)
# 链接 libtsrm_cache.so → 它成为 NEEDED 依赖，进程启动时一起加载
target_link_libraries(phploader tsrm_cache dl log)

# ─── libfrpcloader.so ─── frpc 启动器（dlopen 数据目录里的 libfrpc.so）
# 与 liblaunch.so / libphploader.so 同构，但更简单：libfrpc.so 是 Go c-shared
# 自包含库，运行期无额外 .so 依赖，故无需预加载、无需 tsrm_cache、无需 tagfix。
add_executable(frpcloader frpcloader.c)

set_target_properties(frpcloader PROPERTIES
        PREFIX "lib"
        SUFFIX ".so"
        OUTPUT_NAME "frpcloader")

target_compile_options(frpcloader PRIVATE -fPIE)
target_link_options(frpcloader PRIVATE -fPIE -pie)
target_link_libraries(frpcloader dl log)

# ─── libecpty.so ─── 伪终端（PTY）子进程启动器（普通 JNI 共享库）
# 与上面几个「伪装成 .so 的可执行文件」不同，这是真正的 JNI 共享库，
# 由 Kotlin 侧 System.loadLibrary("ecpty") 加载，提供 fork+/dev/ptmx 创建
# 带控制终端的子进程的能力（改编自 Termux 的 termux.c）。
add_library(ecpty SHARED ecpty.c)
target_link_libraries(ecpty log)

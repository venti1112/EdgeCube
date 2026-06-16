/*
 * libfrpcloader.so —— EdgeCube 的 frpc 启动器（dlopen 版）
 *
 * 与 Java 的 liblaunch.so（dlopen libjli.so）、PHP 的 libphploader.so
 * （dlopen libphpwrapper.so）完全同构，但更简单：libfrpc.so 是 Go 以
 * c-shared 方式编译的自包含库，静态链接了所有 Go 依赖，运行期不依赖任何
 * 额外的 .so，因此无需像 PHP 那样预加载一长串依赖库。
 *
 * 背景：Android targetSdk >= 29 禁止 execve() 运行 app 私有数据目录里的
 * ELF（SELinux 对 app_data_file 拒绝 execute_no_trans），但仍允许 dlopen()
 * 其中的 .so。因此把这个极小的 PIE 可执行文件放进 nativeLibraryDir（lib
 * 目录，允许执行），由它去 dlopen 数据目录里的 libfrpc.so —— 引擎本体便可
 * 放在可写、可热更新、可独立于 APK 升级的 data 目录里。
 *
 * 本文件被「编译成可执行文件，但命名为 libfrpcloader.so」，这样 Android
 * Gradle 插件会把它打进 lib/<abi>/ 并安装到 nativeLibraryDir。它是真正的
 * 可执行 ELF，不是共享库。
 *
 * 优雅停止不在这里处理：libfrpc.so 内部已用 signal.Notify 监听 SIGINT/
 * SIGTERM 并调用 GracefulClose（见 frp 的 cmd/frpclib/frplib.go）。Go 运行时
 * 在被 dlopen 后会接管信号，若在此处再装 handler 反而会与之冲突，故从简。
 *
 * 父进程（Kotlin/ProcessBuilder）约定：
 *   env EC_FRPC_LIB    必填。libfrpc.so 的绝对路径（位于数据目录）。
 *   argv[1]            必填。frpc 配置文件（toml/yaml/json）的绝对路径。
 *   cwd                工作目录（ProcessBuilder.directory 设置）。
 */

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <android/log.h>

#define TAG "EdgeCubeFrpcLoader"

#define LOGE(...) \
    do { \
        __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__); \
        fprintf(stderr, "[frpcloader] "); \
        fprintf(stderr, __VA_ARGS__); \
        fputc('\n', stderr); \
        fflush(stderr); \
    } while (0)

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)

/* 对应 libfrpc.so 导出的 //export RunFrpc：int RunFrpc(char *configPath)。
 * 阻塞运行直到服务停止，返回退出码（0 正常，非 0 出错）。 */
typedef int (*run_frpc_t)(char *config_path);

int main(int argc, char **argv) {
    const char *frpc_lib = getenv("EC_FRPC_LIB");
    if (!frpc_lib || !frpc_lib[0]) {
        LOGE("EC_FRPC_LIB 未设置");
        return 1;
    }
    if (argc < 2 || !argv[1] || !argv[1][0]) {
        LOGE("缺少配置文件路径参数（argv[1]）");
        return 1;
    }

    LOGI("加载 %s, 配置 %s", frpc_lib, argv[1]);

    void *handle = dlopen(frpc_lib, RTLD_NOW | RTLD_GLOBAL);
    if (!handle) {
        LOGE("dlopen(%s) 失败: %s", frpc_lib, dlerror());
        return 1;
    }

    run_frpc_t run_frpc = (run_frpc_t) dlsym(handle, "RunFrpc");
    if (!run_frpc) {
        LOGE("dlsym(RunFrpc) 失败: %s", dlerror());
        dlclose(handle);
        return 1;
    }

    int ret = run_frpc(argv[1]);
    LOGI("RunFrpc 返回 %d", ret);

    /* 不 dlclose：Go 运行时不支持卸载，进程随 main 返回整体退出即可。 */
    return ret;
}

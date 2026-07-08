/*
 * libdragonflyloader.so —— EdgeCube 的 Dragonfly 启动器（dlopen 版）
 *
 * 与 frpc 的 libfrpcloader.so 完全同构：libdragonfly.so 是 Go 以 c-shared
 * 方式编译的自包含库，静态链接了所有 Go 依赖，运行期不依赖任何额外的 .so。
 *
 * 背景：Android targetSdk >= 29 禁止 execve() 运行 app 私有数据目录里的
 * ELF（SELinux 对 app_data_file 拒绝 execute_no_trans），但仍允许 dlopen()
 * 其中的 .so。因此把这个极小的 PIE 可执行文件放进 nativeLibraryDir（lib
 * 目录，允许执行），由它去 dlopen 数据目录里的 libdragonfly.so —— 引擎
 * 本体便可放在可写、可热更新、可独立于 APK 升级的 data 目录里。
 *
 * 本文件被「编译成可执行文件，但命名为 libdragonflyloader.so」，这样
 * Android Gradle 插件会把它打进 lib/<abi>/ 并安装到 nativeLibraryDir。
 * 它是真正的可执行 ELF，不是共享库。
 *
 * 父进程（Kotlin/EcPty）约定：
 *   env EC_DRAGONFLY_LIB    必填。libdragonfly.so 的绝对路径。
 *   argv[1]                 必填。config.yml 配置文件的绝对路径。
 *   cwd                     工作目录。
 */

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <android/log.h>

#define TAG "EdgeCubeDragonflyLoader"

#define LOGE(...) \
    do { \
        __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__); \
        fprintf(stderr, "[dragonflyloader] "); \
        fprintf(stderr, __VA_ARGS__); \
        fputc('\n', stderr); \
        fflush(stderr); \
    } while (0)

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)

/* 对应 libdragonfly.so 导出的 RunDragonfly：
 *   int RunDragonfly(const char *configPath);
 * 阻塞运行直到服务停止，返回退出码。 */
typedef int (*run_dragonfly_t)(const char *config_path);

int main(int argc, char **argv) {
    /* 强制立即输出到 stderr，确认 loader 在运行。 */
    fprintf(stderr, "[dragonflyloader] pid=%d started\n", (int)getpid());
    fflush(stderr);

    const char *dragonfly_lib = getenv("EC_DRAGONFLY_LIB");
    if (!dragonfly_lib || !dragonfly_lib[0]) {
        LOGE("EC_DRAGONFLY_LIB 未设置");
        return 1;
    }
    if (argc < 2 || !argv[1] || !argv[1][0]) {
        LOGE("缺少配置文件路径参数（argv[1]）");
        return 1;
    }

    LOGI("加载 %s, 配置 %s", dragonfly_lib, argv[1]);

    void *handle = dlopen(dragonfly_lib, RTLD_NOW | RTLD_GLOBAL);
    if (!handle) {
        const char *dl_err = dlerror();
        LOGE("dlopen(%s) 失败: %s", dragonfly_lib, dl_err ? dl_err : "(无错误信息)");
        return 1;
    }

    run_dragonfly_t run_dragonfly = (run_dragonfly_t) dlsym(handle, "RunDragonfly");
    if (!run_dragonfly) {
        const char *dl_err = dlerror();
        LOGE("dlsym(RunDragonfly) 失败: %s", dl_err ? dl_err : "(无错误信息)");
        dlclose(handle);
        return 1;
    }

    int ret = run_dragonfly(argv[1]);
    LOGI("RunDragonfly 返回 %d", ret);

    /* 不 dlclose：Go 运行时不支持卸载，进程随 main 返回整体退出即可。 */
    return ret;
}

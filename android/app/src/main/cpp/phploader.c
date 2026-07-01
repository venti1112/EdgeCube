/*
 * libphploader.so —— EdgeCube 的 PHP 启动器（dlopen 版）
 *
 * 与 Java 的 liblaunch.so（dlopen libjli.so）、frp 的 libfrpcloader.so
 * （dlopen libfrpc.so）完全同构：
 *   1. 从环境变量 EC_PHP_LIB 读取 libphpwrapper.so 的路径
 *      （libphpwrapper.so 内部使用 PHP embed SAPI，NEEDED 依赖 libphp.so）
 *   2. 预加载 libphp.so 的所有依赖与 libphp.so（RTLD_NOW | RTLD_GLOBAL）
 *   3. dlopen libphpwrapper.so
 *   4. dlsym php_run 并调用，PHP 在当前进程内执行 .phar 脚本
 *
 * 进程模型：
 *   Kotlin 侧通过 EcPty 在 PTY 上把这个可执行文件作为独立子进程拉起，
 *   stdin/stdout/stderr 直连 PTY 从设备，PHP 输出原样回显，命令行输入
 *   直接送达 PHP 的 fgets(STDIN)。崩溃只影响本进程，不拖累 Flutter UI。
 *
 * 父进程（Kotlin/ServerProcessManager）约定：
 *   env EC_PHP_LIB     必填。libphpwrapper.so 的绝对路径（位于运行时数据目录）。
 *   env LD_LIBRARY_PATH 须包含 libphp.so 所在目录，以便预加载依赖。
 *   env PHPRC          php.ini 所在目录（通常 ${RUNTIME_DIR}/bin）。
 *   env TMPDIR         可写临时目录（App cacheDir）。
 *   argv[1..]          PHP 脚本参数（如 PocketMine-MP.phar）。
 *   cwd                PHP 服务端工作目录。
 */

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <android/log.h>

#define TAG "EdgeCubePhpLoader"

#define LOGE(...)                                                        \
    do {                                                                 \
        __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__);        \
        fprintf(stderr, "[phploader] ");                                 \
        fprintf(stderr, __VA_ARGS__);                                    \
        fputc('\n', stderr);                                             \
        fflush(stderr);                                                  \
    } while (0)

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)

typedef int (*php_run_t)(int argc, char **argv);

/* 需要预加载的 PHP 依赖库列表（按依赖顺序）。
 *
 * Android linker 对 dlopen 的依赖搜索有限制：当 dlopen libphpwrapper.so
 * 时，linker 会自动加载其 NEEDED 依赖 libphp.so；但 libphp.so 自身的
 * NEEDED 依赖（libcrypto、libssl 等）必须已在进程命名空间中可见，否则
 * 加载失败。故先用 RTLD_NOW | RTLD_GLOBAL 预加载它们。
 *
 * libphp.so 放在最后，确保其间接依赖已经在 wrapper 之前准备好。
 *
 * 列表必须与 build.sh 中实际安装到 lib/ 的 .so 文件名一致。 */
static const char *PRELOAD_LIBS[] = {
    /* Android 系统库（不在 lib_dir 中，直接用短名称 dlopen） */
    "liblog.so",
    "libm.so",
    /* libc++_shared 必须最先加载——其它 C++ 库（leveldb 等）依赖它 */
    "libc++_shared.so",
    /* 基础加密 / 压缩 */
    "libcrypto.so",
    "libssl.so",
    "libz.so",
    "libdeflate.so",
    /* 数据格式 */
    "libxml2.so",
    "libyaml-0.so",
    "libzip.so",
    "libsqlite3.so",
    "libpng16.so",
    "libjpeg.so",
    /* 大数运算（PocketMine Bedrock 加密用） */
    "libgmp.so",
    /* 网络 */
    "libcurl.so",
    /* PocketMine 专用 */
    "libleveldb.so",
    /* PHP embed SAPI 本体 */
    "libphp.so",
    NULL
};

/* 从 EC_PHP_LIB 路径推导出 lib/ 目录，然后预加载所有依赖库。 */
static int preload_php_deps(const char *php_lib_path) {
    const char *last_slash = strrchr(php_lib_path, '/');
    if (!last_slash) {
        LOGE("EC_PHP_LIB 路径格式异常: %s", php_lib_path);
        return -1;
    }
    size_t dir_len = (size_t)(last_slash - php_lib_path);
    /* 最长的库名 + 目录前缀 + 斜杠 + NUL */
    char *lib_dir = (char *)malloc(dir_len + 64);
    if (!lib_dir) return -1;

    memcpy(lib_dir, php_lib_path, dir_len);
    lib_dir[dir_len] = '/';

    /* 系统库（不在 lib_dir 中，直接用短名称 dlopen） */
    static const char *SYSTEM_LIBS[] = {"liblog.so", "libm.so", NULL};

    int failures = 0;
    for (int i = 0; PRELOAD_LIBS[i] != NULL; i++) {
        const char *lib_name = PRELOAD_LIBS[i];
        int is_system = 0;
        for (int j = 0; SYSTEM_LIBS[j]; j++) {
            if (strcmp(lib_name, SYSTEM_LIBS[j]) == 0) {
                is_system = 1;
                break;
            }
        }
        /* 系统库用短名称，用户库用完整路径 */
        const char *path = is_system ? lib_name : (strcpy(lib_dir + dir_len + 1, lib_name), lib_dir);
        void *h = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
        if (!h) {
            /* dlerror() 只能调用一次——第一次返回错误信息并清除标志，
             * 第二次返回 NULL。必须先保存再使用。 */
            const char *err = dlerror();
            if (!err) err = "(无错误信息)";
            /* 某些可选库（如 libpng/libjpeg 仅 -g 构建时存在）可能缺失，
             * 警告但不视为致命错误——PHP 自身会在模块加载阶段报具体错。 */
            const char *optional[] = {"libpng16.so", "libjpeg.so", NULL};
            int is_optional = 0;
            for (int j = 0; optional[j]; j++) {
                if (strcmp(lib_name, optional[j]) == 0) {
                    is_optional = 1;
                    break;
                }
            }
            if (is_optional) {
                LOGI("可选库 %s 未找到，跳过: %s", lib_name, err);
            } else {
                LOGE("预加载 %s 失败: %s", path, err);
                failures++;
            }
        } else {
            LOGI("预加载 %s 成功", lib_name);
        }
    }

    free(lib_dir);
    return failures == 0 ? 0 : -1;
}

int main(int argc, char **argv) {
    const char *php_lib = getenv("EC_PHP_LIB");
    if (!php_lib || !php_lib[0]) {
        LOGE("EC_PHP_LIB 未设置");
        return 1;
    }

    LOGI("加载 %s, argc=%d", php_lib, argc);

    if (preload_php_deps(php_lib) != 0) {
        LOGE("预加载 PHP 依赖库失败");
        return 1;
    }

    void *handle = dlopen(php_lib, RTLD_NOW | RTLD_GLOBAL);
    if (!handle) {
        const char *err = dlerror();
        if (!err) err = "(无错误信息)";
        LOGE("dlopen(%s) 失败: %s", php_lib, err);
        return 1;
    }

    php_run_t php_run = (php_run_t)dlsym(handle, "php_run");
    if (!php_run) {
        const char *err = dlerror();
        if (!err) err = "(无错误信息)";
        LOGE("dlsym(php_run) 失败: %s", err);
        dlclose(handle);
        return 1;
    }

    /* 构造新 argv：argv[0]="php"（仅用于 PHP 错误消息显示），argv[1..]
     * 转发调用者参数（通常是 PocketMine-MP.phar 路径）。 */
    char **new_argv = (char **)malloc(sizeof(char *) * (size_t)(argc + 1));
    if (!new_argv) {
        LOGE("内存不足，无法构造 argv");
        dlclose(handle);
        return 1;
    }
    new_argv[0] = (char *)"php";
    for (int i = 1; i < argc; i++) new_argv[i] = argv[i];
    new_argv[argc] = NULL;

    LOGI("调用 php_run(%d, ...)", argc);

    int ret = php_run(argc, new_argv);

    free(new_argv);
    /* 不 dlclose：PHP 内部注册的 shutdown 函数可能与 dlclose 后的代码
     * 引用已卸载的符号。进程随 main 返回整体退出，由内核回收资源。 */
    return ret;
}

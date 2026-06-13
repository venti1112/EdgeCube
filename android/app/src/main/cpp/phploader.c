/*
 * libphploader.so —— EdgeCube 的 PHP 启动器（dlopen 版）
 *
 * 与 Java 的 liblaunch.so（dlopen libjli.so）完全同构：
 *   1. 从环境变量 EC_PHP_LIB 读取 libphpwrapper.so 的路径
 *      （libphpwrapper.so 内部调用 PHP embed SAPI，链接 libphp.so）
 *   2. dlopen libphpwrapper.so，调用 php_run(argc, argv)
 *   3. PHP 在当前进程运行，stdout/stderr 直接由父进程读取
 *
 * 父进程（Kotlin/ProcessBuilder）约定：
 *   env EC_PHP_LIB   必填。libphpwrapper.so 的绝对路径。
 *   argv[1..]         PHP 脚本参数（phar 路径）。
 *   cwd               PHP 服务端工作目录。
 *   LD_LIBRARY_PATH   须包含 libphp.so 所在目录，以便 dlopen 解析依赖。
 */

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <android/log.h>

#define TAG "EdgeCubePhpLoader"

#define LOGE(...) \
    do { \
        __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__); \
        fprintf(stderr, "[phploader] "); \
        fprintf(stderr, __VA_ARGS__); \
        fputc('\n', stderr); \
        fflush(stderr); \
    } while (0)

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)

typedef int (*php_run_t)(int argc, char **argv);

int main(int argc, char **argv) {
    const char *php_lib = getenv("EC_PHP_LIB");
    if (!php_lib || !php_lib[0]) {
        LOGE("EC_PHP_LIB 未设置");
        return 1;
    }

    LOGI("加载 %s, argc=%d", php_lib, argc);

    void *handle = dlopen(php_lib, RTLD_NOW | RTLD_GLOBAL);
    if (!handle) {
        LOGE("dlopen(%s) 失败: %s", php_lib, dlerror());
        return 1;
    }

    php_run_t php_run = (php_run_t) dlsym(handle, "php_run");
    if (!php_run) {
        LOGE("dlsym(php_run) 失败: %s", dlerror());
        dlclose(handle);
        return 1;
    }

    /* 构造新 argv：argv[0]="php"，argv[1..] 转发调用者参数 */
    char **new_argv = (char **) malloc(sizeof(char *) * (size_t)(argc + 1));
    new_argv[0] = "php";
    for (int i = 1; i < argc; i++) new_argv[i] = argv[i];
    new_argv[argc] = NULL;

    LOGI("调用 php_run(%d, ...)", argc);

    int ret = php_run(argc, new_argv);

    free(new_argv);
    dlclose(handle);
    return ret;
}

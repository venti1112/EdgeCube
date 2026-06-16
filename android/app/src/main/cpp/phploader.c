/*
 * libphploader.so —— EdgeCube 的 PHP 启动器（dlopen 版）
 *
 * 与 Java 的 liblaunch.so（dlopen libjli.so）完全同构：
 *   1. 从环境变量 EC_PHP_LIB 读取 libphpwrapper.so 的路径
 *      （libphpwrapper.so 内部调用 PHP embed SAPI，链接 libphp.so）
 *   2. 预加载 libphp.so 的所有间接依赖（RTLD_NOW | RTLD_GLOBAL）
 *   3. dlopen libphpwrapper.so（NEEDED libphp.so）
 *   4. libphp.so 以 IE 模式引用 _tsrm_ls_cache，该符号由
 *      libtsrm_cache.so 提供（主可执行文件的 NEEDED 依赖，进程启动时加载）
 *   5. PHP 在当前进程运行，stdout/stderr 直接由父进程读取
 *
 * 父进程（Kotlin/ProcessBuilder）约定：
 *   env EC_PHP_LIB   必填。libphpwrapper.so 的绝对路径。
 *   argv[1..]         PHP 脚本参数（phar 路径）。
 *   cwd               PHP 服务端工作目录。
 *   LD_LIBRARY_PATH   须包含 libphp.so 所在目录，以便预加载依赖。
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

/* 需要预加载的 PHP 依赖库列表（按依赖顺序）。
 * Android linker 对 dlopen 的依赖搜索有限制，
 * 必须先用 RTLD_NOW | RTLD_GLOBAL 预加载，后续 dlopen 才能找到。
 *
 * 注意：libphp.so 不在此列表中！它由 libphpwrapper.so 的 NEEDED
 * 条目自动触发加载。_tsrm_ls_cache 由 libtsrm_cache.so 提供
 * （主可执行文件的 NEEDED 依赖，进程启动时已加载）。 */
static const char *PRELOAD_LIBS[] = {
    "libcrypto.so",
    "libssl.so",
    "libdeflate.so",
    "libpng16.so",
    "libjpeg.so",
    "libyaml-0.so",
    "libleveldb.so",
    "libxml2.so",
    "libzip.so",
    "libsqlite3.so",
    "libcurl.so",
    "libc++_shared.so",
    NULL
};

/* 从 EC_PHP_LIB 路径推导出 lib/ 目录，然后预加载所有依赖库。 */
static int preload_php_deps(const char *php_lib_path) {
    /* 从 .../lib/libphpwrapper.so 推导 .../lib/ 目录 */
    const char *last_slash = strrchr(php_lib_path, '/');
    if (!last_slash) {
        LOGE("EC_PHP_LIB 路径格式异常: %s", php_lib_path);
        return -1;
    }
    size_t dir_len = (size_t)(last_slash - php_lib_path);
    char *lib_dir = (char *)malloc(dir_len + 256);
    if (!lib_dir) return -1;

    memcpy(lib_dir, php_lib_path, dir_len);
    lib_dir[dir_len] = '/';

    for (int i = 0; PRELOAD_LIBS[i] != NULL; i++) {
        strcpy(lib_dir + dir_len + 1, PRELOAD_LIBS[i]);
        void *h = dlopen(lib_dir, RTLD_NOW | RTLD_GLOBAL);
        if (!h) {
            LOGE("预加载 %s 失败: %s", lib_dir, dlerror());
            free(lib_dir);
            return -1;
        }
        LOGI("预加载 %s 成功", PRELOAD_LIBS[i]);
    }

    free(lib_dir);
    return 0;
}

int main(int argc, char **argv) {
    const char *php_lib = getenv("EC_PHP_LIB");
    if (!php_lib || !php_lib[0]) {
        LOGE("EC_PHP_LIB 未设置");
        return 1;
    }

    LOGI("加载 %s, argc=%d", php_lib, argc);

    /* 先预加载所有依赖库 */
    if (preload_php_deps(php_lib) != 0) {
        LOGE("预加载 PHP 依赖库失败");
        return 1;
    }

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

/*
 * liblaunch.so —— EdgeCube 的独立 JVM 启动器（其实是个可执行 ELF，不是库）
 *
 * 背景：
 *   Android targetSdk >= 29 禁止 execve() 运行 app 私有数据目录里的 ELF
 *   （SELinux 对 app_data_file 拒绝 execute_no_trans），但仍允许 dlopen()
 *   其中的 .so（execute 是放行的）。因此我们没法直接跑 JRE 自带的 bin/java，
 *   但可以把这个极小的 PIE 可执行文件放进 app 的 nativeLibraryDir（lib 目录，
 *   是唯一允许执行的可写位置之外的特例），由它去 dlopen JRE 的 libjli.so 并调用
 *   JLI_Launch —— 这正是 bin/java 自己做的事。JRE 本体则放在可写、可热更新、
 *   可多版本共存的 data 目录里。
 *
 *   本文件被「编译成可执行文件，但命名为 liblaunch.so」，这样 Android Gradle
 *   插件会把它打进 lib/<abi>/ 并安装到 applicationInfo.nativeLibraryDir。它是
 *   真正的可执行 ELF，不是共享库。
 *
 * 进程模型：
 *   Kotlin 侧用 ProcessBuilder 把它作为「独立进程」拉起，所以每个服务端实例彼此
 *   隔离、可单独 kill；JVM 崩溃不会拖垮 Flutter UI。无需 JNI、无需进程内 dlopen
 *   那一套、无需 exit hook —— 进程内那些复杂度全省掉。
 *
 * 父进程（Kotlin/ProcessBuilder）需在 exec 前约定好：
 *   env JAVA_HOME        必填。JRE home；argv[0] 会被设为 "$JAVA_HOME/bin/java"。
 *   env LD_LIBRARY_PATH  JRE 的各 lib 目录（+ 系统目录）。exec 时被 linker 原生
 *                        读入默认命名空间，JVM 后续自己的 dlopen 才能解析到。
 *   env EC_LIBJLI        选填。libjli.so 的绝对路径。不填则回退到按名字
 *                        dlopen("libjli.so")，依赖 LD_LIBRARY_PATH。
 *   argv[1..]            java 参数，例如 -Xmx2G -jar server.jar nogui
 *   cwd                  服务端工作目录（ProcessBuilder.directory 设置）。
 *
 * 重要前提：
 *   必须使用 Pojav/FCL 那类「为 Android(bionic) 编译、且 launcher 改为从 argv[0]
 *   定位 home」的 JRE。通用 Linux(glibc) 的 OpenJDK 既不兼容 bionic，其 launcher
 *   也靠 /proc/self/exe 定位 home（此处会指向 liblaunch.so，定位失败）。
 */

#include <dlfcn.h>
#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <android/log.h>

/* ARM64 Tagged Pointers (TBI) 修复：
 *
 * Android 11+ (API 31+) 默认启用堆指针标签。JVM 内部会改写指针高位字节作为
 * 元数据区，释放时标签校验失败导致 SIGABRT（退出码 134）。
 *
 * 正确做法：在 JVM 启动前用 mallopt(M_BIONIC_SET_HEAP_TAGGING_LEVEL, 0)
 * 通知 bionic 分配器「不再给新分配的内存打标签」。这样已有堆指针不受影响，
 * JVM 后续分配没有标签，改写高位字节不被拦截。
 *
 * 注意：不能用 prctl(PR_SET_TAGGED_ADDR_CTRL, 0) 关闭内核 TBI，
 * 否则 bionic 内部带标签的指针直接损坏。
 *
 * mallopt/M_BIONIC_SET_HEAP_TAGGING_LEVEL 在某些 NDK 版本的头文件里
 * 未声明，故用 dlopen + dlsym 运行时调用以兼容所有 NDK。
 */
#define TAG "EdgeCubeLaunch"

#define LOGE(...)                                               \
    do {                                                        \
        __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__); \
        fprintf(stderr, __VA_ARGS__);                           \
        fputc('\n', stderr);                                    \
        fflush(stderr);                                         \
    } while (0)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)

/* Android 15+ (MTE 硬件) 的堆标签兼容方案 */
static void disable_heap_tagging(void) {
    int (*mallopt_ptr)(int, int) = dlsym(RTLD_DEFAULT, "mallopt");
    if (mallopt_ptr) {
        int r = mallopt_ptr(55, 0);
        LOGI("disable_heap_tagging: mallopt(55,0) returned %d", r);
        if (r) return;
    }
    bool (*android_mp)(int, void*, size_t) = dlsym(RTLD_DEFAULT, "android_mallopt");
    if (android_mp) { int lv = 0; android_mp(8, &lv, sizeof(lv)); }
}

/*
 * JLI_Launch —— libjli.so 里真正的入口，和 bin/java 调用的完全一致。
 * 签名在 OpenJDK 8..21 之间稳定。jint = int(4B)，jboolean = unsigned char(1B)。
 */
typedef int JLI_Launch_t(
        int argc, char **argv,                  /* main argc, argv          */
        int jargc, const char **jargv,          /* java 内置参数            */
        int appclassc, const char **appclassv,  /* app classpath            */
        const char *fullversion,                /* 完整版本串（仅展示用）   */
        const char *dotversion,                 /* 点分版本串（仅展示用）   */
        const char *pname,                      /* program name             */
        const char *lname,                      /* launcher name            */
        unsigned char javaargs,                 /* 是否 JAVA_ARGS           */
        unsigned char cpwildcard,               /* 是否展开 classpath 通配  */
        unsigned char javaw,                    /* 仅 Windows 的 javaw      */
        int ergo);                              /* ergonomics 策略          */

/* 在 JRE 目录的 lib/ 下递归搜索 .so 并用 dlopen 预加载。
 * 与 FCL 的 setUpJavaRuntime / bridge.dlopen 一致，确保所有 JRE 原生库
 * 在 JVM 启动前已加载到进程命名空间。 */
static void preload_jre_libs(const char *java_home) {
    char lib_path[PATH_MAX];
    snprintf(lib_path, sizeof(lib_path), "%s/lib", java_home);
    /* FCL 明确按此顺序 dlopen 的关键库 */
    const char *targets[] = {
        "libjvm.so", "libverify.so", "libjava.so",
        "libnet.so", "libnio.so", "libzip.so",
        NULL
    };
    /* 递归遍历 lib/ 目录找目标 .so */
    char stack[64][PATH_MAX];
    int top = 0;
    snprintf(stack[top++], sizeof(stack[0]), "%s", lib_path);
    while (top > 0) {
        char *dir = stack[--top];
        DIR *d = opendir(dir);
        if (d == NULL) continue;
        struct dirent *e;
        while ((e = readdir(d)) != NULL) {
            char full[PATH_MAX];
            snprintf(full, sizeof(full), "%s/%s", dir, e->d_name);
            if (e->d_type == DT_DIR) {
                if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0)
                    continue;
                if (top < 64) {
                    snprintf(stack[top++], sizeof(stack[0]), "%s", full);
                }
            } else if (e->d_type == DT_REG || e->d_type == DT_LNK) {
                for (int t = 0; targets[t] != NULL; t++) {
                    if (strcmp(e->d_name, targets[t]) == 0) {
                        /* 用 RTLD_NOW 确保符号全部解析，与 FCL 的 dlopen 一致 */
                        void *h = dlopen(full, RTLD_NOW | RTLD_GLOBAL);
                        if (h != NULL) {
                            LOGI("preloaded %s", full);
                        } else {
                            LOGI("preload %s failed: %s", full, dlerror());
                        }
                        break;
                    }
                }
            }
        }
        closedir(d);
    }
}

int main(int argc, char **argv) {
    /* Android 11+ (API 31+)：关闭堆指针标签，防止 JVM 改写指针高位字节
     * 触发 SIGABRT。必须在任何 JVM 内存分配之前调用。 */
    disable_heap_tagging();

    const char *java_home = getenv("JAVA_HOME");
    if (java_home == NULL || java_home[0] == '\0') {
        LOGE("JAVA_HOME 未设置，无法定位 JRE。");
        return 1;
    }

    /* 解析 libjli.so：优先用显式绝对路径，否则交给父进程已设好的 LD_LIBRARY_PATH。 */
    const char *libjli_path = getenv("EC_LIBJLI");
    if (libjli_path == NULL || libjli_path[0] == '\0') {
        libjli_path = "libjli.so";
    }

    LOGI("JAVA_HOME=%s", java_home);
    LOGI("loading %s", libjli_path);

    /* 预加载 JRE 原生库（与 FCL 的 setUpJavaRuntime / bridge.dlopen 一致）。 */
    preload_jre_libs(java_home);

    /* RTLD_GLOBAL：让 JVM 后续加载的库能解析到 libjli 的符号。
     * RTLD_LAZY：与 FCL 一致，libjli 的部分符号要到运行时才由 libjvm 等补齐。 */
    void *libjli = dlopen(libjli_path, RTLD_LAZY | RTLD_GLOBAL);
    if (libjli == NULL) {
        LOGE("dlopen(%s) 失败: %s", libjli_path, dlerror());
        return 1;
    }

    JLI_Launch_t *JLI_Launch = (JLI_Launch_t *) dlsym(libjli, "JLI_Launch");
    if (JLI_Launch == NULL) {
        LOGE("dlsym(JLI_Launch) 失败: %s", dlerror());
        return 1;
    }

    /*
     * 拼出 JRE 期望的 argv。argv[0] 必须是 "<home>/bin/java"：被打过补丁的
     * launcher 据此推导 JRE home。其余原样转发调用者传入的 java 参数。
     */
    char java_bin[PATH_MAX];
    snprintf(java_bin, sizeof(java_bin), "%s/bin/java", java_home);

    char **jli_argv = (char **) malloc(sizeof(char *) * (argc + 1));
    if (jli_argv == NULL) {
        LOGE("内存不足，无法构造 argv");
        return 1;
    }
    jli_argv[0] = java_bin;
    for (int i = 1; i < argc; i++) {
        jli_argv[i] = argv[i];
    }
    jli_argv[argc] = NULL;

    LOGI("调用 JLI_Launch，共 %d 个参数", argc);

    /*
     * 清除所有信号处理器，为 JVM 提供干净的信号处理环境。
     * 与 FoldCraftLauncher jre_launcher.c 做法一致。
     */
    struct sigaction clean_sa;
    memset(&clean_sa, 0, sizeof(struct sigaction));
    for (int sigid = SIGHUP; sigid < NSIG; sigid++) {
        if (sigid == SIGSEGV)
            clean_sa.sa_handler = SIG_IGN;
        else
            clean_sa.sa_handler = SIG_DFL;
        sigaction(sigid, &clean_sa, NULL);
    }

    /* 让标准输出的缓冲模式与 JVM 期望的一致 */
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    /*
     * 交出控制权给 JVM。对服务端而言这里会一直阻塞到 JVM 退出；之后 JLI 以进程
     * 退出码返回（或直接 exit）。无论哪种，本进程都以正确退出码结束，父进程通过
     * Process.waitFor() 拿到。
     */
    int ret = JLI_Launch(argc, jli_argv,
                         0, NULL,
                         0, NULL,
                         "1.8.0-internal", /* fullversion：仅展示，跨版本无碍   */
                         "1.8",            /* dotversion：同上                   */
                         "java",           /* pname                              */
                         "openjdk",        /* lname                              */
                         0 /* 非 JAVA_ARGS        */,
                         1 /* 展开 classpath 通配 */,
                         0 /* 非 javaw            */,
                         0 /* 默认 ergonomics 策略 */);

    free(jli_argv);
    return ret;
}

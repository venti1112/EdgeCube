/*
 * libecpty.so —— EdgeCube 的伪终端（PTY）子进程启动器（JNI 共享库）
 *
 * 背景：
 *   原先服务端用 Kotlin 的 ProcessBuilder 拉起，stdin/stdout 是普通管道，程序
 *   isatty() 为假——拿不到真正的终端，于是没有行编辑、Tab 补全、JLine 控制台、
 *   也没有原生 ANSI 着色。为做「交互式终端」，改为在 /dev/ptmx 上开一对伪终端：
 *   主设备 fd 留在 app 进程里读写，子进程把从设备当作 stdin/stdout/stderr。
 *   这样服务端就跑在真实 TTY 上，终端能力全部可用。
 *
 *   本实现改编自 Termux 的 terminal-emulator/src/main/jni/termux.c
 *   （Apache License 2.0），仅保留 PTY 创建 / 窗口尺寸 / waitpid / close 四个原语，
 *   ANSI/VT 解析交给 Flutter 侧的 xterm.dart 完成。
 *
 *   与 liblaunch.so 的衔接：子进程直接 execvp(liblaunch.so, argv)，环境变量
 *   （JAVA_HOME / LD_LIBRARY_PATH / EC_LIBJLI / LD_PRELOAD …）经 envp 传入，
 *   与原 ProcessBuilder 路径完全等价——只是 stdio 换成了 PTY 从设备。
 *
 * JNI 对应 Kotlin 类：com.venti1112.edgecube.server.EcPty
 */

#include <dirent.h>
#include <fcntl.h>
#include <jni.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#define EC_UNUSED(x) x __attribute__((__unused__))

static int throw_runtime_exception(JNIEnv* env, char const* message)
{
    jclass exClass = (*env)->FindClass(env, "java/lang/RuntimeException");
    (*env)->ThrowNew(env, exClass, message);
    return -1;
}

static int create_subprocess(JNIEnv* env,
        char const* cmd,
        char const* cwd,
        char* const argv[],
        char** envp,
        int* pProcessId,
        jint rows,
        jint columns,
        jint cell_width,
        jint cell_height)
{
    int ptm = open("/dev/ptmx", O_RDWR | O_CLOEXEC);
    if (ptm < 0) return throw_runtime_exception(env, "Cannot open /dev/ptmx");

    char devname[64];
    if (grantpt(ptm) || unlockpt(ptm) || ptsname_r(ptm, devname, sizeof(devname))) {
        return throw_runtime_exception(env, "Cannot grantpt()/unlockpt()/ptsname_r() on /dev/ptmx");
    }

    // 开启 UTF-8 模式，并关闭软件流控，避免 Ctrl+S 把显示锁死。
    struct termios tios;
    tcgetattr(ptm, &tios);
    tios.c_iflag |= IUTF8;
    tios.c_iflag &= ~(IXON | IXOFF);
    tcsetattr(ptm, TCSANOW, &tios);

    // 设定初始窗口尺寸，连接的程序据此得知屏幕大小。
    struct winsize sz = {
        .ws_row = (unsigned short) rows,
        .ws_col = (unsigned short) columns,
        .ws_xpixel = (unsigned short) (columns * cell_width),
        .ws_ypixel = (unsigned short) (rows * cell_height),
    };
    ioctl(ptm, TIOCSWINSZ, &sz);

    pid_t pid = fork();
    if (pid < 0) {
        return throw_runtime_exception(env, "Fork failed");
    } else if (pid > 0) {
        // 父进程：返回主设备 fd 与子进程 pid。
        *pProcessId = (int) pid;
        return ptm;
    } else {
        // 子进程：解除 Android Java 进程可能屏蔽的信号。
        sigset_t signals_to_unblock;
        sigfillset(&signals_to_unblock);
        sigprocmask(SIG_UNBLOCK, &signals_to_unblock, 0);

        close(ptm);
        setsid();

        int pts = open(devname, O_RDWR);
        if (pts < 0) exit(-1);

        // 从设备作为 stdin/stdout/stderr，并成为控制终端。
        dup2(pts, 0);
        dup2(pts, 1);
        dup2(pts, 2);

        // 关闭从父进程继承来的其它 fd，避免泄漏。
        DIR* self_dir = opendir("/proc/self/fd");
        if (self_dir != NULL) {
            int self_dir_fd = dirfd(self_dir);
            struct dirent* entry;
            while ((entry = readdir(self_dir)) != NULL) {
                int fd = atoi(entry->d_name);
                if (fd > 2 && fd != self_dir_fd) close(fd);
            }
            closedir(self_dir);
        }

        clearenv();
        if (envp) for (; *envp; ++envp) putenv(*envp);

        if (chdir(cwd) != 0) {
            char* error_message;
            if (asprintf(&error_message, "chdir(\"%s\")", cwd) == -1) error_message = "chdir()";
            perror(error_message);
            fflush(stderr);
        }
        execvp(cmd, argv);
        // exec 失败时把错误打到终端，便于排查。
        char* error_message;
        if (asprintf(&error_message, "exec(\"%s\")", cmd) == -1) error_message = "exec()";
        perror(error_message);
        _exit(1);
    }
}

JNIEXPORT jint JNICALL Java_com_venti1112_edgecube_server_EcPty_createSubprocess(
        JNIEnv* env,
        jclass EC_UNUSED(clazz),
        jstring cmd,
        jstring cwd,
        jobjectArray args,
        jobjectArray envVars,
        jintArray processIdArray,
        jint rows,
        jint columns,
        jint cell_width,
        jint cell_height)
{
    jsize size = args ? (*env)->GetArrayLength(env, args) : 0;
    char** argv = NULL;
    if (size > 0) {
        argv = (char**) malloc((size + 1) * sizeof(char*));
        if (!argv) return throw_runtime_exception(env, "Couldn't allocate argv array");
        for (int i = 0; i < size; ++i) {
            jstring arg_java_string = (jstring) (*env)->GetObjectArrayElement(env, args, i);
            char const* arg_utf8 = (*env)->GetStringUTFChars(env, arg_java_string, NULL);
            if (!arg_utf8) return throw_runtime_exception(env, "GetStringUTFChars() failed for argv");
            argv[i] = strdup(arg_utf8);
            (*env)->ReleaseStringUTFChars(env, arg_java_string, arg_utf8);
        }
        argv[size] = NULL;
    }

    size = envVars ? (*env)->GetArrayLength(env, envVars) : 0;
    char** envp = NULL;
    if (size > 0) {
        envp = (char**) malloc((size + 1) * sizeof(char *));
        if (!envp) return throw_runtime_exception(env, "malloc() for envp array failed");
        for (int i = 0; i < size; ++i) {
            jstring env_java_string = (jstring) (*env)->GetObjectArrayElement(env, envVars, i);
            char const* env_utf8 = (*env)->GetStringUTFChars(env, env_java_string, 0);
            if (!env_utf8) return throw_runtime_exception(env, "GetStringUTFChars() failed for env");
            envp[i] = strdup(env_utf8);
            (*env)->ReleaseStringUTFChars(env, env_java_string, env_utf8);
        }
        envp[size] = NULL;
    }

    int procId = 0;
    char const* cmd_cwd = (*env)->GetStringUTFChars(env, cwd, NULL);
    char const* cmd_utf8 = (*env)->GetStringUTFChars(env, cmd, NULL);
    int ptm = create_subprocess(env, cmd_utf8, cmd_cwd, argv, envp, &procId, rows, columns, cell_width, cell_height);
    (*env)->ReleaseStringUTFChars(env, cmd, cmd_utf8);
    (*env)->ReleaseStringUTFChars(env, cwd, cmd_cwd);

    if (argv) {
        for (char** tmp = argv; *tmp; ++tmp) free(*tmp);
        free(argv);
    }
    if (envp) {
        for (char** tmp = envp; *tmp; ++tmp) free(*tmp);
        free(envp);
    }

    int* pProcId = (int*) (*env)->GetPrimitiveArrayCritical(env, processIdArray, NULL);
    if (!pProcId) return throw_runtime_exception(env, "JNI call GetPrimitiveArrayCritical(processIdArray, &isCopy) failed");

    *pProcId = procId;
    (*env)->ReleasePrimitiveArrayCritical(env, processIdArray, pProcId, 0);

    return ptm;
}

JNIEXPORT void JNICALL Java_com_venti1112_edgecube_server_EcPty_setPtyWindowSize(
        JNIEnv* EC_UNUSED(env), jclass EC_UNUSED(clazz),
        jint fd, jint rows, jint cols, jint cell_width, jint cell_height)
{
    struct winsize sz = {
        .ws_row = (unsigned short) rows,
        .ws_col = (unsigned short) cols,
        .ws_xpixel = (unsigned short) (cols * cell_width),
        .ws_ypixel = (unsigned short) (rows * cell_height),
    };
    ioctl(fd, TIOCSWINSZ, &sz);
}

JNIEXPORT jint JNICALL Java_com_venti1112_edgecube_server_EcPty_waitFor(
        JNIEnv* EC_UNUSED(env), jclass EC_UNUSED(clazz), jint pid)
{
    int status;
    waitpid(pid, &status, 0);
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        return -WTERMSIG(status);
    } else {
        return 0;
    }
}

JNIEXPORT void JNICALL Java_com_venti1112_edgecube_server_EcPty_setPtyEcho(
        JNIEnv* EC_UNUSED(env), jclass EC_UNUSED(clazz), jint fd, jboolean echo)
{
    struct termios tios;
    if (tcgetattr(fd, &tios) != 0) return;
    if (echo) {
        tios.c_lflag |= ECHO;
    } else {
        tios.c_lflag &= ~((tcflag_t)ECHO);
    }
    tcsetattr(fd, TCSANOW, &tios);
}

JNIEXPORT void JNICALL Java_com_venti1112_edgecube_server_EcPty_close(
        JNIEnv* EC_UNUSED(env), jclass EC_UNUSED(clazz), jint fileDescriptor)
{
    close(fileDescriptor);
}

/*
 * libtsrm_cache.so —— 提供 PHP ZTS 的 _tsrm_ls_cache TLS 变量。
 *
 * _tsrm_ls_cache 是 PHP ZTS 模式的 __thread 变量（ts_rsrc_id *），
 * 被 libphp.so 以 IE（Initial Exec）TLS 访问模型引用。
 *
 * Android linker 禁止 dlopened 库中定义的 TLS 变量被 IE 模式引用，
 * 因此该变量不能放在 libphpwrapper.so（dlopen 加载）中。
 *
 * 解决方案：将 _tsrm_ls_cache 放在独立的 libtsrm_cache.so 中，
 * 作为主可执行文件 libphploader.so 的 NEEDED 依赖。这样：
 *   - libtsrm_cache.so 在进程启动时随主可执行文件一起加载
 *   - 其 TLS 变量在初始 TLS 块中分配，IE 访问模型合法
 *   - 其导出符号对后续 dlopen 的库可见
 */

#include <stddef.h>

__attribute__((visibility("default")))
__attribute__((tls_model("initial-exec")))
__thread void *_tsrm_ls_cache = NULL;

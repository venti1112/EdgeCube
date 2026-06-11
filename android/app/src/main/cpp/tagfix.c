#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* 在用户数据前面多分配 8 字节，存储指针标签，free 时恢复 */
#define HDR sizeof(uintptr_t)

static void* (*real_m)(size_t) = NULL;
static void  (*real_f)(void*) = NULL;
static void* (*real_r)(void*, size_t) = NULL;

static int resolved;

static void do_resolve(void) {
    void* h = dlopen("libc.so", RTLD_LAZY | RTLD_NOLOAD);
    if (!h) h = dlopen("libc.so", RTLD_LAZY);
    if (h) {
        real_m = dlsym(h, "malloc");
        real_f = dlsym(h, "free");
        real_r = dlsym(h, "realloc");
    }
    resolved = 1;
}

__attribute__((constructor)) void init(void) { do_resolve(); }

void* malloc(size_t s) {
    if (!resolved) do_resolve();
    void* p = real_m(s + HDR);
    if (p) { *(uintptr_t*)p = ((uintptr_t)p >> 56); return (void*)((uintptr_t)p + HDR); }
    return NULL;
}

void free(void* p) {
    if (!resolved) do_resolve();
    if (!p) return;
    void* base = (void*)((uintptr_t)p - HDR);
    uintptr_t wanted = *(uintptr_t*)base;
    uintptr_t addr   = (uintptr_t)base;
    uintptr_t curr   = addr >> 56;
    if (curr != wanted) addr = (addr & 0x00FFFFFFFFFFFFFFULL) | (wanted << 56);
    real_f((void*)addr);
}

void* calloc(size_t n, size_t s) {
    if (!resolved) do_resolve();
    size_t total = n * s + HDR;
    void* p = real_m(total);
    if (p) {
        *(uintptr_t*)p = ((uintptr_t)p >> 56);
        void* up = (void*)((uintptr_t)p + HDR);
        memset(up, 0, total - HDR);
        return up;
    }
    return NULL;
}

/* aligned_alloc / posix_memalign: JVM 极少用，直接透传 */
int posix_memalign(void** mp, size_t a, size_t s) {
    if (!resolved) do_resolve();
    static int (*real)(void**, size_t, size_t) = NULL;
    if (!real) real = dlsym(RTLD_NEXT, "posix_memalign");
    return real(mp, a, s);
}

void* realloc(void* p, size_t s) {
    if (!resolved) do_resolve();
    if (!p) return malloc(s);
    void* base = (void*)((uintptr_t)p - HDR);
    uintptr_t addr = (uintptr_t)base;
    uintptr_t wanted = *(uintptr_t*)base;
    uintptr_t curr = addr >> 56;
    if (curr != wanted) addr = (addr & 0x00FFFFFFFFFFFFFFULL) | (wanted << 56);
    void* np = real_r((void*)addr, s + HDR);
    if (np) {
        *(uintptr_t*)np = ((uintptr_t)np >> 56);
        return (void*)((uintptr_t)np + HDR);
    }
    return NULL;
}

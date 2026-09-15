#!/bin/bash
# ============================================================
# proot 交叉编译脚本 (EdgeCube)
#
# 用法:
#   ./build.sh [ABI] [VERSION]
#
#   ABI      目标架构: arm64-v8a (默认) | armeabi-v7a | x86_64 | x86
#   VERSION  版本标识, 无参数时使用 proot 仓库的短 hash
#
# 依赖:
#   - Android NDK 29 (位于 ~/AndroidSDK/ndk/29.0.14206865)
#   - make, wget, tar, sha256sum
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_DIR="$HOME/.build/proot"
OUTPUT_DIR="$REPO_DIR/app/android/app/src/main/jniLibs"

# ---- 默认参数 ----
ABI="${1:-arm64-v8a}"
VERSION="${2:-}"

# ---- ABI -> NDK 映射 ----
# 格式: CC_TARGET:NDK_TRIPLE:JNI_ABI
declare -A ABI_MAP
ABI_MAP["arm64-v8a"]="aarch64-linux-android24:aarch64-linux-android:arm64-v8a"
ABI_MAP["armeabi-v7a"]="armv7a-linux-androideabi24:armv7a-linux-androideabi:armeabi-v7a"
ABI_MAP["x86_64"]="x86_64-linux-android24:x86_64-linux-android:x86_64"
ABI_MAP["x86"]="i686-linux-android24:i686-linux-android:x86"

if [[ -z "${ABI_MAP[$ABI]:-}" ]]; then
    echo "Error: 未知 ABI '$ABI'"
    echo "支持的 ABI: ${!ABI_MAP[*]}"
    exit 1
fi

IFS=':' read -r CC_TARGET NDK_TRIPLE JNI_ABI <<<"${ABI_MAP[$ABI]}"

# ---- NDK 环境 ----
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/AndroidSDK}"
ANDROID_NDK_HOME="$ANDROID_SDK_ROOT/ndk/29.0.14206865"
TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
SYSROOT="$TOOLCHAIN/sysroot"

export PATH="$TOOLCHAIN/bin:$PATH"

CC="$TOOLCHAIN/bin/${CC_TARGET}-clang"
AR="$TOOLCHAIN/bin/llvm-ar"
STRIP="$TOOLCHAIN/bin/llvm-strip"
OBJCOPY="$TOOLCHAIN/bin/llvm-objcopy"
OBJDUMP="$TOOLCHAIN/bin/llvm-objdump"
LD="$CC"

echo "=== 构建 proot for $ABI ($JNI_ABI) ==="
echo "  CC:      $CC_TARGET"
echo "  Triple:  $NDK_TRIPLE"
echo "  NDK:     $ANDROID_NDK_HOME"

# ---- 版本号 ----
if [[ -z "$VERSION" ]]; then
    VERSION=$(cd "$REPO_DIR/proot" && git rev-parse --short HEAD)
fi
echo "  Version: $VERSION"
echo ""

# 需要 python3 (waf 构建 talloc 用)
command -v python3 >/dev/null 2>&1 || { echo "Error: 缺少 python3 (talloc 的 waf 构建系统需要)"; exit 1; }

# ============================================================
# 清理 & 准备
# ============================================================
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/src" "$BUILD_DIR/out"

# ============================================================
# 1. 交叉编译 talloc
# ============================================================
echo "=== [1/3] 编译 talloc 2.4.3 ==="

TALLOC_VERSION="2.4.3"
TALLOC_TARBALL="talloc-${TALLOC_VERSION}.tar.gz"
TALLOC_URL="https://www.samba.org/ftp/talloc/${TALLOC_TARBALL}"
TALLOC_SHA256="dc46c40b9f46bb34dd97fe41f548b0e8b247b77a918576733c528e83abd854dd"

cd "$BUILD_DIR/src"
if [[ ! -f "$TALLOC_TARBALL" ]]; then
    wget -q "$TALLOC_URL" -O "$TALLOC_TARBALL"
fi
echo "$TALLOC_SHA256  $TALLOC_TARBALL" | sha256sum -c -

tar xzf "$TALLOC_TARBALL"
cd "talloc-${TALLOC_VERSION}"

# 生成 cross-answers.txt (预置交叉编译检查答案)
cat > cross-answers.txt << 'CROSSEOF'
Checking uname sysname type: "Linux"
Checking uname machine type: "dontcare"
Checking uname release type: "dontcare"
Checking uname version type: "dontcare"
Checking simple C program: OK
building library support: OK
Checking for large file support: OK
Checking for -D_FILE_OFFSET_BITS=64: OK
Checking for WORDS_BIGENDIAN: OK
Checking for C99 vsnprintf: OK
Checking for HAVE_SECURE_MKSTEMP: OK
rpath library support: OK
-Wl,--version-script support: FAIL
Checking correct behavior of strtoll: OK
Checking correct behavior of strptime: OK
Checking for HAVE_IFACE_GETIFADDRS: OK
Checking for HAVE_IFACE_IFCONF: OK
Checking for HAVE_IFACE_IFREQ: OK
Checking getconf LFS_CFLAGS: OK
Checking for large file support without additional flags: OK
Checking for working strptime: OK
Checking for HAVE_SHARED_MMAP: OK
Checking for HAVE_MREMAP: OK
Checking for HAVE_INCOHERENT_MMAP: OK
Checking getconf large file support flags work: OK
CROSSEOF

# 配置
CC="$CC" AR="$AR" ./configure \
    --prefix="$BUILD_DIR/out" \
    --disable-rpath \
    --disable-python \
    --cross-compile \
    --cross-answers=cross-answers.txt

# 编译
make -j"$(nproc)" CC="$CC" AR="$AR"

# 安装 (仅 libtalloc.so)
make install CC="$CC" AR="$AR"

# 打包静态库 (按 termux 配方)
cd "$BUILD_DIR/src/talloc-${TALLOC_VERSION}/bin/default"
"$AR" rcu libtalloc.a talloc*.o
install -Dm600 libtalloc.a "$BUILD_DIR/out/lib/libtalloc.a"

echo "  talloc OK"

# ============================================================
# 2. 交叉编译 proot
# ============================================================
echo ""
echo "=== [2/3] 编译 proot ==="

# 源码在 git submodule 中, 为不污染工作树, 用 git archive 复制到构建目录编译
PROOT_BUILD_DIR="$BUILD_DIR/src/proot"
mkdir -p "$PROOT_BUILD_DIR"
cd "$REPO_DIR/proot"
git archive --prefix= HEAD | tar -x -C "$PROOT_BUILD_DIR"

# 应用仓库内的适配补丁 (修复交叉编译/NDK 兼容问题), 不修改 submodule 源码
PATCH_DIR="$SCRIPT_DIR/patches"
if [[ -d "$PATCH_DIR" ]]; then
    for patch in "$PATCH_DIR"/*.patch; do
        [[ -e "$patch" ]] || continue
        echo "  应用补丁: $(basename "$patch")"
        (cd "$PROOT_BUILD_DIR" && patch -p1 --forward < "$patch")
    done
fi

PROOT_MAKE_DIR="$PROOT_BUILD_DIR/src"
if [[ ! -f "$PROOT_MAKE_DIR/GNUmakefile" ]]; then
    echo "Error: proot 源码解包后未找到 src/GNUmakefile, 请检查 git submodule 是否已初始化"
    exit 1
fi
TALLOC_PREFIX="$BUILD_DIR/out"

# 统一编译参数
# 注意1: makefile 中 CFLAGS/LDFLAGS 用 += 追加, 命令行传参会整体覆盖,
#        故这里必须在命令行完整给出所有必需项。
# 注意2: PROOT_UNBUNDLE_LOADER 同时是「make 变量」(控制是否内嵌 loader,
#        ifdef 判断) 和「C 宏」(驱动 get_loader_path 分支), 两者都要传。
CPPFLAGS="-D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -DVERSION=\\\"${VERSION}\\\" -I. -I$PROOT_MAKE_DIR -I$TALLOC_PREFIX/include"
CFLAGS="-Wall -Wextra -O2 -DPROOT_UNBUNDLE_LOADER=\\\"$BUILD_DIR/out/libexec/proot\\\""
LDFLAGS="-ltalloc -L$TALLOC_PREFIX/lib -Wl,-z,noexecstack -Wl,-rpath-link=$TALLOC_PREFIX/lib"
UNBUNDLE_LOADER="$BUILD_DIR/out/libexec/proot"

# 先从 submodule 树中复制 loader 相关工作区文件到构建目录:
# make ifdef PROOT_UNBUNDLE_LOADER 时不再把 loader 包装进二进制。
# 直接构建 proot (unbundle: 独立 loader 产物)
echo "  编译 loader + proot (unbundled loader)..."
make -C "$PROOT_MAKE_DIR" proot \
    CC="$CC" LD="$LD" STRIP="$STRIP" \
    OBJCOPY="$OBJCOPY" OBJDUMP="$OBJDUMP" \
    CPPFLAGS="$CPPFLAGS" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    PROOT_UNBUNDLE_LOADER="$UNBUNDLE_LOADER" \
    V=1

echo "  proot OK"

# ============================================================
# 3. 剥离、重命名、复制到 jniLibs
# ============================================================
echo ""
echo "=== [3/3] 剥离 & 组装 ==="

OUT_ABI_DIR="$OUTPUT_DIR/$JNI_ABI"
mkdir -p "$OUT_ABI_DIR"

# proot
cp "$PROOT_MAKE_DIR/proot" "$BUILD_DIR/proot"
"$STRIP" "$BUILD_DIR/proot"
cp "$BUILD_DIR/proot" "$OUT_ABI_DIR/lib__bin__proot__.so"

# loader
mkdir -p "$BUILD_DIR/out/libexec/proot"
cp "$PROOT_MAKE_DIR/loader/loader" "$BUILD_DIR/out/libexec/proot/loader"
"$STRIP" "$BUILD_DIR/out/libexec/proot/loader"
cp "$BUILD_DIR/out/libexec/proot/loader" "$OUT_ABI_DIR/lib__libexec__loader__.so"

# libtalloc.so
cp "$BUILD_DIR/out/lib/libtalloc.so.2.4.3" "$OUT_ABI_DIR/lib__lib__libtalloc.so.2.4.3__.so"

echo ""
echo "========================================"
echo " 构建完成"
echo "  ABI:      $ABI"
echo "  Version:  $VERSION"
echo "  输出目录: $OUT_ABI_DIR"
echo "========================================"
ls -lh "$OUT_ABI_DIR/"
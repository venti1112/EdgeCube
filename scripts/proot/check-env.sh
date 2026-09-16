#!/bin/bash
set -euo pipefail

echo "=== 检查 proot 构建环境 ==="
echo ""

# 检查 Android NDK
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/AndroidSDK}"
ANDROID_NDK_HOME="$ANDROID_SDK_ROOT/ndk/29.0.14206865"

echo "检查 NDK 位置: $ANDROID_NDK_HOME"
if [[ ! -d "$ANDROID_NDK_HOME" ]]; then
    echo "❌ NDK 不存在, 需要确认 AndroidSDK 位置和版本"
    exit 1
fi
echo "✅ NDK 找到"
echo ""

# 检查工具链
TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
for tool in "aarch64-linux-android24-clang" llvm-ar llvm-strip; do
    path="$TOOLCHAIN/bin/$tool"
    if [[ -x "$path" ]]; then
        echo "✅ $tool found"
    else
        echo "❌ $tool missing"
        exit 1
    fi
done
echo ""

# 检查系统工具
for tool in make wget tar sha256sum git; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "✅ $tool found"
    else
        echo "❌ $tool missing, 需要安装: sudo apt install $tool"
        exit 1
    fi
done
echo ""

# 检查 proot 源码
REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROOT_DIR="$REPO_DIR/proot"
echo "检查 proot 源码: $PROOT_DIR"
if [[ ! -f "$PROOT_DIR/src/GNUmakefile" ]]; then
    echo "❌ proot 源码不存在, 需要 git submodule update --init"
    exit 1
fi
echo "✅ proot 源码找到"
short_hash=$(cd "$PROOT_DIR" && git rev-parse --short HEAD)
echo "   当前 commit: $short_hash"
echo ""

# 输出环境信息
echo "=== 环境信息 ==="
echo "   ANDROID_SDK_ROOT: $ANDROID_SDK_ROOT"
echo "   ANDROID_NDK_HOME: $ANDROID_NDK_HOME"
echo "   构建脚本:        $REPO_DIR/scripts/proot/build.sh"
echo ""
echo "环境检查通过, 可以执行:"
echo "  ./scripts/proot/build.sh arm64-v8a"
echo ""
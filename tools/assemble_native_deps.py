#!/usr/bin/env python3
"""
EdgeCube 原生依赖组装工具

把 Termux 源码构建产物（proot/busybox/tar/zstd 及依赖的 .deb）与
PMMP PHP 交叉编译产物组装成 Android arm64-v8a 的 jniLibs 目录。

命名约定与 ProotBootstrap.kt 严格对应：
    bin/<name>       -> lib__bin__<name>__.so
    lib/<filename>   -> lib__lib__<filename>__.so
    两个 proot loader 保持 Termux 构建时生成的文件名。

用法：
    python3 tools/assemble_native_deps.py \\
        --termux-output third_party/termux-packages/output \\
        --php-bin third_party/php-build-scripts/bin/php7/bin/php \\
        --out dist/native-deps/arm64-v8a

依赖：ar、tar（binutils + GNU tar，CI 与常见 Linux 发行版均自带）。
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# Termux 包内路径前缀（.deb 数据 tar 中的顶层目录）。
TERMUX_PREFIX = Path("data/data/com.termux/files/usr")

# 可执行文件：Termux 包内路径 -> jniLibs 文件名。
BINARIES = {
    "bin/proot": "lib__bin__proot-classic__.so",
    "bin/busybox": "lib__bin__busybox__.so",
    "bin/tar": "lib__bin__tar__.so",
    "bin/zstd": "lib__bin__zstd__.so",
}

# 动态库：Termux 包内路径 -> jniLibs 文件名。
# 版本号来自 third_party/termux-packages 中固定的 recipe；recipe 升级时
# 这里与 ProotBootstrap.kt 需要同步修改（脚本会在此处报错提醒）。
LIBRARIES = {
    "lib/libtalloc.so.2.4.4": "lib__lib__libtalloc.so.2.4.4__.so",
    "lib/libzstd.so.1.5.7": "lib__lib__libzstd.so.1.5.7__.so",
    "lib/libz.so.1.3.2": "lib__lib__libz.so.1.3.2__.so",
    "lib/liblzma.so.5.8.3": "lib__lib__liblzma.so.5.8.3__.so",
    "lib/libacl.so": "lib__lib__libacl.so__.so",
    "lib/libattr.so": "lib__lib__libattr.so__.so",
    "lib/libpcre2-8.so": "lib__lib__libpcre2-8.so__.so",
    "lib/libiconv.so": "lib__lib__libiconv.so__.so",
    "lib/libandroid-selinux.so": "lib__lib__libandroid-selinux.so__.so",
    "lib/libbusybox.so.1.37.0": "lib__lib__libbusybox.so.1.37.0__.so",
}

# proot build.sh 的 post_make_install 直接输出到 Termux output 目录。
LOADERS = (
    "libproot-loader-aarch64-5.1.107-68.so",
    "libproot-loader32-aarch64-5.1.107-68.so",
)

TAR_FLAGS = {
    ".xz": ["-xJf"],
    ".gz": ["-xzf"],
    ".bz2": ["-xjf"],
    ".zst": ["--zstd", "-xf"],
}


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, **kwargs)


def extract_deb(deb: Path, staging: Path) -> None:
    """把 .deb 的 data.tar.* 解压到 staging（多个包共用一个前缀目录）。"""
    members = run(["ar", "t", str(deb)], capture_output=True, text=True).stdout.splitlines()
    data_member = next((m for m in members if m.startswith("data.tar")), None)
    if data_member is None:
        raise SystemExit(f"{deb.name}: 未找到 data.tar.*")

    suffix = Path(data_member).suffix
    flags = TAR_FLAGS.get(suffix)
    if flags is None:
        raise SystemExit(f"{deb.name}: 不支持的压缩格式 {data_member}")

    data = run(["ar", "p", str(deb), data_member], capture_output=True).stdout
    run(["tar", *flags, "-", "-C", str(staging)], input=data)


def resolve_source(staging: Path, rel: str) -> Path:
    """解析包内路径；Termux 包内的相对/绝对 symlink 都要能落到 staging 内。"""
    src = staging / TERMUX_PREFIX / rel
    if src.exists():
        return src.resolve()

    # 绝对符号链接按 /data/data/... 指回 staging 的对应位置。
    if src.is_symlink():
        target = Path(os.readlink(src))
        if target.is_absolute():
            candidate = staging / target.relative_to("/")
            if candidate.exists():
                return candidate.resolve()

    raise SystemExit(f"缺少 Termux 产物：$PREFIX/{rel}")


def copy_asset(src: Path, dest_dir: Path, name: str) -> None:
    dest = dest_dir / name
    if dest.exists():
        raise SystemExit(f"输出文件名重复：{name}")
    shutil.copyfile(src, dest)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--termux-output", required=True, type=Path, help="termux-packages/output 目录")
    parser.add_argument("--php-bin", required=True, type=Path, help="PHP 构建产物的 bin/php7/bin/php")
    parser.add_argument("--out", required=True, type=Path, help="输出目录（扁平 jniLibs）")
    args = parser.parse_args()

    debs = sorted(args.termux_output.glob("*.deb"))
    if not debs:
        raise SystemExit(f"{args.termux_output} 下没有 .deb")
    if not args.php_bin.is_file():
        raise SystemExit(f"缺少 PHP 二进制：{args.php_bin}")

    args.out.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="edgecube-native-deps-") as tmp:
        staging = Path(tmp)
        for deb in debs:
            extract_deb(deb, staging)

        for rel, name in BINARIES.items():
            copy_asset(resolve_source(staging, rel), args.out, name)
        for rel, name in LIBRARIES.items():
            copy_asset(resolve_source(staging, rel), args.out, name)

    for loader in LOADERS:
        src = args.termux_output / loader
        if not src.is_file():
            raise SystemExit(f"缺少 proot loader：{src}")
        copy_asset(src, args.out, loader)

    copy_asset(args.php_bin, args.out, "libphp-cli.so")

    total = sum(p.stat().st_size for p in args.out.iterdir() if p.is_file())
    print(f"已组装 {len(list(args.out.iterdir()))} 个文件，共 {total / 1024 / 1024:.1f} MiB -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

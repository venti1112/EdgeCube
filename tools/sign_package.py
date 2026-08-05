#!/usr/bin/env python3
"""
EdgeCube 运行环境包签名工具

使用 APK 签名密钥（PKCS#12 keystore）对 .ecpkg 或 rootfs 包签名。
签名写入 ZIP 内的 META-INF/edgecube.sig，与 App 内置的
PackageSignatureVerifier 验证逻辑完全对应。

依赖：
    pip install cryptography

用法：
    # 对 .ecpkg 包签名（原地追加签名条目）
    python sign_package.py --key-properties android/key.properties --ecpkg runtime.ecpkg

    # 对 rootfs 包签名（创建含 edgecube-package.json 清单的外层 ZIP，扩展名 .ecpkg）
    python sign_package.py --key-properties android/key.properties --rootfs-tar rootfs.tar.zst

    # 指定输出路径与包清单（合并 type=proot 后写入 edgecube-package.json）
    python sign_package.py --key-properties android/key.properties \\
        --rootfs-tar jdk25.tar.zst --output jdk25.ecpkg \\
        --rootfs-manifest manifest.json

默认输出文件名规则：去掉 tar 复合扩展名后加 .ecpkg。
    jdk25.tar.zst  -> jdk25.ecpkg
    rootfs.tar.xz -> rootfs.ecpkg
    rootfs.tgz     -> rootfs.ecpkg

rootfs .ecpkg 结构（本质是 ZIP，与 RootfsStore.isRootfsPackage 识别逻辑对应）：
    rootfs.tar.zst              # 内层 Linux 根文件系统压缩包
    edgecube-package.json       # 包清单，至少含 {"type":"proot"}
    META-INF/edgecube.sig       # 签名条目（由本工具生成）

签名算法（与 PackageSignatureVerifier.kt 完全一致）：
    1. 遍历 ZIP 中所有非 META-INF/ 前缀、非目录的条目，按条目名排序。
    2. 对每个条目内容计算 SHA-256。
    3. 拼接为 "条目名\nSHA-256十六进制\n" 格式字符串（manifest）。
    4. 对 manifest 的 UTF-8 字节进行 ECDSA over SHA-256 签名。
    5. 将签名 Base64 编码后写入 META-INF/edgecube.sig。
"""

import argparse
import base64
import hashlib
import json
import os
import sys
import tempfile
import zipfile


# rootfs 包清单中的固定 type 值，App 端 isRootfsPackage 据此路由到 rootfs 导入流程。
# 与 RootfsStore.kt 中的 PACKAGE_TYPE_PROOT 常量保持一致。
PACKAGE_TYPE_PROOT = "proot"

# ZIP 根层的包清单文件名；与 RuntimeInstaller.kt / RootfsStore.kt 中的常量一致。
PACKAGE_MANIFEST_FILE = "edgecube-package.json"

# tar 压缩包的复合扩展名（与 RootfsStore.kt 中的 TAR_SUFFIXES 保持一致）。
# 用于推导 rootfs 模式下的默认输出文件名，确保完整去掉 .tar.zst 等双层后缀。
TAR_SUFFIXES = (".tar.zst", ".tar.xz", ".tar.gz", ".tgz", ".tar")


def strip_tar_suffix(path):
    """去掉 tar 压缩包的复合扩展名。

    例：``rootfs.tar.zst`` -> ``rootfs``，``jdk25.tar.xz`` -> ``jdk25``，
    ``rootfs.tgz`` -> ``rootfs``。无已知 tar 后缀时退化为去掉最后一个扩展名，
    避免把 ``jdk25.tar.zst`` 错切成 ``jdk25.tar``（再加 .ecpkg 变成
    ``jdk25.tar.ecpkg``，正是要避免的情况）。
    """
    lower = path.lower()
    for suffix in TAR_SUFFIXES:
        if lower.endswith(suffix):
            return path[: -len(suffix)]
    return os.path.splitext(path)[0]


def load_private_key(key_properties_path):
    """从 key.properties 读取 PKCS#12 keystore 中的私钥。"""
    props = {}
    with open(key_properties_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                k, v = line.split("=", 1)
                props[k.strip()] = v.strip()

    store_file = props.get("storeFile")
    store_pass = props.get("storePassword", "")
    key_alias = props.get("keyAlias")
    key_pass = props.get("keyPassword", store_pass)

    if not store_file:
        raise ValueError("key.properties 中缺少 storeFile")
    if not key_alias:
        raise ValueError("key.properties 中缺少 keyAlias")

    store_file = os.path.expanduser(store_file)
    if not os.path.isabs(store_file):
        base_dir = os.path.dirname(os.path.abspath(key_properties_path))
        store_file = os.path.join(base_dir, store_file)

    from cryptography.hazmat.primitives.serialization import pkcs12

    with open(store_file, "rb") as f:
        p12_data = f.read()

    private_key, cert, _ = pkcs12.load_key_and_certificates(
        p12_data,
        key_pass.encode() if key_pass else None,
    )
    if private_key is None:
        raise ValueError(f"无法从 keystore 读取私钥（别名可能不匹配）")

    print(f"已从 {key_properties_path} 读取签名配置：")
    print(f"  keystore = {store_file}")
    print(f"  alias    = {key_alias}")
    print(f"  key type = {type(private_key).__name__}")
    return private_key


def compute_manifest(zip_path):
    """计算 ZIP 中所有非 META-INF/ 条目的签名清单字符串。

    与 PackageSignatureVerifier.kt 中的 computeManifest 完全一致。
    返回 manifest 的 UTF-8 字节，签名库会对它计算 SHA-256 后签名。
    """
    hashes = []
    with zipfile.ZipFile(zip_path, "r") as zf:
        names = sorted(
            entry.filename
            for entry in zf.infolist()
            if not entry.filename.endswith("/") and not entry.filename.startswith("META-INF/")
        )
        for name in names:
            content = zf.read(name)
            sha = hashlib.sha256(content).hexdigest()
            hashes.append(f"{name}\n{sha}\n")

    manifest = "".join(hashes)
    return manifest.encode("utf-8")


def sign_manifest(private_key, manifest_bytes):
    """用 EC 私钥对 manifest 签名（SHA256withECDSA）。"""
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.hashes import SHA256

    return private_key.sign(manifest_bytes, ec.ECDSA(SHA256()))


def add_signature_to_zip(zip_path, private_key):
    """在 ZIP 中追加 META-INF/edgecube.sig 签名条目（原地替换）。"""
    manifest_bytes = compute_manifest(zip_path)
    signature = sign_manifest(private_key, manifest_bytes)
    sig_b64 = base64.b64encode(signature).decode("ascii")

    tmp_fd, tmp_path = tempfile.mkstemp(
        dir=os.path.dirname(os.path.abspath(zip_path)),
        suffix=".tmp",
    )
    os.close(tmp_fd)

    with zipfile.ZipFile(zip_path, "r") as src:
        with zipfile.ZipFile(tmp_path, "w", zipfile.ZIP_DEFLATED) as dst:
            for item in src.infolist():
                if item.filename == "META-INF/edgecube.sig":
                    continue
                dst.writestr(item, src.read(item.filename))
            dst.writestr("META-INF/edgecube.sig", sig_b64)

    os.replace(tmp_path, zip_path)


def build_rootfs_manifest(extra_manifest_path=None):
    """构造 rootfs ZIP 层的 edgecube-package.json 内容。

    固定写入 `type=proot`（App 端 isRootfsPackage 据此识别为 rootfs 包）。
    若传入 [extra_manifest_path]，则加载该 JSON 文件并合并字段，允许自定义
    envType、envName 等额外元数据；但 `type` 始终被强制为 "proot"，
    避免误传导致 App 端路由错误。

    返回写入 ZIP 的 JSON 字符串（UTF-8 编码无 BOM）。
    """
    manifest = {}
    if extra_manifest_path:
        with open(extra_manifest_path, "r", encoding="utf-8") as f:
            manifest = json.load(f)
        if not isinstance(manifest, dict):
            raise ValueError(
                f"{extra_manifest_path} 顶层不是 JSON 对象：{type(manifest).__name__}"
            )
    manifest["type"] = PACKAGE_TYPE_PROOT
    return json.dumps(manifest, ensure_ascii=False, indent=2)


def create_rootfs_zip(tar_path, output_path, private_key, extra_manifest_path=None):
    """创建 rootfs 外层 ZIP。

    结构：
        rootfs.tar.zst            # 内层 tar 压缩包
        edgecube-package.json     # 包清单（type=proot，可由 --rootfs-manifest 合并额外字段）
        META-INF/edgecube.sig     # 签名（由 add_signature_to_zip 追加）

    注意：edgecube-package.json 必须在签名前写入，签名清单会把它一并计入。
    """
    manifest_json = build_rootfs_manifest(extra_manifest_path)
    with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(tar_path, "rootfs.tar.zst")
        zf.writestr(PACKAGE_MANIFEST_FILE, manifest_json)
    add_signature_to_zip(output_path, private_key)


def main():
    parser = argparse.ArgumentParser(
        description="EdgeCube 运行环境包签名工具",
    )
    parser.add_argument(
        "--key-properties",
        required=True,
        help="Android key.properties 文件路径",
    )
    parser.add_argument(
        "--ecpkg",
        default=None,
        help="对已有的 .ecpkg 包签名（原地追加签名条目）",
    )
    parser.add_argument(
        "--rootfs-tar",
        default=None,
        help="rootfs tar 压缩包路径（如 rootfs.tar.zst），将创建外层 .ecpkg 包",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="rootfs 模式下的输出 .ecpkg 路径（默认与输入同目录的 .ecpkg）",
    )
    parser.add_argument(
        "--rootfs-manifest",
        default=None,
        help=(
            "rootfs 模式下可选的包清单 JSON 文件路径。字段会合并到 "
            "edgecube-package.json，但 type 始终强制为 proot。"
            "可用于声明 envType、envName、envMainBin 等元数据。"
        ),
    )

    args = parser.parse_args()

    private_key = load_private_key(args.key_properties)

    if args.ecpkg:
        print(f"正在签名 {args.ecpkg}...")
        add_signature_to_zip(args.ecpkg, private_key)
        print(f"✓ 签名完成：{args.ecpkg}")

    elif args.rootfs_tar:
        output = args.output
        if output is None:
            # 完整去掉 .tar.zst / .tar.xz / .tgz 等复合扩展名后再加 .ecpkg，
            # 避免出现 jdk25.tar.ecpkg 这种残留下层 .tar 的文件名。
            output = strip_tar_suffix(args.rootfs_tar) + ".ecpkg"
        manifest_desc = ""
        if args.rootfs_manifest:
            manifest_desc = f"，清单 {args.rootfs_manifest}"
        print(f"正在创建 {output}（含 {args.rootfs_tar}{manifest_desc}）...")
        create_rootfs_zip(
            args.rootfs_tar,
            output,
            private_key,
            extra_manifest_path=args.rootfs_manifest,
        )
        print(f"✓ 签名完成：{output}")

    else:
        print("错误：必须指定 --ecpkg 或 --rootfs-tar", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
EdgeCube 运行环境包签名工具

使用 APK 签名密钥（PKCS#12 keystore）对 .ecpkg 或 rootfs.zip 包签名。
签名写入 ZIP 内的 META-INF/edgecube.sig，与 App 内置的
PackageSignatureVerifier 验证逻辑完全对应。

依赖：
    pip install cryptography

用法：
    # 对 .ecpkg 包签名（原地追加签名条目）
    python sign_package.py --key-properties android/key.properties --ecpkg runtime.ecpkg

    # 对 rootfs 包签名（先创建外层 ZIP，再追加签名）
    python sign_package.py --key-properties android/key.properties --rootfs-tar rootfs.tar.zst --output rootfs.zip

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
import os
import sys
import tempfile
import zipfile


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


def create_rootfs_zip(tar_path, output_path, private_key):
    """创建 rootfs 外层 ZIP（含 rootfs.tar.zst 条目 + 签名）。"""
    with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(tar_path, "rootfs.tar.zst")
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
        help="rootfs tar 压缩包路径（如 rootfs.tar.zst），将创建外层 ZIP",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="rootfs 模式下的输出 ZIP 路径（默认与输入同目录的 .zip）",
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
            base = os.path.splitext(args.rootfs_tar)[0]
            output = base + ".zip"
        print(f"正在创建 {output}（含 {args.rootfs_tar}）...")
        create_rootfs_zip(args.rootfs_tar, output, private_key)
        print(f"✓ 签名完成：{output}")

    else:
        print("错误：必须指定 --ecpkg 或 --rootfs-tar", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

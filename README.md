<div align="center">

<img src="assets/images/app_logo.png" width="120" alt="EdgeCube logo" />

# EdgeCube

**在 Android 手机上运行 Minecraft 服务器。**

[English](README-EN.md) · [简体中文](README.md)

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-Dart%20%3E%3D%203.12.2-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Rust](https://img.shields.io/badge/Rust-2024%20Edition-dea582?logo=rust&logoColor=black)](https://www.rust-lang.org)
[![Platform](https://img.shields.io/badge/Platform-Android%207.0%2B-3DDC84?logo=android&logoColor=white)](https://www.android.com)
[![Version](https://img.shields.io/badge/version-1.0.6-orange.svg)](https://github.com/venti1112/EdgeCube)

[官网](https://edgecubemc.com) · [文档](https://edgecubemc.com/#docs) · [Issue](https://github.com/venti1112/EdgeCube/issues)

</div>

---

## 简介

EdgeCube 是一款开源 Android 应用，用于在手机上创建、配置、启动并运维 Minecraft 服务器。

应用内置完整的运行时管理（JRE 17/21/25、PHP、rootfs）、终端、文件管理器、模组/插件浏览器，以及一组网络服务，让你的设备随时可以被外部访问。

## 功能特性

**服务端与运行时**

- 一键创建向导：选择服务端类型 → 版本 → 加载器 → 下载
- 支持 Vanilla、Paper、Purpur、Spigot、CraftBukkit、Forge、NeoForge、Fabric、Leaf、Leaves、Velocity、BungeeCord、PowerNukkitX、PocketMine-MP、Allay。
- 双运行模式，可随时切换：
  - **原生模式**：直接调用内置 JRE（17/21/25）或随包的 PHP CLI。
  - **proot 容器模式**：在导入的 Linux rootfs 内运行，兼容性最好。
- 运行环境包（`.ecpkg`）支持在线下载、导入、更新与签名校验；`.ecpkg` 已做文件关联，可从文件管理器直接打开导入。
- 首次启动自动确认 Minecraft EULA；崩溃分析：服务端或隧道异常退出时，日志会与内置规则库（`assets/rules/server_errors.json`）匹配，给出原因与修复建议。

**公网访问**

- UPnP 端口映射、DDNS、STUN NAT1 打洞。
- FRP 隧道，支持多供应商：CHMLFRP、MeFrp、MSL FRP、OpenFRP、SakuraFRP。

**内容资源**

- 在线浏览与下载模组 / 插件 / 整合包：Modrinth、CurseForge、Spiget、Hangar、Poggit。
- 整合包导入：CurseForge、Modrinth、MultiMC、MCBBS/HMCL。

**运维**

- 增量备份 + 定时备份，目标支持本地、FTP、SFTP、WebDAV。
- 保活：前台服务、电池优化白名单、WakeLock/WifiLock、状态悬浮窗、防息屏、桌面小组件（启动/停止、状态、CPU/内存、在线人数）。
- 服务端属性编辑、世界存档配置、玩家管理、系统监控。

**体验**

- UI 基于 [flutter_miuix](https://pub.dev/packages/flutter_miuix)（HyperOS 风格）。
- 多语言：简体中文（源语言）/ English。
- 主题：暗色、种子色、动态取色（Monet）。

## 技术架构

```
┌──────────────────────────────────────────────────────────┐
│ Flutter UI（lib/）                                        │
│   Scope 树 → 5 个 Tab：服务器 · 控制台 · 管理 ·            │
│   文件 · 设置                                              │
├──────────────────────────────────────────────────────────┤
│ Dart 服务层 —— 21 条 Method/EventChannel                   │
│   server · shell · ftp · ssh · proot · runtime ·         │
│   archive · ecpkg · forge · tunnel · monitor · …         │
├──────────────────────────────────────────────────────────┤
│ Android 原生层（Kotlin + C，minSdk 24）                    │
│   ServerLauncher · RuntimeInstaller · ProotBootstrap ·   │
│   KeepAliveManager · WidgetUpdater · 签名校验             │
├──────────────────────────────────────────────────────────┤
│ Rust JNI（cargo-ndk → libedgecube_pty.so / _tools.so）   │
│   edgecube-pty   ：PTY spawn / 分帧 / 广播                │
│   edgecube-tools ：归档 + FTP（unftp）+ SSH（russh）      │
└──────────────────────────────────────────────────────────┘
```

## 环境要求

- Flutter SDK（Dart `>=3.12.2 <4.0.0`）
- Android SDK，含 **NDK 30.0.16248370**、CMake 4.1.2、build-tools 37.0.0
- Rust 工具链 + [`cargo-ndk`](https://github.com/bbqsrc/cargo-ndk)
- **Android 7.0+** 的真机或模拟器（`arm64-v8a`、`armeabi-v7a`、`x86_64`）

## 快速开始

```bash
git clone https://github.com/venti1112/EdgeCube.git
cd EdgeCube
git submodule update --init --recursive   # 仅在修改原生依赖时需要
flutter pub get
flutter run
```

### 打包发布

```bash
# Rust 由 Gradle 的 cargoBuild 任务自动编译；proot/PHP 原生依赖由
# fetchNativeDeps 任务从 Release 下载并校验（见下节），均已挂接到 preBuild：
flutter build apk --release

# CurseForge 为可选项，不注入 key 时该平台会在 UI 中隐藏
flutter build apk --release --dart-define=CURSEFORGE_API_KEY=<your-key>
```

> Release 签名读取 `android/key.properties`（`storeFile`、`storePassword`、`keyAlias`、`keyPassword`）；debug 构建同样使用该签名。

### 原生依赖（proot 工具链 / PHP CLI）

仓库不保存构建好的二进制，以下组件均由 GitHub Actions 从源码构建：

| 组件 | 构建源码 | 方式 |
| --- | --- | --- |
| proot / busybox / tar / zstd 及依赖 | `third_party/termux-packages` | Termux package-builder 镜像（由子模块 Dockerfile 构建） |
| PHP CLI 8.2（musl 静态链接） | `third_party/php-build-scripts` + `third_party/musl-cross-make` | `compile.sh` 交叉编译 |

「构建原生依赖」工作流把产物组装为 `edgecube-native-deps-arm64-v8a.zip` 并发布到 `native-deps-v1` Release；`android/native-deps.properties` 锁定资产名与 sha256，Gradle 的 `fetchNativeDeps` 任务在 `preBuild` 前下载、校验并解压到 `build/native-deps/jniLibs/`。

升级组件时：更新子模块指针 → 运行「构建原生依赖」（可同时提升 Release tag）→ 把新 sha256 填入 `android/native-deps.properties`。

APK 构建工作流从 Actions Secrets 读取签名材料：`ANDROID_KEYSTORE_B64`（base64 编码的 `.jks`）与 `ANDROID_KEY_PROPERTIES`（完整 `key.properties` 内容，`storeFile` 由 CI 覆盖为临时路径）。

### 测试与静态检查

```bash
flutter analyze          # flutter_lints
flutter test             # i18n 键一致性、PTY 分帧、模组元数据、世界服务、对话框
cd rust && cargo test    # edgecube-pty + edgecube-tools（archive / ftp / ssh）
```

## 配置说明

运行时配置以 JSON 形式存放在 `<应用文档目录>/config/`（`lib/config/`），每个功能一个文件——`network.json`、`ssh.json`、`ftp.json`、`mcp.json`、`backup.json`、`ddns.json`、`stun.json`、`instances.json`、`locale.json` …

服务端工作目录默认位于 `<共享存储>/EdgeCube/instances/<id>/`，可在设置中整体迁移。

| 服务 | 默认端口 | 配置文件 |
| --- | --- | --- |
| FTP | 2121 | `config/ftp.json` |
| SSH / SFTP | 2222 | `config/ssh.json` |
| MCP | 8765 | `config/mcp.json` |

### `.ecpkg` 包签名

运行环境 / rootfs 包使用 APK 发布密钥做 ECDSA-P256 + SHA-256 签名，应用内导入前会校验：

```bash
pip install cryptography
python tools/sign_package.py --key-properties android/key.properties --ecpkg runtime.ecpkg
python tools/sign_package.py --key-properties android/key.properties --rootfs-tar rootfs.tar.zst
```

## 目录结构

```
EdgeCube/
├── lib/                  # Dart 源码
│   ├── main.dart         # 启动引导 + Scope 树
│   ├── home_shell.dart   # 底部 Tab
│   ├── instance/         # 创建向导、下载、导入
│   ├── server/           # 启停、proot、属性、DDNS/UPnP、监控、崩溃分析
│   ├── files/  mods/     # 文件管理、模组/插件/整合包源
│   ├── ftp/ ssh/ shell/ mcp/ frp/ stun/ tunnel/ backup/
│   ├── config/           # JSON 配置 Store
│   ├── i18n/  theme/  logging/  pages/  widgets/
├── android/              # Kotlin + C（CMake）；原生依赖在构建时拉取
├── rust/                 # workspace：edgecube-pty、edgecube-tools
├── third_party/          # 原生依赖构建源码（Git 子模块）
├── assets/               # 图片、i18n JSON、markdown、崩溃规则
├── test/                 # Flutter 测试
└── tools/                # sign_package.py、assemble_native_deps.py
```

## 参与贡献

欢迎在 [github.com/venti1112/EdgeCube](https://github.com/venti1112/EdgeCube) 提 Issue 与 Pull Request。

- 问题反馈 → [Issues](https://github.com/venti1112/EdgeCube/issues)
- 使用文档 → [edgecubemc.com/#docs](https://edgecubemc.com/#docs)

代码注释与 commit 信息请使用中文，与现有代码库保持一致。

## 开源协议

[AGPL-3.0](LICENSE) © venti1112

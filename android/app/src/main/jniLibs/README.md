# 自带 shell 二进制（BusyBox / Bash）放置说明

EdgeCube 的「Shell 终端」与 MCP `run_shell` 工具默认使用系统自带的 `/system/bin/sh`
（toybox，开箱即用 `ls`/`cd`/`cat` 等）。若想要更完整的环境，可自行编译 BusyBox 或 Bash
并放在这里，应用会在启动 shell 时**自动优先使用**它们。

## 放置位置与命名

现代 Android 出于 W^X 安全策略，只允许从 `nativeLibraryDir` 执行二进制，应用私有目录
（`filesDir`）不可执行。本项目已开启 `useLegacyPackaging = true`，因此放进 `jniLibs/<abi>/`
且以 `lib*.so` 命名的文件会在安装时解压到可执行的 `nativeLibraryDir`。

按设备 ABI 放置（`arm64-v8a` 必备，其余可选）：

```
android/app/src/main/jniLibs/
  arm64-v8a/
    libbusybox.so   # 你编译的 busybox（静态 PIE）
    libbash.so      # 你编译的 bash（静态 PIE，可选）
  armeabi-v7a/
    libbusybox.so
  x86_64/
    libbusybox.so
```

优先级：`libbash.so` > `libbusybox.so` > 系统 `/system/bin/sh`。

## 编译要求

- 必须是 **静态链接 + PIE**（位置无关可执行文件）：
  `arm64-v8a` 用 NDK 的 `aarch64-linux-android<API>-clang`，
  链接参数含 `-static -fPIE -pie`（或 BusyBox 的 `CONFIG_STATIC=y` + `CONFIG_PIE=y`）。
- **BusyBox 建议开启**：
  - `CONFIG_FEATURE_SH_STANDALONE=y`
  - `CONFIG_FEATURE_PREFER_APPLETS=y`
  这样 `busybox sh` 内部直接派发 `ls`、`cat` 等 applet，无需在 PATH 里建符号链接
  （`filesDir` 不可执行，无法用 `busybox --install` 建可执行软链）。
- **Bash 自身不含 `ls` 等工具**：若只放 `libbash.so`，`ls` 等仍由 PATH 中的
  `/system/bin`（toybox）或同时放置的 `libbusybox.so` 提供。

放好后重新编译安装 APK 即可；在「管理 → Shell 终端」标题栏会显示当前生效的 shell 名称。

#!/usr/bin/env bash
# EdgeCube PTY 构建脚本
#
# 用法:
#   ./scripts/build.sh                    # 本机平台
#   ./scripts/build.sh linux/amd64 linux/arm64 windows/amd64
#
# 目标说明:
#   - linux/amd64, linux/arm64:桌面 Linux / Android(静态,CGO_ENABLED=0,
#     Android 上由 Kotlin daemon 直接 spawn,无需 proot)
#   - windows/amd64:winpty dll 已内嵌(embed),运行时解压到临时目录
# 产物输出到 pty/dist/{goos}-{goarch}/pty[.exe]
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p dist

targets=("$@")
if [[ ${#targets[@]} -eq 0 ]]; then
  targets=("$(go env GOOS)/$(go env GOARCH)")
fi

for t in "${targets[@]}"; do
  goos="${t%%/*}"
  goarch="${t##*/}"
  out="dist/${goos}-${goarch}/pty"
  [[ "$goos" == "windows" ]] && out="${out}.exe"
  echo "[build] ${t} -> ${out}"
  CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" go build \
    -trimpath -ldflags "-s -w" -o "$out" .
done

echo "[build] 完成"
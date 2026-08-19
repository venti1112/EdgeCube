#!/usr/bin/env bash
# proto 生成物同步校验
#
# 将 openapi.yaml 重新生成到临时目录,与仓库内提交的生成物逐文件 diff。
# 任何差异都说明 openapi.yaml 与生成物不同步(契约被绕过),CI 中应失败。
#
# 用法:
#   ./check.sh                 # 校验全部语言
#   ./check.sh dart            # 仅校验 Dart
#   ./check.sh rust
#   ./check.sh kotlin
set -euo pipefail

cd "$(dirname "$0")"

SPEC="openapi.yaml"
CLI_VERSION="2.40.1"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 与 gen.sh 保持一致:generator|library|props
declare -A GEN_CONF=(
  [dart]="dart-dio||pubName=edgecube_api_client,useEnumExtension=true,allowUnicodeIdentifiers=true"
  [rust]="rust||packageName=edgecube_api"
  [kotlin]="kotlin|jvm-ktor|packageName=com.venti1112.edgecube.api"
)

target="${1:-all}"
langs=()
if [[ "$target" == "all" ]]; then
  langs=(dart rust kotlin)
else
  langs=("$target")
fi

fail=0
for lang in "${langs[@]}"; do
  conf="${GEN_CONF[$lang]}"
  generator="${conf%%|*}"
  rest="${conf#*|}"
  library="${rest%%|*}"
  props="${rest#*|}"

  dest="gen/$lang"
  [[ -d "$dest" ]] || { echo "[check] 缺少生成物目录 $dest,请先运行 ./gen.sh"; fail=1; continue; }

  echo "[check] 重新生成 $lang ..."
  local_extra=()
  [[ -n "$library" ]] && local_extra=(--library="$library")
  npx --yes "@openapitools/openapi-generator-cli@${CLI_VERSION}" generate \
    -i "$SPEC" -g "$generator" -o "$TMP/$lang" \
    --additional-properties="$props" \
    "${local_extra[@]}" \
    --skip-validate-spec >/dev/null

  if [[ "$lang" == "dart" ]]; then
    echo "[check] dart: 运行 build_runner ..."
    (cd "$TMP/$lang" && dart run build_runner build --delete-conflicting-outputs >/dev/null)
  fi

  echo "[check] diff $lang ..."
  if diff -r -x .dart_tool -x pubspec.lock -x .gitignore -x build -x .gradle "$dest" "$TMP/$lang" >/dev/null 2>&1; then
    echo "[check] $lang: 同步 ✓"
  else
    echo "[check] $lang: 不同步 ✗ (openapi.yaml 修改后未运行 ./gen.sh)"
    diff -r -x .dart_tool -x pubspec.lock -x .gitignore -x build -x .gradle "$dest" "$TMP/$lang" | head -30
    fail=1
  fi
done

[[ $fail -eq 0 ]] || exit 1
echo "[check] 全部通过 ✓"
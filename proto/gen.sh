#!/usr/bin/env bash
# EdgeCube proto 代码生成器
#
# 契约优先:所有 API 变更先改 proto/openapi.yaml,再运行本脚本重新生成
# 双端代码。生成物提交仓库(见 proto/README.md)。
#
# 用法:
#   ./gen.sh                 # 生成全部语言
#   ./gen.sh dart            # 仅 Dart (Flutter UI 客户端, dio)
#   ./gen.sh rust            # 仅 Rust (daemon 参考)
#   DEST=proto/gen/dart ./gen.sh dart   # 覆盖输出目录
#
# 依赖:Java 17+、npm/npx(openapi-generator-cli 经 npx 按需拉取)
set -euo pipefail

cd "$(dirname "$0")"

SPEC="openapi.yaml"
CLI_VERSION="2.40.1"            # openapi-generator-cli 版本(可复现)
DART_GENERATOR="dart-dio"
RUST_GENERATOR="rust"

DART_PROPS="pubName=edgecube_api_client,useEnumExtension=true,allowUnicodeIdentifiers=true"
RUST_PROPS="packageName=edgecube_api"

log() { printf '\033[1;36m[gen]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[gen]\033[0m %s\n' "$*" >&2; exit 1; }

[[ -f "$SPEC" ]] || err "找不到 $SPEC,请在 proto/ 目录下运行"

# openapi-generator 需要 Java
command -v java >/dev/null 2>&1 || err "需要 Java 17+ (openapi-generator 运行环境)"

gen_dart() {
  local dest="${DEST:-gen/dart}"
  rm -rf "$dest"   # 干净生成:增量生成会导致 .openapi-generator/FILES 与文件系统不一致
  log "生成 Dart 客户端 (dart-dio) -> $dest"
  npx --yes "@openapitools/openapi-generator-cli@${CLI_VERSION}" generate \
    -i "$SPEC" -g "$DART_GENERATOR" -o "$dest" \
    --additional-properties="$DART_PROPS" \
    --skip-validate-spec
  # dart-dio 生成物依赖 built_value 序列化,需跑 build_runner 生成 *.g.dart
  command -v dart >/dev/null 2>&1 || err "生成 Dart 需要 dart (build_runner)"
  log "运行 build_runner (生成 .g.dart 序列化代码)..."
  (cd "$dest" && dart run build_runner build --delete-conflicting-outputs >/dev/null)
  log "Dart 生成完成: $dest"
}

gen_rust() {
  local dest="${DEST:-gen/rust}"
  rm -rf "$dest"   # 干净生成:增量生成会导致 .openapi-generator/FILES 与文件系统不一致
  log "生成 Rust 客户端参考 (rust) -> $dest"
  npx --yes "@openapitools/openapi-generator-cli@${CLI_VERSION}" generate \
    -i "$SPEC" -g "$RUST_GENERATOR" -o "$dest" \
    --additional-properties="$RUST_PROPS" \
    --skip-validate-spec
  log "Rust 生成完成: $dest"
}

case "${1:-all}" in
  dart)   gen_dart ;;
  rust)   gen_rust ;;
  all)    gen_dart; gen_rust ;;
  *)      err "未知目标: $1 (可选: dart / rust / all)" ;;
esac

log "完成。生成物已在 gen 目录下，修改 openapi.yaml 后请运行 ./gen.sh 重新生成,并运行 ./check.sh 校验。"
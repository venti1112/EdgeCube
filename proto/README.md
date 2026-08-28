# proto/ — 协议规范(唯一契约)

本目录是 EdgeCube v2 前后端分离的**唯一协议契约**,Rust daemon / Flutter UI
两端都必须以本目录文件为准,任何一端不得绕过契约私自改协议。

## 文件

| 文件 | 内容 |
|---|---|
| `openapi.yaml` | REST API 规范(OpenAPI 3.0.3),含全部数据模型 |
| `ws.md` | WebSocket 协议(events 订阅 + terminal 会话),参考 MCSManager 设计 |
| `README.md` | 本文档 |

## 契约优先流程

```
1. 需求变更 → 先改 openapi.yaml / ws.md(含 x-phase 阶段标记)
2. 更新 conformance 测试用例(daemon 同套用例)
3. 生成客户端/服务端代码 → Rust daemon / Flutter client 各自实现
4. daemon 通过 conformance 后才允许 UI 侧联调
```

## 代码生成

使用 [openapi-generator](https://openapi-generator.tech) CLI(v2.40.1,经 npx 按需拉取,无需本地安装;
运行依赖 Java 17+)。

```bash
# 生成全部两端代码(推荐)
./proto/gen.sh

# 单独生成某端;DEST 可覆盖输出目录
./proto/gen.sh dart       # Flutter UI 客户端(dart-dio)
./proto/gen.sh rust       # Rust daemon 参考

# 校验生成物与 openapi.yaml 同步(CI 阶段接入)
./proto/check.sh
```

生成物输出:

| 端 | 生成器 | 输出目录 |
|---|---|---|
| Dart (Flutter) | dart-dio | `proto/gen/dart`(app 建立后拷贝至 `app/lib/api/generated` 或改 `DEST`) |
| Rust | rust | `proto/gen/rust` |

- **生成物提交仓库**,避免构建时依赖生成器与网络;`proto/gen/dart` 的
  `.dart_tool/`、`pubspec.lock` 为构建产物,已 .gitignore。
- 修改 openapi.yaml 后必须重新生成(`./gen.sh`)并通过 `./check.sh`,否则 CI 失败。
- 注意:增量生成到已存在的输出目录可能产生 FILES 与文件系统不一致(删旧重建即可,
  脚本已保证从干净目录生成)。
- WS 部分(ws.md)无生成器,由双端手写实现,conformance 测试兜底。

## 约定

- API 路径前缀:`/api/v1/*`;WS:`/api/v1/ws/events`、`/api/v1/ws/terminal`
- 默认端口 8760,daemon 配置可改
- 鉴权:6 位对码 → `POST /auth/pair` 换长期 token,后续 `Authorization: Bearer`
- 阶段标记:每个 path 带 `x-phase`(0/1/2/3),对应 docs/PLAN.md §10 分阶段路线;
  实现时按阶段推进,未到阶段的端点返回 `501 Not Implemented`(占位)
- 分页统一 `Page` 语义:page 从 1 开始,pageSize 上限 100
- 错误统一 `ErrorResponse { code, message, details? }`,UI 按 code 本地化文案
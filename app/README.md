# EdgeCube-APP

EdgeCube 的前端 APP（Flutter，Android / Windows / Linux / Web）。

与后端 `daemon` 之间只靠一条 WebSocket 长连接通信：既做类 HTTP 的一问一答，
也接收服务端主动推送。协议细节见 [`../daemon/README.md`](../daemon/README.md)。

---

## 启动后的连接流程

```
启动
 │
 ├─ 读存储里的「上次连成功的服务器」     shared_preferences: connection
 │
 ├─ 没有 ──► /connect 连接页：填 IP / 端口 / Token → 连接
 │             ├─ 成功：配置落盘 → 守卫放行 → 自动进入主界面
 │             └─ 失败：停在连接页，就地显示原因（令牌错 / 连不上 / 超时）
 │
 └─ 有 ────► 直接进主界面，并在首帧后自动重连
              ├─ 连不上：不踢回连接页，顶部横幅提示 +「重试」
              └─ 掉线：横幅提示 + 退避重连（1s→2s→4s→8s→15s，最多 5 次）
```

几个刻意的取舍：

- **连接页只在「从未成功连接过」时出现**。配过一次之后，daemon 重启、网络抖动
  都只用横幅提示 —— 每次都被踢回连接页没法用。
- **只有连成功才落盘**。半途输入的地址、连不上的地址都不该被记住。
- **令牌走查询串**（`ws://host:port/ws?token=…`）。浏览器 WebSocket API 不能自定义
  请求头，查询串是唯一跨平台的方式，也是 daemon 支持的三种带法之一。
- 「忘记这台服务器」（设置 → 连接）会清空存储，守卫随即把人送回连接页。

### 订阅的两层语义（别混）

订阅是**连接级**的：连接一断，服务端那侧的订阅随之消失。客户端因此分两层记：

| | 读法 | 掉线（自动重连中） | 断开 / 忘记 / 换服务器 | 重试次数用尽 |
| --- | --- | --- | --- | --- |
| **生效订阅** | `ref.watch(subscriptionsProvider)` | 清空 | 清空 | 清空 |
| **期望订阅** | `ref.read(connectionProvider.notifier).desiredTopics` | 保留 → 重连后自动补订 | 清空 | 清空 |

- 页面只管调 `ref.read(connectionProvider.notifier).subscribe('topic')`：
  没连上就先登记意图，连上/重连后自动补订，不用自己处理断开与重连。
- 「服务器」页就是这么用的：它订阅 `core.conn_opened` / `core.conn_closed`，
  事件一到就刷新 `core.info`，所以「当前连接数」是活的；卡片上还会列出
  当前订阅并提供「取消全部订阅」。
- 「取消全部订阅」是字面意思，连页面自己声明的那两条也会取消；
  重新连接（或重试）后会重新登记。

## 目录结构

```
lib/
├── main.dart                 入口：预加载存储 → ProviderScope(overrides) → EdgeCubeApp
├── app.dart                  主题 + 路由；首帧后触发「有配置就自动连」
├── router.dart               路由表 + 首次配置守卫（redirect）
├── storage.dart              全局 SharedPreferences Provider
├── connection/
│   ├── settings.dart         ConnectionSettings（地址/端口/令牌）+ 单项 Provider + 落盘
│   ├── transport.dart        DaemonTransport 抽象 + WebSocket 实现（可注入假实现）
│   ├── client.dart           DaemonClient：信封收发、id 配对、订阅、事件流
│   └── state.dart            连接状态机（阶段 / 重连 / 超时）+ 派生 Provider
├── pages/
│   ├── connect_page.dart     连接页（IP / 端口 / Token）
│   └── servers_page.dart     主界面「服务器」页：连接概览 + core.info
├── shell/
│   ├── home_shell.dart       底栏 / 侧栏 + 内容区（含毛玻璃）
│   └── connection_banner.dart 未连接时的顶部横幅
└── settings/
    ├── main.dart             设置入口
    ├── connection_page.dart  连接设置：改地址重连 / 断开 / 忘记服务器
    ├── appearance.dart       外观设置（主题、背景、毛玻璃）
    ├── appearance_page.dart
    └── base.dart             「单项设置全局 Provider」的公共骨架
```

## 代码约定

- **UI 用 `package:material_ui/material_ui.dart`**，不直接 import `package:flutter/material.dart`
  （例外：需要包一层 flutter/material 主题时，如 `flex_color_picker`）。
- **每个设置项一个全局 Provider**：聚合状态是唯一真源（负责 clamp 与落盘），
  单项 Provider 只是门面。骨架在 `settings/base.dart`：
  `ref.watch(daemonHostProvider)` / `ref.read(daemonHostProvider.notifier).set(…)`。
- **一个存储 key 存整份 JSON**，不要一项一个 key（多 key 读-改-写会互相覆盖）。
- 连接配置的 setter **不落盘**，落盘只发生在连接成功那一刻。
- 不在 build 里改状态；页面的输入框在提交时一次性写回 Provider。

## 协议客户端怎么用

```dart
final client = ref.read(daemonClientProvider);   // 未连接时为 null
if (client != null) {
  final info = await client.callObject('core.info');
  await client.subscribe('ticker.*');
  client.events.listen((event) => print(event['topic']));
}
```

- `call` / `callObject` 出错时抛 `DaemonException(code, message)`，
  **按 `code` 分支**（`method_not_found` / `invalid_params` / `busy` …），不要匹配 message。
- 并发调用靠自增 id 配对，回来顺序不保证。
- **多开互不干扰**：id 只在**本条连接内**配对，服务端也不会把 A 的应答发给 B
  （见 daemon 的「多客户端隔离」）。同一个 App 里同时连多台服务器同理。
  事件只发给订阅了的连接 —— 没订的连接一帧都收不到。
- 想让「断线重连后自动恢复订阅」，用
  `ref.read(connectionProvider.notifier).subscribe(topic)`。

## 测试

```bash
cd app
flutter analyze                 # 0 issue
flutter test                    # 全部用例
flutter test --exclude-tags e2e # 只跑前端用例（不需要后端二进制）
```

- `test/connection_test.dart` —— 连接流程：地址解析、首次守卫、成功 / 失败 / 令牌错、
  掉线与自动重连、设置页改地址 / 断开 / 忘记，以及「连接途中改目标」的竞态。
- `test/glass_ui_test.dart` —— 毛玻璃与设置项 Provider。
- `test/daemon_e2e_test.dart` —— **真机联调**：拉起真实 daemon 进程
  （`port = 0` 让系统分配，再从 JSON 日志里读回端口），用真实 WebSocket 走完
  握手 / 调用 / 订阅推送 / 鉴权拒绝。没编译后端时自动 skip：

  ```bash
  cd daemon && cargo build
  ```

- `test/support/fake_transport.dart` —— 内存假传输，Widget 测试用它替代真实网络。

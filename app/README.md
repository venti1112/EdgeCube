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
- 两个现成的订阅者可以照抄，分别代表两种用法：
  - `instance/providers.dart` —— 事件只说「变了」，收到就 `invalidate` 重新拉；
  - `monitor/providers.dart` —— 事件里**直接带完整状态**，塞进 `state` 即可，
    别再回一次 `<domain>.snapshot`（那会把 WS 流量翻倍）。
- 「取消全部订阅」是字面意思，连页面自己声明的那几条也会取消，
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
│   ├── servers_page.dart     主界面「服务器」页：选中实例的控制面板
│   │                         （卡片集合 / 顺序 / 间距逐项对齐；
│   │                          启动 / 停止 / 重启 / 强制停止已接上 daemon）
│   ├── manage_page.dart      主界面「管理」页：各管理子页的入口列表
│   └── port_mapping_page.dart 「网络映射」：FRP 卡 + UPnP 状态总览卡 + STUN / DDNS（置灰）
│   └── files_page.dart       主界面「文件」页：挂着远程文件浏览器
├── instance/
│                             （`eula.dart` 是启动前的 EULA 关卡）
│   ├── models.dart           实例的线上模型（与 daemon 的 snake_case 一一对应）
│   ├── api.dart              instance.* 方法的 Dart 封装
│   ├── providers.dart        列表 / 选中详情 / 事件刷新
│   ├── create_instance_page.dart   新建向导（只实现了「创建空实例」，其余置灰）
│   ├── instance_list_sheet.dart    底部实例列表（切换 / 删除 / 新建）
│   ├── instance_settings_dialog.dart  实例设置：名称 / 启动命令 / 兼容模式 / 自动重启 / 换行符 / 路由器端口映射
│   └── config/               服务器配置（一个通用页，认哪种配置在 daemon 那边）
│       ├── config_page.dart  入口页：问 `instance.config.get` → 按 kind 选字段表
│       ├── parsers.dart      server.properties / YAML 的行级编辑器（保留注释与排版）
│       ├── draft.dart        一次编辑会话：脏判定 + 只写改动过的字段
│       ├── models.dart       字段表模型（ConfigFieldDef / ConfigSection）
│       ├── sections.dart     四份字段表（java / pmmp / pnx / allay）
│       ├── icon_crop_page.dart  图标裁剪页（黑底取景：拖动 + 双指缩放 + 64×64）
│       └── icon_image.dart   图片解码 / 裁剪 / PNG 编码（`dart:ui`，不引图片库）
├── monitor/
│   ├── models.dart           SystemSnapshot（设备内存 + CPU）
│   └── providers.dart        系统状态：首拉 monitor.snapshot + 订阅 monitor.stats
├── console/
│   ├── pty_transport.dart    控制台连接的最小抽象（生产 = WebSocket，测试 = 内存）
│   ├── pty_client.dart       /pty/{id} 的协议：历史快照 / 实时输出 / 敲键 / resize
│   └── console_page.dart     控制台页：xterm2 终端 + 字号 / 清屏 / 重连 + 扩展按键栏
├── files/                    文件管理：远程浏览 / 编辑 / 查找 / 上传下载
│                             （`client_files*.dart` 是客户端本机目录的平台分派，
│                              IO 真遍历，Web 不支持「导入文件夹」）
├── players/                  玩家管理：在线 / 白名单 / 封禁 / IP 封禁 / OP
│                             （在线玩家由 daemon 解析日志得到，前端只发命令读结果）
├── frp/                      映射隧道：平台登录 / 隧道列表 / 配置生成 / **隧道运行**
│   ├── api.dart              frp.* 方法的 Dart 封装（含 frp.run.* / frp.runtimes）
│   ├── models.dart           线上模型（平台 / 授权会话 / 隧道 / 运行态，snake_case 对应）
│   ├── providers.dart        接口 + 隧道清单 + 运行清单（订阅 frp.run 事件）
│   ├── frp_provider_picker_page.dart  选择平台（六项里含「自定义 FRP」）
│   ├── frp_login_page.dart            账号登录：粘贴令牌 / 浏览器授权
│   │                                  （**发起与轮询都在 daemon**，前端只显示 daemon 推的状态）
│   ├── frp_provider_tunnels_page.dart 平台隧道：我的隧道（挑一条存本地）+ 创建
│   ├── frp_tunnel_list_page.dart      本地隧道列表（卡片带运行状态，点进运行页）
│   ├── frp_run_page.dart              单条隧道的运行页：启停 + 地址复制 + 日志
│   ├── frp_tunnel_config_page.dart    隧道配置：预览 / 重新生成 / 删除
│   └── frp_custom_config_page.dart    自定义 FRP：简易表单或直接粘贴 frpc 配置
├── mods/                     模组与插件（管理 / 下载两组标签）
│   ├── api.dart              mods.* 方法的 Dart 封装 + 错误码翻译
│   ├── models.dart           线上模型（源 / 项目类型 / 搜索命中 / 版本 / 已装元数据 / 更新 / 项目匹配）
│   ├── providers.dart        接口 + 表 + 游戏版本 + 已装清单 + 图标匹配（订阅 mods.changed）
│   ├── mods_page.dart        「模组/插件管理」：**四个标签**（插件管理 / 插件下载 /
│   │                         模组管理 / 模组下载，标签数由目录存不存在算出来），
│   │                         管理标签里是「共 N 项 + 四个图标按钮 + 更新横幅 + 卡片列表」
│   ├── mod_download_page.dart 下载标签：搜索行 + 筛选 Chip + 结果卡 + 触底翻页 +
│   │                         版本底部弹层 + 版本详情页 + 外部链接对话框；
│   │                         文件末尾还放着 `DownloadQueueBanner` 与 `showDownloadQueueSheet`
│   └── client_mods_cleanup_dialog.dart  「清理客户端模组」对话框（判据来自 daemon）
├── shell/
│   ├── home_shell.dart       底栏 / 侧栏 + 内容区（含毛玻璃）
│   └── connection_banner.dart 未连接时的顶部横幅
└── settings/
    ├── main.dart             设置入口
    ├── connection_page.dart  连接设置：改地址重连 / 断开 / 忘记服务器
    ├── appearance.dart       外观设置（主题、背景、毛玻璃）
    ├── appearance_page.dart
    ├── about.dart            关于页：两端设备信息的采集 / 解析
    ├── about_page.dart       关于页：前端 / 后端两张设备卡
    ├── about_platform_io.dart   Linux 主机名 / 内存与逻辑核数
    ├── about_platform_web.dart  Web 端同名占位（CPU/内存走浏览器 API）
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

## 关于页

设置 → 关于：两张卡分别是「前端运行设备」和「后端运行设备」。

- **前端**：`clientDeviceInfoProvider` 采集平台 / 系统 / 型号（桌面端是主机名）/
  CPU 核心 / 内存 / 应用版本；Linux 插件不提供主机名与内存，由
  `about_platform_io.dart` 补，Web 用浏览器信息。屏幕尺寸来自 `MediaQuery`，
  是**当前窗口**的逻辑尺寸与 DPR，不是显示器物理分辨率。
- **后端**：`daemonDeviceInfoProvider` 先调 `core.host` 拿主机信息，再调
  `core.info` 拿 daemon 版本与运行时长。未连接时后端卡只显示「未连接」；
  旧 daemon 没有 `core.host` 时提示升级，但版本号照常显示。
- 设备字段拿不到时写「未知」，不把整张卡变成错误态 —— 这是网络 / 插件边界，
  契约漂移由针对 `core.host` 的测试兜底。

## 回到文件页时自动比对

切到「文件」页签时（`index == 3`）：**重列当前目录 → 与已显示的逐条比路径与
「是不是目录」→ 一样就什么都不做**，不一样才换掉。

实现是一条自增信号（`files/providers.dart` 的 `filesRefreshProvider`）：
`HomeShell` 切到文件页签时 `bump()`，`FileBrowser` 在 `build` 里 `ref.listen` 它去
`_checkAndRefresh()`。两处细节：

- **先比对再 setState**：一模一样时连一次重建都不做 —— 否则每次切页签都重建列表，
  滚动位置会跳回顶部、还会白闪一下；
- **静默**：比对失败不弹提示（这只是「顺手看一眼」）；
- 顺带一条保险：结果回来时如果用户已经点进别的目录（`path != _path`），
  这次结果直接丢掉。

`bump()` 放在 `goBranch` **之前**：比对在页面还没露出来时就开始，
等它出现内容已经对了。

## 图片查看器

点图片文件直接全屏看：
`files/models.dart` 的 `imageExtensions`（png/jpg/jpeg/gif/webp/bmp，全在 Flutter 原生解码范围，
**不引图片解码依赖**，与服务端图标同一条取舍）+ `files/image_viewer.dart` 的
`ImageViewerPage`（HTTP 下载 → `Image.memory` 全屏预览 + `InteractiveViewer` 捏合缩放）。

要点：

- 图片在**服务端机器上**，要经 `FileTransfer.download` 下载（与编辑器下载正文是同一条路）；
- 分派优先级在 `file_browser.dart` 的 `onTap`：目录 → 图片 → 可编辑文本 → 什么都不做；
- 字节不是合法图片（下错了 / 文件损坏）走 `errorBuilder`，**不把页面炸了**；
- 下载失败有「重试」，黑底看图（透明 png 看得最清楚）。

## 一个坑：手写 `basename` 没剪尾斜杠

「导入文件夹」曾报「名称不能为空」（daemon 日志 `instance.files.mkdir → invalid_params`）。
根因在 `files/client_files_io.dart` 的 `_basename`：`getDirectoryPath()` 走 XDG 门户，
给文件夹的 URI 常是 `file:///home/x/photos/` 这种**带尾斜杠**的，`toFilePath()` 原样保留，
手写的「取最后一段」于是返回空串 → 拿空名字去 `mkdir`。

修法就是 `_basename` 里**先剪掉结尾的 `/` 与 `\`**（`package:path` 的 `basename` 本来就这么做）。
顺带加了个保险：剪完还是空（选了盘根 `/` 或 `C:\`）就直接报「不能导入磁盘根目录」，
别再把非法请求发给 daemon。回归用例：`选中的文件夹路径带尾斜杠时，名字也不为空`。

## 一个 Dart 的坑：`Stream.pipe` 按运行期类型检查

`files/transfer.dart` 的上传原来是 `content.pipe(request.sink)`。
`Stream.pipe` 的签名是 `Future pipe(StreamConsumer<T> consumer)`，**`T` 取接收者的
运行期类型参数**：真实调用方给的是 `Stream<Uint8List>`（`pickFiles().readAsByteStream()`
与 `File.openRead()` 都产出 `Uint8List`），于是运行期要求
`StreamConsumer<Uint8List>`，而 `request.sink` 是 `_StreamSinkWrapper<List<int>>`
→ 抛 `type '_StreamSinkWrapper<List<int>>' is not a subtype of type
'StreamConsumer<Uint8List>' of 'streamConsumer'`。

**静态类型写的是 `Stream<List<int>>`，所以编译期与 analyze 都看不出来**，
只有真发一个文件才炸。改用 `sink.addStream(content)`（参数是 `Stream<List<int>>`，
协变，天然满足），并**自己 `close()`**（`pipe` = addStream + close，
不补这一步请求体永远不结束，`send` 会挂死）。

## 测试

```bash
cd app
flutter analyze                 # 0 issue
flutter test                    # 全部用例
flutter test --exclude-tags e2e # 只跑前端用例（不需要后端二进制）
```

- `test/connection_test.dart` —— 连接流程：地址解析、首次守卫、成功 / 失败 / 令牌错、
  掉线与自动重连、设置页改地址 / 断开 / 忘记，以及「连接途中改目标」的竞态。
  ⚠️ **当前 5 个用例是红的**：它们还在找 `servers_target` / `servers_subscriptions`
  / `servers_pending_subscriptions` 这些属于更早的「连接概览版」服务器页的 Key，
  那些控件在服务器页改成实例控制面板后就没了。这些断言该改成打在连接横幅 /
  设置 → 连接页上，属于待办的清理。
- `test/glass_ui_test.dart` —— 毛玻璃与设置项 Provider。
  ⚠️ **3 个用例同样是红的**，原因同上（`_shellMarker` 找的是 `servers_target`）。
  **当前全量基线（`--exclude-tags e2e`）：216 通过 / 8 失败**（5 + 3），都是这笔债。
- `test/monitor_test.dart` —— 系统状态 Provider：未连接只登记意图、连上先拉
  `monitor.snapshot`、之后靠 `monitor.stats` 推送更新（且**不**回拉）、
  `cpu_usage` 为 null / 平台不支持时退化成「不可用」。
- `test/about_test.dart` —— 关于页：前端 / 后端两张卡各自的数据、未连接不是错误、
  旧 daemon 缺 `core.host` 时只降级，以及 `core.host` 的宽容解析。
- `test/console_test.dart` —— 控制台协议（注入内存传输，不用起 daemon）：
  历史 begin/end、**跨块的多字节字符不被切开**、敲键走二进制帧 / resize 走文本帧、
  `exit` 带退出码、连接断开变成可显示的错误态、未连接时 write/resize 不抛。
- `test/files_test.dart` —— 文件管理：列目录 / 进出子目录、新建 / 重命名 / 删除、
  长按多选与批量移动 / 复制、搜索（当前目录 vs 含子目录）、压缩与解压。
  还有三条钉「回到文件页自动比对」：
  目录变了要刷新、**没变就不重建**（不转圈）、以及**切页签这个触发点本身**
  （走真外壳 + 真路由，不是手动发信号）。
  HTTP 上传那几条**必须用 `Uint8List` 写流**（真实调用方就是给 `Uint8List`）：
  用 `Stream<List<int>>` 会恰好绕过 `Stream.pipe` 的**运行期**类型检查，
  于是「用例全绿、真发文件就炸」（见下面那条坑）。
- `test/players_test.dart` —— 玩家管理：在线快照 + 事件整份替换、五类名单的标签、
  命令字符串逐条钉住（含按实例换行符收尾、服务端没在跑时的只读态）。
- `test/frp_test.dart` —— 映射隧道（全是假 daemon，平台侧的一切都在 daemon）：
  本地隧道列表、选择平台、令牌登录 / 浏览器授权（进度只认 daemon 推的事件，
  App 自己不轮询）、**挂载早于连上时连上后补问会话**、自定义 FRP 的两种表单、
  平台隧道的「使用 / 创建 / 令牌失效」。两个坑：页面上到处是不确定进度的
  `CircularProgressIndicator`，别用 `pumpAndSettle`（用 `pumpFrames`）；复制链接是
  「await 完剪贴板才提示」，测试里要先给 `SystemChannels.platform`
  挂个 mock，否则那句话永远不出现。
- `test/eula_test.dart` —— EULA 同意机制：**已同意就不弹框**、未同意弹框
  （标题 / 正文 / 链接 / 说明 / 「不同意」「同意」逐字照 `server.eula.*`）、
  **点「不同意」什么都不写**（不调 `instance.eula.accept`）、点框外面关不掉
  （`barrierDismissible: false`）。daemon 侧那一半由 `daemon_e2e_test.dart`
  的「EULA 同意机制」钉住（含写出来的内容与宽松判定口径）。
- `test/mods_test.dart` —— 模组与插件（全是假 daemon），**按当前排版钉**：
  标签由目录决定（0 个 → 空态两句、只有 mods → 2 个、两个都有 → 4 个、
  PocketMine 时插件那一栏叫「Poggit 插件」且认 `.phar`）、主行用 jar 里读出来的名字、
  **副行是「版本 · 加载器」+ 描述、没有元数据时退回文件大小**、
  行上是**三个独立图标按钮**（不是 Switch）、启停与删除都有确认框且参数对
  （尤其 `project_type`，它决定落 `mods/` 还是 `plugins/`）、
  检查更新出「N 个模组可更新」横幅（这句话**横幅与 SnackBar 各显示一次**）、
  客户端模组清理（没有就只提示不弹窗 / 有就默认全选再逐个删），
  以及下载那条路（搜索、版本弹层、版本详情、提交 `mods-install`、队列横幅）。
  另外两条专门钉筛选细节：**插件页的加载器菜单里不许出现 Fabric/Forge**
  （加载器表按项目类型分成两张，含 `waterfall`），以及**游戏版本菜单里正式版排在快照前面、
  非正式版带类型副标题**。还有两条钉「两端形状对不上」的可见性：
  旧 daemon 的纯字符串 `game_versions` 要能容错解析，**真认不出来时筛选条上要写
  「需重启守护进程」**（静默变成「菜单里只有任意」是最难查的）。
  **别用 `pumpAndSettle`**（进度环是无限动画），项目里的写法是推固定帧数。
- `test/daemon_e2e_test.dart` —— **真机联调**：拉起真实 daemon 进程
  （`port = 0` 让系统分配，再从 JSON 日志里读回端口；`EDGECUBE_DATA_DIR` 指到
  自己的临时目录，别写开发机的数据目录），用真实 WebSocket 走完
  握手 / 调用 / 订阅推送 / 鉴权拒绝，并校验各模块的线上格式能被前端的模型解析
  （字段名 / 类型对不上会在这里炸）—— `monitor` 的 `SystemSnapshot`、
  模组的「目录规则 + 启停改名 + 已装清单」。没编译后端时自动 skip：

  ```bash
  cd daemon && cargo build
  ```

  它**不真下模组**：往实例目录里放的是内容不是 zip 的 `.jar`，验的是「读不出元数据
  时 `meta` 是 null」这条契约 —— daemon 那套 `fabric.mod.json` 解析由它自己的单测
  与 `tests/framework.rs` 钉住，不在这里重演。

- `test/support/fake_transport.dart` —— 内存假传输，Widget 测试用它替代真实网络。

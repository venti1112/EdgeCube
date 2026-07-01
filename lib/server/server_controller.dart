import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:port_forwarder/port_forwarder.dart';
import 'package:xterm/xterm.dart';

import 'pnx_properties.dart';
import 'server_properties.dart';
import 'server_service.dart';
import 'upnp_service.dart';
import '../config/network_store.dart';
import '../config/terminal_store.dart';
import '../tunnel/tunnel_service.dart';
import 'runtime_service.dart';

/// 匹配 Minecraft 服务端日志中玩家加入/离开的正则（兼容英文与中文输出）。
///
/// 捕获组 1 均为玩家名：英文匹配 `Name[/ip] logged in` / `Name left the game`，
/// 中文匹配 Nukkit/PowerNukkitX 的 `Name 加入了游戏` / `Name 退出了游戏`。
final _reJoin = RegExp(
  r'(\w{1,16})(?:\[/[\d.:]+\] logged in| 加入了游戏|[/\d.:]+\] 登入游戏)',
);
final _reLeave = RegExp(r'(\w{1,16})(?: left the game| 退出了游戏|[/\d.:]+\] 登出游戏)');

/// 匹配 `list` 命令响应中的在线玩家列表。
///
/// 英文：`There are X of Y players online: name1, name2`
/// 中文（Nukkit/PNX）：`目前有 X/Y 个玩家在线：name1, name2`
final _reListResp = RegExp(r'(?:online|在线)[：:]\s*(.*)');

/// 服务端进程的运行状态。
///
/// - [stopped]：进程未运行。
/// - [preparing]：正在解压 JRE 运行时。
/// - [starting]：JVM 已启动，服务端正在初始化（尚未输出 Done）。
/// - [running]：服务端初始化完成，可接受玩家连接。
/// - [stopping]：已发送 stop 命令，等待进程退出。
enum ServerStatus { stopped, preparing, starting, running, stopping }

/// 服务端意外退出时的崩溃报告数据。
class CrashData {
  const CrashData({
    required this.exitCode,
    required this.logLines,
    required this.envType,
    required this.envRuntimeId,
    this.kind = 'server',
  });

  final int exitCode;
  final List<String> logLines;

  /// 运行环境类型：'java' 或 'php'。
  final String envType;

  /// 运行环境标识：如 'jre21'、'php8.2'。
  final String envRuntimeId;

  /// 崩溃来源：'server'（服务端）或 'tunnel'（FRP 隧道）。
  /// UI 根据此字段切换标题/文案；'tunnel' 时不显示 envType/envRuntimeId。
  final String kind;
}

/// 管理服务端进程的运行状态与日志缓冲，并把 UI 操作转发到 [ServerService]。
///
/// 单活动进程模型：同一时刻只跟踪一个正在运行的服务端，[runningInstanceId]
/// 标识它属于哪个实例。日志为所有页面共享，故本控制器置于全局 Scope。
class ServerController extends ChangeNotifier {
  ServerController({
    ServerService? service,
    UpnpService? upnp,
    TunnelService? tunnel,
  }) : _service = service ?? ServerService(),
       _upnp = upnp ?? UpnpService(),
       _tunnel = tunnel ?? TunnelService() {
    _sub = _service.events().listen(_onEvent);
    _tunnelSub = _tunnel.events().listen(_onTunnelEvent);
    terminal.onOutput = _onTerminalOutput;
    terminal.onResize = _onTerminalResize;
  }

  final ServerService _service;
  final UpnpService _upnp;
  final TunnelService _tunnel;
  late final StreamSubscription<ServerEvent> _sub;
  late final StreamSubscription<TunnelEvent> _tunnelSub;

  /// 交互式终端（xterm）。由本控制器持有，故切页/页面重建时内容不丢失。
  /// 所有可见输出（PTY 字节与 EdgeCube 提示）都经 [_feedTerm]/[_emitOutput] 同步写入，
  /// 以保证服务端输出与本地命令行提示符的显示顺序正确。
  // reflowEnabled: false —— xterm 4.0.0 的 reflow 在 resize（缩放字号导致列数
  // 变化）时会保留旧单元格，再次变宽时旧数据重现，导致内容行数翻倍累积
  // （上游 PR #227 未合并）。禁用后变窄时截断长行而非重排，避免重复。
  final Terminal terminal = Terminal(
    maxLines: _maxLogLines,
    reflowEnabled: false,
  );

  // —— PTY 原始字节 → UTF-8 解码（allowMalformed 避免非法字节中断）——

  /// 终端扩展按键栏的「粘滞修饰键」：点亮后只对下一次输入生效一次，随即自动复位
  /// （与 Termux 的 CTRL/ALT 行为一致）。仅在原始终端模式下用于变换软键盘按键。
  bool _ctrlDown = false;
  bool _altDown = false;
  bool get ctrlDown => _ctrlDown;
  bool get altDown => _altDown;

  // ——————————————————————————————————————————————————————————
  // 输入模式：命令行编辑（默认）/ 原始终端
  // ——————————————————————————————————————————————————————————

  /// true=命令行编辑模式：App 在终端内做本地行编辑（`> ` 提示符、回显、Backspace、
  /// ↑↓ 历史、回车整行发送），PTY 关闭回显/规范模式；对所有服务端稳定可用。
  /// false=原始终端模式：逐键直达 PTY，回显/行编辑交给 tty 与服务端自身（如 JLine）。
  bool _lineMode = true;
  bool get lineMode => _lineMode;

  // —— 本地命令行编辑器状态（仅 [_lineMode] 时有效）——
  String _input = '';
  final List<String> _history = [];
  int _histPos = 0; // 0.._history.length；== length 表示「正在编辑的新行」
  String _histStash = ''; // 浏览历史时暂存的在编辑内容
  static const int _maxHistory = 200;

  /// 异步解析指定实例是否启用兼容模式。由外层（main）注入，读取实例的配置文件。
  /// 用于应用被回收后原生状态回放（未经过本会话 [start]）时恢复兼容模式标志。
  Future<bool> Function(String instanceId)? compatModeResolver;

  /// 解析当前是否启用了 UPnP 端口映射。由外层（main）注入，读取配置文件。
  Future<bool> Function()? upnpEnabledResolver;

  /// 解析 UPnP 自定义外网端口。由外层（main）注入，读取配置文件。
  /// 返回 null 表示使用服务端端口。
  Future<int?> Function()? upnpExternalPortResolver;

  /// 解析 UPnP 映射协议。由外层（main）注入，读取配置文件。
  /// 返回 'tcp' 或 'udp'，默认 'tcp'。
  Future<String> Function()? upnpProtocolResolver;

  /// 解析当前是否启用了 FRP 隧道。由外层（main）注入，读取配置文件。
  Future<bool> Function()? tunnelEnabledResolver;

  /// 当前运行实例的兼容模式标志。[start] 时由调用方传入并缓存，供状态事件
  /// 同步判定；回放路径下若与缓存实例不符，则经 [compatModeResolver] 异步补正。
  bool _compatMode = false;

  /// [_compatMode] 当前对应的实例 id；与待判定实例不符即触发异步补正。
  String? _compatModeId;

  /// 日志环形缓冲上限，超出丢弃最旧的行。
  static const int _maxLogLines = 5000;

  ServerStatus _status = ServerStatus.stopped;
  String? _instanceId;
  String? _instanceName;
  String? _workingDir;
  int? _lastExitCode;
  final List<String> _log = [];
  final Set<String> _onlinePlayers = {};

  /// FRP 隧道（frpc）日志缓冲。供崩溃报告导出使用。
  /// 与 [_log] 分离：frpc 日志不写入服务端终端，但需在异常退出时一并导出。
  final List<String> _tunnelLog = [];

  // —— 运行时类型/标识追踪（崩溃报告用）——
  String _runtimeType = '';
  String _runtimeId = '';

  // —— 用户主动操作标志（区分意外退出与主动停止）——
  bool _userStopping = false;

  // —— PowerNukkitX 首次启动向导自动应答 ——
  // PNX 首次运行时会弹出交互式向导（语言→许可→跳过→启动），这里自动完成。
  int _pnxWizardStep = 0; // 0=未触发, 1=等待许可, 2=等待跳过, 3=等待启动
  bool _userForceStopping = false;

  // —— UPnP / FRP 即时状态标志 ——
  bool _upnpActive = false;
  bool _tunnelActive = false;
  bool _restartingTunnel = false;

  // —— FRP 隧道进程状态追踪 ——
  // _tunnelRunning: frpc 进程是否真正进入 STATUS_RUNNING（看到 "login to server
  //   success" 日志）；用于区分"进程已拉起但未连接成功"与"已成功连接到 frps"。
  // _userStoppingTunnel: 区分用户主动停止（stop / disableTunnelNow /
  //   applyTunnelConfig / restartTunnel）与 frpc 进程异常退出；前者静默，
  //   后者需要提示。
  // _tunnelCrashed: frpc 上次异常退出（非用户主动停止且退出码非 0）标志。
  //   UI 据此在主页状态芯片显示"出错"（红色）；重新启动或主动停止时复位。
  bool _tunnelRunning = false;
  bool _userStoppingTunnel = false;
  bool _tunnelCrashed = false;

  // —— 崩溃回调：服务端意外退出时触发 ——
  /// 当服务端非正常退出（退出码不为 0 且非用户主动停止）时调用。
  /// UI 层应监听此回调并展示崩溃报告弹窗。
  void Function(CrashData crash)? onCrashExit;

  /// 当 FRP 隧道进程异常退出（非用户主动停止且退出码非 0）时调用。
  /// UI 层应监听此回调并展示与 [onCrashExit] 同款的崩溃报告弹窗。
  void Function(CrashData crash)? onTunnelCrashExit;

  // —— 映射结果追踪 ——
  String? _upnpExternalIp; // UPnP 映射成功后的公网 IP
  FrpcConfig? _activeFrpcConfig; // 当前活跃的 FRP 配置
  int? _serverPort; // 从配置文件读取的服务端端口（启动时缓存）

  ServerStatus get status => _status;
  bool get isRunning => _status == ServerStatus.running;
  bool get isBusy =>
      _status == ServerStatus.preparing ||
      _status == ServerStatus.starting ||
      _status == ServerStatus.stopping;
  String? get runningInstanceId => _instanceId;
  String? get runningInstanceName => _instanceName;
  int? get lastExitCode => _lastExitCode;
  List<String> get log => List.unmodifiable(_log);
  Set<String> get onlinePlayers => Set.unmodifiable(_onlinePlayers);

  // —— 映射状态公共接口 ——
  bool get isUpnpActive => _upnpActive;
  bool get isTunnelActive => _tunnelActive;

  /// frpc 是否真正连接到 frps 成功（看到 "login to server success"）。
  /// 区别于 [isTunnelActive]（仅表示进程已拉起）。UI 应以此作为"已映射"依据，
  /// 以 [isTunnelActive] 作为"映射中"依据。
  bool get isTunnelRunning => _tunnelRunning;

  /// frpc 上次是否异常退出。UI 据此在状态芯片显示"出错"（红色）。
  bool get isTunnelCrashed => _tunnelCrashed;
  String? get upnpExternalIp => _upnpExternalIp;
  int? get upnpMappedPort => _upnp.mappedPort;
  FrpcConfig? get activeFrpcConfig => _activeFrpcConfig;

  /// 服务端实际监听端口（启动时从配置文件读取并缓存）。
  int? get serverPort => _serverPort;

  /// 从实例目录的 server.properties 或 pnx.yml 读取服务端实际监听端口。
  ///
  /// 用于内网地址显示等需要真实端口的场景，与 UPnP 映射状态无关。
  Future<int?> readServerPort() async {
    final dir = _workingDir;
    if (dir == null) return null;
    try {
      final propsFile = File(p.join(dir, 'server.properties'));
      if (await propsFile.exists()) {
        final props =
            ServerProperties.parse(await propsFile.readAsString());
        return props.getInt('server-port') ?? 25565;
      }
      final pnxFile = File(p.join(dir, 'pnx.yml'));
      if (await pnxFile.exists()) {
        final pnx = PnxProperties.parse(await pnxFile.readAsString());
        return pnx.getPort();
      }
      return 25565;
    } catch (_) {
      return 25565;
    }
  }

  /// 是否正有某个“其它”实例在运行（用于禁用对当前实例的启动）。
  bool isOtherRunning(String instanceId) =>
      _status != ServerStatus.stopped && _instanceId != instanceId;

  /// 当前实例是否就是正在运行/启动中的那个。
  bool isActive(String instanceId) => _instanceId == instanceId;

  /// 启动服务端。[runtime] 为 `'java'` 或 `'php'`：
  /// Java 版 [jvmArgs] 如 `['-Xmx1024M']`、[programArgs] 如 `['-jar','server.jar','nogui']`；
  /// PHP 版 [jvmArgs] 为空、[programArgs] 即 `['PocketMine-MP.phar']`。
  Future<void> start({
    required String instanceId,
    required String instanceName,
    required String workingDir,
    required String runtimeId,
    required String runtime,
    required List<String> jvmArgs,
    required List<String> programArgs,
    bool compatMode = false,
  }) async {
    if (_status != ServerStatus.stopped) return;
    if (await TerminalStore.loadAutoClearLogOnStart()) {
      clearLog();
    }
    _instanceId = instanceId;
    _instanceName = instanceName;
    _workingDir = workingDir;
    _lastExitCode = null;
    _runtimeType = runtime;
    _runtimeId = runtimeId;
    _compatMode = compatMode;
    _compatModeId = instanceId;
    _userStopping = false;
    _userForceStopping = false;
    _pnxWizardStep = 0;
    _status = ServerStatus.preparing;
    _notice('[EdgeCube] 启动 $instanceName …');
    notifyListeners();
    try {
      await _service.start(
        instanceId: instanceId,
        instanceName: instanceName,
        workingDir: workingDir,
        runtimeId: runtimeId,
        runtime: runtime,
        jvmArgs: jvmArgs,
        programArgs: programArgs,
      );
      // 兜底：若 state 事件尚未把状态推进到 starting/running。
      // 兼容模式下跳过「启动中」，直接视为「运行中」。
      if (_status == ServerStatus.preparing) {
        _status = _compatFor(instanceId)
            ? ServerStatus.running
            : ServerStatus.starting;
        if (_status == ServerStatus.running) {
          _cacheServerPort();
          _triggerUpnp();
          _triggerTunnel();
        }
        notifyListeners();
      }
    } catch (e) {
      _notice('[EdgeCube] 启动失败：$e');
      _status = ServerStatus.stopped;
      _instanceId = null;
      _instanceName = null;
      _serverPort = null;
      notifyListeners();
    }
  }

  /// 优雅停止（向服务端发送 stop 命令）。
  Future<void> stop() async {
    if (_status != ServerStatus.running) return;
    _userStopping = true;
    _status = ServerStatus.stopping;
    _notice('[EdgeCube] 正在停止（已发送 stop 命令）…');
    notifyListeners();
    await _service.stop();
  }

  /// 强制结束进程。
  Future<void> forceStop() async {
    if (_status == ServerStatus.stopped) return;
    _userForceStopping = true;
    _notice('[EdgeCube] 强制结束进程…');
    await _service.forceStop();
  }

  /// 程序化发送一行控制台命令（如玩家管理页的 op/kick/list；启动中、运行中、
  /// 停止中均有效）。命令写入 PTY 后，由终端行规程自行回显，无需手动回显到终端。
  Future<void> sendCommand(String line) async {
    final cmd = line.trim();
    if (cmd.isEmpty) return;
    if (_status != ServerStatus.starting &&
        _status != ServerStatus.running &&
        _status != ServerStatus.stopping) {
      return;
    }
    await _service.sendCommand(cmd);
  }

  /// 终端按键输入入口（[terminal] 的 onOutput）：软键盘、[sendKey]、[sendText] 都汇聚于此。
  /// 命令行编辑模式 → 交给本地行编辑器；原始模式 → 应用粘滞修饰后逐键直达 PTY。
  void _onTerminalOutput(String data) {
    if (_lineMode) {
      _handleLineInput(data);
      return;
    }
    final modified = (_ctrlDown || _altDown) ? _modifyChar(data) : null;
    final bytes = modified ?? utf8.encode(data);
    _service.writeInput(Uint8List.fromList(bytes));
    _clearModifiers();
  }

  /// 对单个字符应用粘滞的 Ctrl/Alt：Ctrl 把 a–z / @[\]^_ 映射到 0x00–0x1f，
  /// Alt 加 ESC 前缀。返回要写入的字节；不适用（多字符或无映射）时返回 null。
  List<int>? _modifyChar(String data) {
    if (data.length != 1) return null;
    var cc = data.codeUnitAt(0);
    if (_ctrlDown) {
      if (cc >= 0x61 && cc <= 0x7a) cc -= 0x20; // 小写转大写
      if (cc >= 0x40 && cc <= 0x5f) {
        final ctrlByte = cc & 0x1f;
        return _altDown ? [0x1b, ctrlByte] : [ctrlByte];
      }
    }
    if (_altDown) return [0x1b, ...utf8.encode(data)];
    return null;
  }

  /// 复位粘滞修饰键（每次输入消费后调用）。仅在原始终端模式下生效。
  void _clearModifiers() {
    if (!_ctrlDown && !_altDown) return;
    _ctrlDown = false;
    _altDown = false;
    notifyListeners();
  }

  /// 切换粘滞 Ctrl（扩展按键栏的 CTRL 键）。
  void toggleCtrl() {
    _ctrlDown = !_ctrlDown;
    notifyListeners();
  }

  /// 切换粘滞 Alt（扩展按键栏的 ALT 键）。
  void toggleAlt() {
    _altDown = !_altDown;
    notifyListeners();
  }

  /// 切换命令行编辑模式 / 原始终端模式。
  void toggleLineMode() => setLineMode(!_lineMode);

  /// 设置输入模式并同步 PTY 回显。
  void setLineMode(bool on) {
    if (_lineMode == on) return;
    _lineMode = on;
    _service.setEcho(!on); // 行编辑模式关回显，原始模式开回显
    if (on) {
      // 切到行编辑：重置编辑器状态，在当前终端末行画上 prompt。
      _input = '';
      _histPos = _history.length;
      _histStash = '';
      _redrawPrompt();
    }
    notifyListeners();
  }

  /// 发送一个特殊键（ESC / TAB / 方向键 / HOME / END / PgUp / PgDn 等）。
  /// 行编辑模式直接操作编辑器；原始模式经 xterm 的 inputHandler 生成转义序列。
  void sendKey(TerminalKey key) {
    final ctrl = _ctrlDown;
    final alt = _altDown;
    _clearModifiers();
    if (_lineMode) {
      _handleLineKey(key, ctrl: ctrl, alt: alt);
      return;
    }
    terminal.keyInput(key, ctrl: ctrl, alt: alt);
  }

  /// 发送一段字面文本（扩展按键栏的 `-` `/` `|` 等）。
  void sendText(String text) {
    if (_lineMode) {
      for (var i = 0; i < text.length; i++) {
        _handleLineChar(text.codeUnitAt(i));
      }
      return;
    }
    _onTerminalOutput(text);
  }

  /// 终端尺寸变化 → 同步 PTY 窗口大小。由 [terminal] 的 onResize 触发。
  void _onTerminalResize(
    int width,
    int height,
    int pixelWidth,
    int pixelHeight,
  ) {
    _service.resize(
      cols: width,
      rows: height,
      cellWidth: width > 0 ? pixelWidth ~/ width : 0,
      cellHeight: height > 0 ? pixelHeight ~/ height : 0,
    );
  }

  // ——————————————————————————————————————————————————————————
  // 同步终端写入（替代异步 Stream，保证 prompt 与输出顺序正确）
  // ——————————————————————————————————————————————————————————

  /// 同步写 UTF-8 字符串到终端。
  void _writeTerm(String s) {
    if (s.isEmpty) return;
    terminal.write(s);
  }

  /// 把 PTY 原始字节解码为 UTF-8 字符串并同步写入终端。
  /// PTY 输出以短批次到达（通常一到数行），单次解码即可，多字节字符跨分片的概率极低
  /// 且 allowMalformed 下也会产出 U+FFFD 不致丢数据。
  void _feedTerm(Uint8List bytes) {
    final str = utf8.decode(bytes, allowMalformed: true);
    if (str.isNotEmpty) _writeTerm(str);
    // PTY 新输出到达后重绘 prompt，保证 `> ` 始终在最末行。
    if (_lineMode) _redrawPrompt();
  }

  // ——————————————————————————————————————————————————————————
  // 本地命令行编辑器（仅 [_lineMode] 时生效）
  // ——————————————————————————————————————————————————————————

  /// 处理 xterm 汇聚来的终端输出（软键盘打字 / sendText）。
  /// 在行编辑模式下，不逐键写 PTY，而是做本地行编辑。
  void _handleLineInput(String data) {
    for (var i = 0; i < data.length; i++) {
      _handleLineChar(data.codeUnitAt(i));
    }
  }

  /// 处理单个输入字符（来自软键盘）。
  void _handleLineChar(int ch) {
    switch (ch) {
      case 0x0d: // '\r' — 回车提交
        _submitLine();
        break;
      case 0x0a: // '\n' — 同上（某些键盘可能发 \n）
        _submitLine();
        break;
      case 0x08: // '\b' — Backspace (某些 IME 发)
      case 0x7f: // DEL — Backspace (xterm 默认)
        if (_input.isNotEmpty) {
          _input = _input.substring(0, _input.length - 1);
          _histPos = _history.length;
          _histStash = _input;
          _redrawPrompt();
        }
        break;
      case 0x03: // Ctrl-C — 在行编辑模式下清空当前行
        _input = '';
        _histPos = _history.length;
        _histStash = '';
        _redrawPrompt();
        break;
      case 0x04: // Ctrl-D — 空行时发 EOF，否则忽略
        if (_input.isEmpty) {
          _service.writeInput(Uint8List.fromList([0x04]));
        }
        break;
      default:
        if (ch >= 0x20 && ch < 0x7f) {
          // 可打印 ASCII
          _input += String.fromCharCode(ch);
          _histPos = _history.length;
          _histStash = _input;
          _redrawPrompt();
        }
        // 其他控制字符 / 高位 UTF-8（含中文、emoji 等）由 onOutput 的回调保证
        // 单次传入完整字符串，走 _handleLineInput 外层循环逐个字符处理。
        // 这里对 >= 0x80 的码点追加到 _input。
        if (ch >= 0x80) {
          _input += String.fromCharCode(ch);
          _histPos = _history.length;
          _histStash = _input;
          _redrawPrompt();
        }
        break;
    }
  }

  /// 处理扩展按键栏的特殊键（行编辑模式），不走 escape 序列生成/解析环路。
  void _handleLineKey(TerminalKey key, {bool ctrl = false, bool alt = false}) {
    switch (key) {
      case TerminalKey.arrowUp:
        _historyBack();
        break;
      case TerminalKey.arrowDown:
        _historyForward();
        break;
      case TerminalKey.enter:
        _submitLine();
        break;
      case TerminalKey.backspace:
        if (_input.isNotEmpty) {
          _input = _input.substring(0, _input.length - 1);
          _histPos = _history.length;
          _histStash = _input;
          _redrawPrompt();
        }
        break;
      case TerminalKey.escape:
        // ESC 清空当前行
        _input = '';
        _histPos = _history.length;
        _histStash = '';
        _redrawPrompt();
        break;
      case TerminalKey.tab:
        // TAB 在行编辑模式下插入空格（部分服有 Tab 补全的，用户可切原始终端模式）
        _input += '\t';
        _histPos = _history.length;
        _histStash = _input;
        _redrawPrompt();
        break;
      case TerminalKey.home:
        // 暂不支持光标定位，忽略
        break;
      case TerminalKey.end:
        break;
      default:
        // 其他键（PgUp/PgDn 等）忽略
        break;
    }
  }

  /// 历史命令上翻。
  void _historyBack() {
    if (_history.isEmpty || _histPos <= 0) return;
    if (_histPos == _history.length) {
      _histStash = _input; // 保存正在编辑的行
    }
    _histPos--;
    _input = _history[_histPos];
    _redrawPrompt();
  }

  /// 历史命令下翻。
  void _historyForward() {
    if (_histPos >= _history.length) return;
    _histPos++;
    _input = _histPos < _history.length ? _history[_histPos] : _histStash;
    _redrawPrompt();
  }

  /// 提交当前行到服务端：写入 PTY + 进历史。
  void _submitLine() {
    final line = _input.trim();
    // 先擦掉 prompt 行（终端上不再显示），让命令由 PTY 回显或服务端输出自然出现。
    _writeTerm('\r\x1b[K'); // 擦掉当前 prompt 行
    if (line.isNotEmpty) {
      // 去重：连续相同命令不重复入历史
      if (_history.isEmpty || _history.last != line) {
        _history.add(line);
        if (_history.length > _maxHistory) _history.removeAt(0);
      }
      // 也进日志缓冲（供复制 / 崩溃报告），与旧版 `> cmd` 格式一致
      _appendLogLine('> $line');
      // 写入 PTY：命令行编辑模式下 echo 已关闭，故不会有重复回显。
      _service.sendCommand(line);
    }
    _input = '';
    _histPos = _history.length;
    _histStash = '';
    // 等 PTY 回显（若有）或下一段输出到达后，由 _feedTerm 重绘 prompt。
    // 此处先不急着画，避免在回显到达前出现短暂的空白 prompt。
  }

  /// 重绘命令行提示符：擦掉当前行，画上 `> _input`。
  void _redrawPrompt() {
    // \r 回到行首，\x1b[K 擦到行尾，然后画 prompt
    _writeTerm('\r\x1b[K> $_input');
  }

  void clearLog() {
    _log.clear();
    _service.clearLog();
    // 清屏 + 清滚动回看 + 光标归位，让终端与日志缓冲同步清空。
    _writeTerm('\x1b[3J\x1b[2J\x1b[H');
    if (_lineMode) _redrawPrompt();
    notifyListeners();
  }

  /// 当前设备架构下可用的 JRE 标识（如 ['jre17','jre21','jre25']）。
  Future<List<String>> availableJreIds() => _service.availableJreIds();

  /// 当前设备架构下可用的 PHP 运行时标识（如 ['php8.2']）；不支持的架构返回空。
  Future<List<String>> availablePhpIds() => _service.availablePhpIds();

  void _onEvent(ServerEvent event) {
    switch (event) {
      case ServerTermEvent(:final bytes):
        // 原始终端字节：同步写入终端（不进解析），保证与后续 prompt 重绘顺序正确。
        _feedTerm(bytes);
      case ServerLogEvent(:final line):
        // 已去 ANSI 的纯文本行：进日志缓冲并解析，但不写终端
        //（终端内容已由对应的 term 字节呈现，避免重复）。
        _appendLogLine(line);
        _parsePlayerEvent(line);
        _handlePnxWizard(line);
        notifyListeners();
      case ServerStateEvent(
        :final status,
        :final instanceId,
        :final instanceName,
        :final exitCode,
      ):
        if (status != null) {
          // 界面重建后，从原生回放中恢复当前正在运行的实例。
          if (instanceId != null) _instanceId = instanceId;
          if (instanceName != null) _instanceName = instanceName;
          // 兼容模式下「启动中」直接当作「运行中」，跳过「启动中」标签；
          // 应用被回收后重连时的状态回放同样适用。
          final compat = _compatFor(_instanceId);
          // 进程存活，根据 status 字符串映射到对应状态。
          _status = switch (status) {
            'preparing' => ServerStatus.preparing,
            'starting' => compat ? ServerStatus.running : ServerStatus.starting,
            'running' => ServerStatus.running,
            _ => compat ? ServerStatus.running : ServerStatus.starting,
          };
          // 服务端进入运行态后触发 UPnP 端口映射和 FRP 隧道。
          if (_status == ServerStatus.running) {
            _cacheServerPort();
            if (!_upnpActive) _triggerUpnp();
            if (!_tunnelActive) _triggerTunnel();
          }
        } else {
          _status = ServerStatus.stopped;
          _lastExitCode = exitCode;
          _onlinePlayers.clear();
          _serverPort = null;
          if (_upnpActive) _stopUpnp();
          if (_tunnelActive && !_restartingTunnel) _stopTunnel();
          // exitCode 为空表示这是回放的“当前无运行”状态，并非真正退出，不打日志。
          if (exitCode != null) {
            _notice('[EdgeCube] 服务端已退出（退出码 $exitCode）');
            // 崩溃检测：退出码不为 0 且非用户主动停止/强制停止。
            if (exitCode != 0 && !_userStopping && !_userForceStopping) {
              _handleCrash(exitCode);
            }
          }
          _userStopping = false;
          _userForceStopping = false;
        }
        notifyListeners();
    }
  }

  /// 解析日志中的玩家加入/离开/list 响应，维护在线玩家集合。
  void _parsePlayerEvent(String line) {
    final joinMatch = _reJoin.firstMatch(line);
    if (joinMatch != null) {
      _onlinePlayers.add(joinMatch.group(1)!);
      return;
    }
    final leaveMatch = _reLeave.firstMatch(line);
    if (leaveMatch != null) {
      _onlinePlayers.remove(leaveMatch.group(1)!);
      return;
    }
    // 解析 list 命令响应：There are X of Y players online: name1, name2
    final listMatch = _reListResp.firstMatch(line);
    if (listMatch != null) {
      final names = listMatch.group(1)!.trim();
      if (names.isNotEmpty) {
        _onlinePlayers
          ..clear()
          ..addAll(
            names.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
          );
      } else {
        _onlinePlayers.clear();
      }
    }
  }

  /// PowerNukkitX 首次启动向导自动应答。
  ///
  /// PNX 首次运行时会弹出交互式向导：语言选择 → 许可证接受 → 跳过向导 → 启动。
  /// 检测到向导输出后自动发送默认响应，免去用户手动操作。
  void _handlePnxWizard(String line) {
    switch (_pnxWizardStep) {
      case 0:
        // 检测首次启动向导开始
        if (line.contains('First-time setup') ||
            line.contains('Setup Wizard') ||
            line.contains('Language Selection')) {
          _pnxWizardStep = 1;
          Future.delayed(const Duration(milliseconds: 500), () {
            if (_status != ServerStatus.stopped) {
              _service.sendCommand('chs');
            }
          });
        }
        break;
      case 1:
        // 许可证提示：PNX 输出 "你必须接受此许可证才能继续"
        if (line.contains('必须接受') || line.contains('接受此许可证')) {
          _pnxWizardStep = 2;
          Future.delayed(const Duration(milliseconds: 300), () {
            if (_status != ServerStatus.stopped) {
              _service.sendCommand('y');
            }
          });
        }
        break;
      case 2:
        // 跳过向导提示：PNX 输出 "你可以选择跳过设置向导"
        if (line.contains('跳过设置向导')) {
          _pnxWizardStep = 3;
          Future.delayed(const Duration(milliseconds: 300), () {
            if (_status != ServerStatus.stopped) {
              _service.sendCommand('y');
            }
          });
        }
        break;
      case 3:
        // 配置完成：PNX 输出 "你的 PowerNukkitX 服务器现已配置完成"
        if (line.contains('服务器现已配置完成') ||
            line.contains('server is now configured')) {
          _pnxWizardStep = 0;
          Future.delayed(const Duration(milliseconds: 300), () {
            if (_status != ServerStatus.stopped) {
              _service.sendCommand('y');
            }
          });
        }
        break;
    }
  }

  /// 指定实例是否启用兼容模式。优先用 [start] 缓存的同步值；回放路径下实例
  /// 与缓存不符时，触发异步解析补正，先返回当前最佳值。
  bool _compatFor(String? instanceId) {
    if (instanceId == null) return false;
    if (instanceId == _compatModeId) return _compatMode;
    _resolveCompatAsync(instanceId);
    return _compatMode;
  }

  /// 异步从实例配置解析兼容模式并补正状态（用于原生状态回放）。
  Future<void> _resolveCompatAsync(String instanceId) async {
    final resolver = compatModeResolver;
    if (resolver == null) return;
    final value = await resolver(instanceId);
    // 期间运行实例可能已切换，丢弃过期结果。
    if (_instanceId != instanceId) return;
    _compatModeId = instanceId;
    if (_compatMode == value) return;
    _compatMode = value;
    // 兼容模式下「启动中」应显示为「运行中」，解析完成后补正。
    if (value && _status == ServerStatus.starting) {
      _status = ServerStatus.running;
      if (!_upnpActive) _triggerUpnp();
      if (!_tunnelActive) _triggerTunnel();
    }
    notifyListeners();
  }

  /// 从配置文件读取并缓存服务端端口（服务端进入运行态时调用）。
  void _cacheServerPort() {
    readServerPort().then((port) {
      _serverPort = port;
      notifyListeners();
    });
  }

  /// 触发 UPnP 端口映射（服务端进入运行态时调用）。
  void _triggerUpnp() {
    final resolver = upnpEnabledResolver;
    if (resolver == null) return;
    resolver().then((enabled) {
      if (enabled) _startUpnp();
    });
  }

  /// 启动 UPnP 端口映射。
  void _startUpnp() {
    final dir = _workingDir;
    if (dir == null || _upnpActive) return;
    _upnpActive = true;

    // 并行加载：服务端端口、自定义外网端口、映射协议。
    final extResolver = upnpExternalPortResolver;
    final protoResolver = upnpProtocolResolver;
    final extFuture =
        extResolver != null ? extResolver() : Future<int?>.value(null);
    final protoFuture =
        protoResolver != null ? protoResolver() : Future.value('tcp');

    Future.wait([readServerPort(), extFuture, protoFuture]).then((results) {
      final internalPort = results[0] as int? ?? 25565;
      final externalPort = results[1] as int?;
      final protocol =
          (results[2] as String) == 'udp' ? PortType.udp : PortType.tcp;

      _upnp
          .openPort(
            internalPort: internalPort,
            externalPort: externalPort,
            protocol: protocol,
          )
          .then((port) async {
        if (port != null) {
          _notice('[EdgeCube] 路由器端口映射成功：$port');
          _upnpExternalIp = await _upnp.getExternalIp();
          notifyListeners();
        }
      });
    });
  }

  /// 解除 UPnP 端口映射。
  void _stopUpnp() {
    if (!_upnpActive) return;
    _upnpActive = false;
    _upnpExternalIp = null;
    _upnp.closePort().then((_) {
      // 静默处理，不影响主流程。
    });
  }

  /// 启动 FRP 隧道（服务端进入运行态时调用）。
  void _triggerTunnel() {
    final resolver = tunnelEnabledResolver;
    if (resolver == null) return;
    resolver().then((enabled) async {
      if (enabled) {
        final runtimeId = await NetworkStore.loadFrpcRuntimeId();
        // 检查 frpc 运行时是否已安装。
        final runtimes = await const RuntimeService().installedFrpcRuntimes();
        if (runtimes.isEmpty) {
          _notice('[EdgeCube] FRP 隧道未找到 frpc 运行时，跳过启动（请前往「运行环境」导入 frpc）');
          return;
        }
        _startTunnelWithConfig(null, runtimeId: runtimeId);
      }
    });
  }

  /// 使用指定配置启动 FRP 隧道（config 为 null 时从 config/network.json 读取）。
  void _startTunnelWithConfig(FrpcConfig? config, {String? runtimeId}) {
    final dir = _workingDir;
    if (dir == null || _tunnelActive) return;
    _tunnelActive = true;
    _tunnelRunning = false;
    _userStoppingTunnel = false;
    _tunnelCrashed = false; // 重新启动，清除上次的异常退出标记
    _tunnelLog.clear(); // 清空上次会话日志，避免崩溃报告混入历史
    _tunnel.clearLog(); // 同步清空原生侧与 Dart 静态日志缓存
    _doStartTunnel(config, dir, runtimeId: runtimeId);
  }

  Future<void> _doStartTunnel(
    FrpcConfig? config,
    String dir, {
    String? runtimeId,
  }) async {
    try {
      // 优先处理「直接编辑配置文件」模式：使用用户编辑的原始 TOML，
      // 不再注入 localPort（由用户在配置文件中自行维护）。
      final useCustom = await NetworkStore.loadUseCustomFrpc();
      if (config == null && useCustom) {
        final file = await NetworkStore.customFrpcFile();
        if (await file.exists()) {
          final raw = await file.readAsString();
          if (raw.trim().isEmpty) {
            _notice('[EdgeCube] 自定义 frpc.toml 为空，跳过启动');
            _tunnelActive = false;
            return;
          }
          if (_status != ServerStatus.running) {
            _tunnelActive = false;
            return;
          }
          final path = await _tunnel.writeRawConfig(raw);
          await _tunnel.start(
            configPath: path,
            name: 'frpc',
            runtimeId: runtimeId,
          );
          _activeFrpcConfig = null;
          _notice('[EdgeCube] FRP 隧道正在启动…（自定义配置）');
          notifyListeners();
          return;
        }
      }

      FrpcConfig finalConfig;
      if (config != null) {
        finalConfig = config;
      } else {
        // 从 config/network.json 读取（服务器启动时的路径）。
        final saved = await NetworkStore.loadFrpc();
        if (saved == null) {
          _notice('[EdgeCube] FRP 隧道未配置，跳过启动');
          _tunnelActive = false;
          return;
        }
        if (saved.serverAddr.isEmpty) {
          _notice('[EdgeCube] FRP 服务器地址未填写，跳过启动');
          _tunnelActive = false;
          return;
        }
        finalConfig = saved;
      }
      // 注入实际 localPort：优先 server.properties，回退 pnx.yml。
      int localPort = finalConfig.localPort;
      final propsFile = File(p.join(dir, 'server.properties'));
      if (await propsFile.exists()) {
        final props = ServerProperties.parse(await propsFile.readAsString());
        localPort = props.getInt('server-port') ?? 25565;
      } else {
        final pnxFile = File(p.join(dir, 'pnx.yml'));
        if (await pnxFile.exists()) {
          final pnx = PnxProperties.parse(await pnxFile.readAsString());
          localPort = pnx.getPort();
        }
      }
      finalConfig = finalConfig.copyWith(localPort: localPort);
      if (_status != ServerStatus.running) {
        _tunnelActive = false;
        return;
      }
      final path = await _tunnel.writeConfig(finalConfig);
      await _tunnel.start(
        configPath: path,
        name: finalConfig.proxyName,
        runtimeId: runtimeId,
      );
      _activeFrpcConfig = finalConfig;
      _notice('[EdgeCube] FRP 隧道正在启动…（本地端口 $localPort）');
      notifyListeners();
    } catch (e) {
      _notice('[EdgeCube] FRP 隧道启动失败：$e');
      _tunnelActive = false;
    }
  }

  /// 停止 FRP 隧道。
  void _stopTunnel() {
    if (!_tunnelActive) return;
    _tunnelActive = false;
    _tunnelRunning = false;
    _userStoppingTunnel = true; // 标记为主动停止，避免退出事件误报"异常退出"
    _activeFrpcConfig = null;
    _tunnel.stop().then((_) {
      // 静默处理，不影响主流程。
    });
  }

  /// frpc 隧道事件回调。
  ///
  /// 监听原生侧 [TunnelService.events()] 流：
  ///  - 收到 `STATUS_RUNNING` 时才视为"真正成功"，发出成功提示（避免在
  ///    [_doStartTunnel] 中进程刚拉起就误报成功，而 frpc 因 token 错误、
  ///    端口冲突等原因随后立刻退出）。
  ///  - 进程退出（status == null 且 exitCode != null）时，若非用户主动停止
  ///    且退出码非 0，提示"异常退出"并触发 [onTunnelCrashExit] 弹出崩溃报告
  ///    （与服务端崩溃同款，支持导出/上传日志）；用户主动停止或正常退出
  ///    则静默。同时复位 `_tunnelActive`/`_tunnelRunning`，让 UI 可再次发起启动。
  ///  - status == null 且 exitCode == null 是 app 启动时的状态回放
  ///    （frpc 未运行），完全静默。
  ///  - 日志事件（[TunnelLogEvent]）追加到 [_tunnelLog] 供崩溃报告导出；
  ///    端口映射页另订阅同一流做实时显示，此处不写入服务端终端，避免噪声。
  void _onTunnelEvent(TunnelEvent event) {
    if (event is TunnelLogEvent) {
      _appendTunnelLog(event.line);
      return;
    }
    if (event is! TunnelStateEvent) return;
    final status = event.status;
    if (status == 'running') {
      if (_tunnelRunning) return; // 去重，避免重复提示
      _tunnelRunning = true;
      _userStoppingTunnel = false; // 已成功连接，清除可能残留的停止标记
      _tunnelCrashed = false; // 连接成功，清除可能的异常退出标记
      _notice('[EdgeCube] FRP 隧道已连接到服务器');
      notifyListeners();
      return;
    }
    if (status != null) return; // starting / preparing 等中间状态不处理
    // status == null
    final code = event.exitCode;
    if (code == null) return; // 状态回放（未运行），非真正退出，静默
    // 真正的进程退出
    final userStop = _userStoppingTunnel || _restartingTunnel;
    final wasActive = _tunnelActive;
    _userStoppingTunnel = false;
    _tunnelActive = false;
    _tunnelRunning = false;
    _activeFrpcConfig = null;
    if (userStop || !wasActive) {
      _tunnelCrashed = false; // 主动停止或非本控制器发起，清除异常标记
      return;
    }
    if (code != 0) {
      _tunnelCrashed = true; // 标记异常退出，UI 显示"出错"
      _notice('[EdgeCube] FRP 隧道异常退出（退出码 $code），请检查配置或网络');
      notifyListeners();
      // 触发崩溃报告弹窗（与服务端崩溃同款），附上 frpc 日志快照供导出/上传。
      final callback = onTunnelCrashExit;
      if (callback != null) {
        callback(
          CrashData(
            exitCode: code,
            logLines: List<String>.from(_tunnelLog),
            envType: '',
            envRuntimeId: '',
            kind: 'tunnel',
          ),
        );
      }
    } else {
      _notice('[EdgeCube] FRP 隧道已退出');
      notifyListeners();
    }
  }

  /// 追加一行 frpc 日志到 [_tunnelLog]，超出上限丢弃最旧。
  void _appendTunnelLog(String line) {
    _tunnelLog.add(line);
    if (_tunnelLog.length > _maxLogLines) {
      _tunnelLog.removeRange(0, _tunnelLog.length - _maxLogLines);
    }
  }

  // —— 即时生效公共接口 ——

  /// 立即启用 UPnP（用户在 UI 中打开开关时调用）。
  void enableUpnpNow() {
    if (_upnpActive || _status != ServerStatus.running) return;
    _startUpnp();
  }

  /// 立即停用 UPnP（用户在 UI 中关闭开关时调用）。
  void disableUpnpNow() {
    if (!_upnpActive) return;
    _stopUpnp();
  }

  /// 立即启用 FRP 隧道（用户在 UI 中打开开关时调用）。
  /// [config] 可选，传入当前 UI 配置；为 null 时从 config/network.json 读取。
  void enableTunnelNow([FrpcConfig? config, String? runtimeId]) {
    if (_tunnelActive || _status != ServerStatus.running) return;
    _startTunnelWithConfig(config, runtimeId: runtimeId);
  }

  /// 立即停用 FRP 隧道（用户在 UI 中关闭开关时调用）。
  void disableTunnelNow() {
    if (!_tunnelActive) return;
    _stopTunnel();
  }

  /// 以指定配置重启 FRP 隧道（用户在运行中修改配置后调用）。
  Future<void> applyTunnelConfig(FrpcConfig config, [String? runtimeId]) async {
    if (!_tunnelActive || _status != ServerStatus.running) return;
    _restartingTunnel = true;
    await _tunnel.stop();
    await Future.delayed(const Duration(milliseconds: 300));
    if (_status == ServerStatus.running && _workingDir != null) {
      _doStartTunnel(config, _workingDir!, runtimeId: runtimeId);
    }
    _restartingTunnel = false;
  }

  /// 重启 FRP 隧道以应用最新配置（自定义模式读取 `config/frpc.toml`，
  /// 表单模式读取 `config/network.json`）。用户在运行中编辑自定义配置或切换
  /// 模式后调用。
  Future<void> restartTunnel() async {
    if (!_tunnelActive || _status != ServerStatus.running) return;
    _restartingTunnel = true;
    await _tunnel.stop();
    await Future.delayed(const Duration(milliseconds: 300));
    if (_status == ServerStatus.running && _workingDir != null) {
      final runtimeId = await NetworkStore.loadFrpcRuntimeId();
      _doStartTunnel(null, _workingDir!, runtimeId: runtimeId);
    }
    _restartingTunnel = false;
  }

  /// 追加一条纯文本日志行到缓冲（用于复制日志 / 崩溃报告 / 玩家解析），不写终端。
  void _appendLogLine(String line) {
    _log.add(line);
    if (_log.length > _maxLogLines) {
      _log.removeRange(0, _log.length - _maxLogLines);
    }
  }

  /// EdgeCube 自身的提示：同步写入终端（保证与 PTY 输出有序），同时进日志缓冲。
  void _notice(String msg) {
    _writeTerm('$msg\r\n');
    _appendLogLine(msg);
    if (_lineMode) _redrawPrompt();
  }

  /// 服务端意外退出时生成崩溃数据并触发回调。
  void _handleCrash(int exitCode) {
    final callback = onCrashExit;
    if (callback == null) return;
    // 复制当前日志快照，避免后续新启动覆盖。
    final snapshot = List<String>.from(_log);
    callback(
      CrashData(
        exitCode: exitCode,
        logLines: snapshot,
        envType: _runtimeType,
        envRuntimeId: _runtimeId,
      ),
    );
  }

  @override
  void dispose() {
    _sub.cancel();
    _tunnelSub.cancel();
    super.dispose();
  }
}

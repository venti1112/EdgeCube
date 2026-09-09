import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xterm2/xterm.dart';

import '../server/server_service.dart';
import '../server/terminal_client.dart';
import '../settings/appearance.dart';
import '../widgets/terminal_keys_bar.dart';
import '../widgets/terminal_zoom.dart';
import 'api_error.dart';
import 'current_instance.dart';

/// 控制台终端页(对齐 V1 控制台):全交互伪终端(xterm2)直连 daemon
/// /ws/terminal 会话。打开会话即自动启动实例(守护进程模型,退出页面
/// 进程继续运行);支持直接打字输入、历史回放、窗口尺寸同步、双指捏合缩放
/// 与 Termux 式扩展按键栏(ESC/CTRL/ALT/TAB/方向键等)。
class ConsolePage extends ConsumerWidget {
  const ConsolePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instance = ref.watch(currentInstanceProvider);
    if (instance == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('控制台'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        body: const Center(
          child: Text('请先在「服务器」页选择实例'),
        ),
      );
    }
    // key 绑定实例 id:切实例自动重建并重连
    return _InstanceTerminal(
      key: ValueKey(instance.id),
      instanceId: instance.id,
      instanceName: instance.name,
    );
  }
}

class _InstanceTerminal extends ConsumerStatefulWidget {
  const _InstanceTerminal({
    super.key,
    required this.instanceId,
    required this.instanceName,
  });

  final String instanceId;
  final String instanceName;

  @override
  ConsumerState<_InstanceTerminal> createState() => _InstanceTerminalState();
}

class _InstanceTerminalState extends ConsumerState<_InstanceTerminal>
    implements TerminalKeysController {
  /// 控制台终端字号(独立记忆,持久化于本地存储)。
  static const _fontSizeKey = 'consoleFontSize';

  late final Terminal _terminal;
  TerminalClient? _client;

  String _status = '连接中';
  String? _error;
  bool _connecting = true;

  /// 导出日志进行中(按钮转圈防连点)。
  bool _exporting = false;

  /// 当前连接服务器的 API 客户端(与 REST 调用同源,已注入 Bearer token)。
  EdgecubeApiClient? get _apiClient => ref.read(edgecubeClientProvider);

  /// 实例未运行时的状态轮询:检测到被其他前端启动后自动重连接入新会话,
  /// 保证多端同时开着控制台时,一端启动、另一端也能显示运行中与新日志。
  Timer? _statusTimer;
  static const _pollInterval = Duration(seconds: 2);

  /// 终端字号(控制台独立记忆)。
  double _fontSize = kDefaultTerminalFontSize;

  /// 扩展按键栏的「粘滞修饰键」:点亮后只对下一次输入生效一次,随即自动复位
  /// (与 Termux 的 CTRL/ALT 行为一致),用于变换软键盘按键/特殊键。
  bool _ctrlDown = false;
  bool _altDown = false;

  @override
  bool get ctrlDown => _ctrlDown;
  @override
  bool get altDown => _altDown;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(
      maxLines: 5000,
      // 按键输出 → daemon(先应用粘滞 Ctrl/Alt,再以原始字节写入)
      onOutput: _onTerminalOutput,
      // 尺寸同步(autoResize 由 TerminalView 触发)
      onResize: (width, height, _, _) => _client?.resize(width, height),
    );
    _connect();
    _loadFontSize();
  }

  @override
  void dispose() {
    final client = _client;
    _client = null;
    // 关闭会话与连接(实例进程不受影响)
    client?.close();
    super.dispose();
  }

  /// 当前连接服务器的 host/port/token(与 REST 客户端同源)。
  (String, int, String)? _endpoint() {
    final session = ref.read(sessionProvider);
    final serverId = ref.read(currentServerIdProvider);
    if (session == null || serverId == null || session.serverId != serverId) {
      return null;
    }
    final entry = ref
        .read(serverListProvider)
        .where((e) => e.id == serverId)
        .firstOrNull;
    if (entry == null) return null;
    return (entry.host, entry.port, session.token);
  }

  Future<void> _connect() async {
    final endpoint = _endpoint();
    if (endpoint == null) {
      setState(() {
        _connecting = false;
        _error = '未连接到服务器';
      });
      return;
    }
    final (host, port, token) = endpoint;
    setState(() {
      _connecting = true;
      _error = null;
      _status = '连接中';
    });

    final client = TerminalClient(
      host: host,
      port: port,
      token: token,
      onData: (text) => _terminal.write(text),
      onState: (status, exitCode) {
        if (!mounted) return;
        setState(() => _status = status);
      },
      onWatcherCount: (_) {},
      onDone: (reason) {
        if (!mounted || _client == null) return;
        setState(() {
          _connecting = false;
          _error = reason ?? '连接已断开';
        });
      },
    );

    try {
      await client.connect();
      _client = client;
      // 清空旧内容再回放:重连时终端可能残留上屏历史,避免与 replay 重复
      _terminal.clear();
      final opened = await client.open(
        widget.instanceId,
        cols: _terminal.viewWidth,
        rows: _terminal.viewHeight,
      );
      if (!mounted) return;
      // open 返回 status:实例已停止时为 'stopped'(后端不再自动启动)
      setState(() {
        _connecting = false;
        _status = (opened['status'] as String?) ?? '已连接';
      });
      // 未运行:等被其他前端启动;已运行/启动中:停止轮询
      if (_status == 'stopped') {
        _startWatching();
      } else {
        _stopWatching();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = '$e';
      });
    }
  }

  Future<void> _reconnect() async {
    await _client?.close();
    _client = null;
    _connect();
  }

  // ────────────────────────────────────────────────
  // 未运行实例的状态轮询(多端协作:他端启动后自动接入)
  // ────────────────────────────────────────────────

  /// 开启(幂等)状态轮询:实例仍在 stopped 时周期性查询 REST 状态。
  void _startWatching() {
    if (_statusTimer != null) return;
    _statusTimer = Timer.periodic(_pollInterval, (_) => _pollInstanceStatus());
  }

  void _stopWatching() {
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  /// 轮询实例状态;发现 running(他端启动)即重连续上新会话。
  Future<void> _pollInstanceStatus() async {
    final client = _apiClient;
    if (client == null || !mounted || _statusTimer == null) return;
    try {
      final detail = (await client
              .getInstancesApi()
              .getInstance(instanceId: widget.instanceId))
          .data;
      if (detail == null || !mounted || _statusTimer == null) return;
      if (detail.status.status == InstanceStatus.running) {
        _stopWatching();
        await _reconnect();
      }
    } catch (_) {
      // 网络瞬断等:保持轮询,下一周期再试
    }
  }

  // ————————————————————————————————————————————————
  // 日志复制 / 导出(对齐 V1 控制台)
  // ————————————————————————————————————————————————

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 拉取实例完整落盘日志(经 REST /instances/{id}/outputlog)。
  Future<String?> _fetchLog() async {
    final client = _apiClient;
    if (client == null) return null;
    final resp = await client
        .getInstancesApi()
        .getInstanceOutputLog(instanceId: widget.instanceId);
    return resp.data;
  }

  /// 复制日志到剪贴板。
  Future<void> _copyLog() async {
    try {
      final content = await _fetchLog();
      if (!mounted) return;
      if (content == null || content.isEmpty) {
        _snack('暂无日志');
        return;
      }
      await Clipboard.setData(ClipboardData(text: content));
      if (!mounted) return;
      _snack('日志已复制');
    } catch (e) {
      if (!mounted) return;
      _snack(apiErrorMessage(e));
    }
  }

  /// 导出日志:拉全文写入临时文件,再调系统分享。
  Future<void> _exportLog() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final content = await _fetchLog();
      if (content == null) throw Exception('未连接到服务器');
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/edgecube_log_$ts.log');
      await file.writeAsString(content);
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (e) {
      if (!mounted) return;
      _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ————————————————————————————————————————————————
  // 终端输出与扩展按键栏(粘滞修饰键)
  // ————————————————————————————————————————————————

  /// 终端输出入口(软键盘打字、[sendKey]、[sendText] 都汇聚于此):
  /// 应用粘滞的 Ctrl/Alt 变换后,以原始字节写入 PTY,随即复位修饰键。
  void _onTerminalOutput(String data) {
    final modified = (_ctrlDown || _altDown) ? _modifyChar(data) : null;
    final bytes = modified ?? utf8.encode(data);
    _client?.writeBytes(bytes);
    _clearModifiers();
  }

  /// 对单个字符应用粘滞的 Ctrl/Alt:Ctrl 把 a–z / @[\]^_ 映射到 0x00–0x1f,
  /// Alt 加 ESC 前缀。返回要写入的字节;不适用(多字符或无映射)时返回 null。
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

  /// 复位粘滞修饰键(每次输入消费后调用)。
  void _clearModifiers() {
    if (!_ctrlDown && !_altDown) return;
    setState(() {
      _ctrlDown = false;
      _altDown = false;
    });
  }

  @override
  void toggleCtrl() => setState(() => _ctrlDown = !_ctrlDown);

  @override
  void toggleAlt() => setState(() => _altDown = !_altDown);

  /// 发送一个特殊键(ESC / TAB / 方向键 / HOME / END / PgUp / PgDn 等):
  /// 经 xterm 的 inputHandler 生成转义序列并写入 PTY。
  @override
  void sendKey(TerminalKey key) {
    final ctrl = _ctrlDown;
    final alt = _altDown;
    _clearModifiers();
    _terminal.keyInput(key, ctrl: ctrl, alt: alt);
  }

  /// 发送一段字面文本(扩展按键栏的 `-` `/` 等)。
  @override
  void sendText(String text) => _onTerminalOutput(text);

  // ————————————————————————————————————————————————
  // 终端字号(本地持久化)
  // ————————————————————————————————————————————————

  Future<void> _loadFontSize() async {
    final raw = await ref.read(storageProvider).read(_fontSizeKey);
    if (!mounted) return;
    final parsed = raw == null ? null : double.tryParse(raw);
    final size =
        (parsed ?? kDefaultTerminalFontSize).clamp(
          kMinTerminalFontSize,
          kMaxTerminalFontSize,
        );
    setState(() => _fontSize = size);
  }

  void _setFontSize(double size) {
    if (size == _fontSize) return;
    setState(() => _fontSize = size);
  }

  Future<void> _saveFontSize() =>
      ref.read(storageProvider).write(_fontSizeKey, _fontSize.toString());

  @override
  Widget build(BuildContext context) {
    // 应用主题由 material_ui 的 MaterialApp 通过其自身继承链注入;
    // 本页组件来自 flutter/material(含 xterm2 终端),flutter 的 Theme.of
    // 取不到该主题,会回落浅色默认主题导致深色模式失效。故按外层 material_ui
    // 主题的亮度派生一个 flutter Theme 包裹整页(对齐 text_editor_page)。
    final muiTheme = mui.Theme.of(context);
    final isDark = muiTheme.brightness == Brightness.dark;
    final flutterData = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: muiTheme.colorScheme.primary,
        brightness: isDark ? Brightness.dark : Brightness.light,
      ),
    );

    return Theme(
      data: flutterData,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  widget.instanceName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _statusChip(Theme.of(context).colorScheme, _status),
            ],
          ),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          actions: [
            TerminalZoomButton(
              fontSize: _fontSize,
              onChanged: (size) {
                _setFontSize(size);
                _saveFontSize();
              },
            ),
            IconButton(
              onPressed: _copyLog,
              icon: const Icon(Icons.copy),
              tooltip: '复制日志',
            ),
            IconButton(
              onPressed: _exporting ? null : _exportLog,
              icon: _exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              tooltip: '导出日志',
            ),
            IconButton(
              onPressed: _reconnect,
              icon: const Icon(Icons.refresh),
              tooltip: '重连',
            ),
          ],
        ),
        body: _error != null && _client == null
            ? _errorView()
            : _connecting
                ? const Center(child: CircularProgressIndicator())
                : _terminalView(),
      ),
    );
  }

  /// 终端区域 + 紧贴下方的扩展按键栏(Termux 式布局)。
  Widget _terminalView() {
    return Column(
      children: [
        Expanded(
          child: ZoomableTerminal(
            terminal: _terminal,
            fontSize: _fontSize,
            onFontSizeChanged: _setFontSize,
            onFontSizeChangeEnd: _saveFontSize,
          ),
        ),
        // RepaintBoundary 让按键栏拥有独立合成层,与 TerminalView 同步清除,
        // 避免 IndexedStack 切换时按键栏比终端慢一帧消失的视觉残留。
        RepaintBoundary(child: TerminalKeysBar(this)),
      ],
    );
  }

  Widget _errorView() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.terminal, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(_error ?? '连接失败', style: TextStyle(color: cs.error)),
          const SizedBox(height: 8),
          FilledButton.tonal(onPressed: _reconnect, child: const Text('重连')),
        ],
      ),
    );
  }

  Widget _statusChip(ColorScheme cs, String status) {
    final (label, color) = switch (status) {
      'running' => ('运行中', Colors.green),
      'starting' || 'stopping' => (instanceStatusLabelSafe(status), Colors.orange),
      'stopped' => ('已停止', cs.outline),
      'busy' => ('忙碌', Colors.orange),
      _ => (_status, cs.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: color)),
    );
  }
}

/// 状态文案(本地映射,避免与 REST 状态标签耦合)。
String instanceStatusLabelSafe(String status) => switch (status) {
      'starting' => '启动中',
      'stopping' => '停止中',
      _ => status,
    };

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import 'shell_service.dart';

/// 交互式 shell 终端的全局控制器。
///
/// 持有 xterm [Terminal]（故切页/重建不丢内容），把按键写入原生 PTY、把 PTY 输出
/// 喂给终端渲染。与 [ServerController] 不同，shell 在真实 TTY 上自带行编辑/历史/补全，
/// 因此这里**只有原始模式**：不做本地行编辑，仅转发字节并应用粘滞 CTRL/ALT 修饰键。
class ShellController extends ChangeNotifier {
  ShellController({ShellService? service})
    : _service = service ?? ShellService() {
    _sub = _service.events().listen(_onEvent);
    terminal.onOutput = _onTerminalOutput;
    terminal.onResize = _onTerminalResize;
  }

  final ShellService _service;
  late final StreamSubscription<ShellEvent> _sub;

  static const int _maxLines = 5000;

  /// 交互式终端（xterm）。
  // reflowEnabled: false —— 见 server_controller.dart 中同名字段注释。
  // xterm 4.0.0 的 reflow 在 resize 时会保留旧单元格，导致缩放后内容行数翻倍。
  final Terminal terminal = Terminal(maxLines: _maxLines, reflowEnabled: false);

  bool _running = false;
  String? _label;
  int? _lastExitCode;

  bool get isRunning => _running;

  /// 当前生效的 shell 名称（如 "system sh"）。
  String? get shellLabel => _label;
  int? get lastExitCode => _lastExitCode;

  // —— 粘滞修饰键（扩展按键栏的 CTRL/ALT，点亮后对下一次输入生效一次）——
  bool _ctrlDown = false;
  bool _altDown = false;
  bool get ctrlDown => _ctrlDown;
  bool get altDown => _altDown;

  /// 初始化：同步当前运行状态（进程在原生侧为单例，跨页面/重建存活）。
  Future<void> init() async {
    _running = await _service.isRunning();
    notifyListeners();
  }

  /// 启动交互 shell（已在运行则忽略）。[cwd] 为初始工作目录。
  Future<void> start({String? cwd}) async {
    if (_running) return;
    try {
      await _service.start(cwd: cwd);
    } catch (e) {
      _writeTerm('\r\n[EdgeCube] 启动 shell 失败：$e\r\n');
    }
  }

  /// 优雅退出（发送 exit）。
  Future<void> stop() => _service.stop();

  /// 强制结束 shell 进程。
  Future<void> forceStop() => _service.forceStop();

  /// 重启：强制结束当前 shell 后重新启动。
  Future<void> restart({String? cwd}) async {
    if (_running) {
      await _service.forceStop();
      // 等待退出事件把状态翻回未运行，避免 start 因仍在运行而被忽略。
      for (var i = 0; i < 20 && _running; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    await start(cwd: cwd);
  }

  /// 清空终端画面与原生缓冲。
  void clear() {
    _service.clearLog();
    // 清屏 + 清滚动回看 + 光标归位。
    _writeTerm('\x1b[3J\x1b[2J\x1b[H');
    notifyListeners();
  }

  // ——————————————————————————————————————————————————————————
  // 输入：原始模式逐键直达 PTY（应用粘滞 CTRL/ALT）
  // ——————————————————————————————————————————————————————————

  void _onTerminalOutput(String data) {
    final modified = (_ctrlDown || _altDown) ? _modifyChar(data) : null;
    final bytes = modified ?? utf8.encode(data);
    _service.writeInput(Uint8List.fromList(bytes));
    _clearModifiers();
  }

  /// 对单个字符应用粘滞 Ctrl/Alt：Ctrl 把 a–z / @[\]^_ 映射到 0x00–0x1f，Alt 加 ESC 前缀。
  List<int>? _modifyChar(String data) {
    if (data.length != 1) return null;
    var cc = data.codeUnitAt(0);
    if (_ctrlDown) {
      if (cc >= 0x61 && cc <= 0x7a) cc -= 0x20;
      if (cc >= 0x40 && cc <= 0x5f) {
        final ctrlByte = cc & 0x1f;
        return _altDown ? [0x1b, ctrlByte] : [ctrlByte];
      }
    }
    if (_altDown) return [0x1b, ...utf8.encode(data)];
    return null;
  }

  void _clearModifiers() {
    if (!_ctrlDown && !_altDown) return;
    _ctrlDown = false;
    _altDown = false;
    notifyListeners();
  }

  void toggleCtrl() {
    _ctrlDown = !_ctrlDown;
    notifyListeners();
  }

  void toggleAlt() {
    _altDown = !_altDown;
    notifyListeners();
  }

  /// 发送特殊键（ESC / TAB / 方向键 / HOME / END / PgUp / PgDn 等）。
  void sendKey(TerminalKey key) {
    final ctrl = _ctrlDown;
    final alt = _altDown;
    _clearModifiers();
    terminal.keyInput(key, ctrl: ctrl, alt: alt);
  }

  /// 发送一段字面文本（扩展按键栏的 `-` `/` 等）。
  void sendText(String text) => _onTerminalOutput(text);

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

  void _writeTerm(String s) {
    if (s.isNotEmpty) terminal.write(s);
  }

  void _onEvent(ShellEvent event) {
    switch (event) {
      case ShellTermEvent(:final bytes):
        final str = utf8.decode(bytes, allowMalformed: true);
        if (str.isNotEmpty) terminal.write(str);
      case ShellStateEvent(:final status, :final label, :final exitCode):
        _running = status != null;
        if (exitCode != null) _lastExitCode = exitCode;
        _label = status != null ? (label ?? _label) : null;
        notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

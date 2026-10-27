import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xterm2/xterm.dart' as xterm;

import '../connection/settings.dart';
import '../files/dialogs.dart' show showErrorDialog;
import '../settings/appearance.dart';
import 'pty_client.dart';
import 'pty_transport.dart';
import 'terminal_keys_bar.dart';

/// 终端配色。
///
/// 用 xterm2 自带的 `defaultTheme`，不自造 palette —— 那套色值是标准 xterm 深色，
/// 服务端输出就是按它调的。终端固定深色（不跟随 App 主题）：浅底上白字/暗字
/// 会看不清。
const _terminalTheme = xterm.TerminalThemes.defaultTheme;

/// 默认字号。
const double _kDefaultFontSize = 13;
const List<double> _kFontSizes = [11, 13, 15, 17, 20];

/// 终端默认字体：与 xterm2 `TerminalStyle.fontFamily` 的默认值一致。
///
/// 用户在设置里没指定字体时就用它 —— 别改成 null：xterm2 给这个默认值配了一份
/// 覆盖 CJK / Emoji 的 fallback 名单，直接传别的名字会把那份名单一起换掉。
const String _kDefaultConsoleFont = 'monospace';

/// 清屏 + 清回滚缓冲 + 光标归位，跟 `pty-terminal-demo` 收到历史前发的序列一致。
const String _kClearSequence = '\x1b[2J\x1b[3J\x1b[H';

/// 一块 PTY 终端：连接、渲染、按键栏、字号、清屏、重连都在这里。
///
/// 实例控制台（`/pty/{id}`）与主机终端（`/shell`）共用一个协议，所以页面只给
/// 标题 / 副标题 / 地址，其余行为完全一致 —— 差别只在副标题文案与
/// 有没有「重启」按钮（[onRestart]）。
///
/// * 连上先收**历史快照**（daemon 侧保留最近 1 MiB），切页回来、App 重启后
///   连上都能看到之前的输出；
/// * 断开只是退订，**进程照旧跑**；
/// * 进程退出会推 `exit` 控制帧，副标题随之变化。
class TerminalPane extends ConsumerStatefulWidget {
  const TerminalPane({
    super.key,
    required this.keyPrefix,
    required this.title,
    required this.subtitle,
    required this.url,
    this.emptyState,
    this.onRestart,
  });

  /// 控件 Key 的前缀（`<prefix>_subtitle` / `_clear` / `_reconnect` …）。
  ///
  /// 两个页面都用这个组件，Key 不分开的话测试与调试时找不准是哪一块。
  final String keyPrefix;

  final String title;

  /// 副标题：拿当前 PTY 状态拼一行（连接态 / 进程阶段 / 退出码）。
  final String Function(PtyStatus status) subtitle;

  /// 要连的流地址；`null` = 没有可连的目标（显示 [emptyState]）。
  final Uri? url;

  final Widget? emptyState;

  /// 非 `null` 时顶栏多一个「重启终端」：点了先执行它，再重连。
  ///
  /// 主机终端用它调 `shell.restart`（杀掉当前 shell 并重开）；控制台用不上。
  final Future<void> Function()? onRestart;

  @override
  ConsumerState<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends ConsumerState<TerminalPane> {
  late final xterm.Terminal _terminal;
  late final TerminalKeysController _keys;
  PtyClient? _client;
  StreamSubscription<String>? _output;
  StreamSubscription<PtyStatus>? _status;
  StreamSubscription<void>? _historyBegin;
  PtyStatus _ptyStatus = const PtyStatus.connecting();
  double _fontSize = _kDefaultFontSize;

  /// 当前连着的地址；换地址（换实例 / 换页面目标）时重连。
  Uri? _attachedUrl;

  @override
  void initState() {
    super.initState();
    _terminal = xterm.Terminal(maxLines: 10000);
    _keys = TerminalKeysController(
      _terminal,
      write: (data) => _client?.write(data),
    );
    // 用户敲的键 → PTY。统一走按键栏的控制器，粘滞的 CTRL / ALT 才管得着
    // 软键盘敲进来的字符（见 `TerminalKeysController`）。
    _terminal.onOutput = _keys.sendText;
    // 终端尺寸变化 → 通知 daemon，服务端才知道该按多宽换行
    _terminal.onResize = (width, height, _, _) =>
        _client?.resize(width, height);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_attach());
    });
  }

  @override
  void didUpdateWidget(TerminalPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      unawaited(_attach());
    }
  }

  @override
  void dispose() {
    _output?.cancel();
    _status?.cancel();
    _historyBegin?.cancel();
    _client?.close();
    _keys.dispose();
    super.dispose();
  }

  /// 连上（或重连）[TerminalPane.url]。
  Future<void> _attach() async {
    final url = widget.url;
    if (url == null || !ref.read(connectionSettingsProvider).isConfigured) {
      await _detach();
      return;
    }
    if (_attachedUrl == url && _client?.isConnected == true) return;

    await _detach();
    _attachedUrl = url;
    final client = PtyClient(
      url,
      transport: ref.read(ptyTransportFactoryProvider),
    );
    _client = client;
    _output = client.output.listen(_terminal.write);
    _historyBegin = client.historyBegin.listen((_) {
      // daemon 要重放历史了：先清屏，免得来回切页把历史叠两层。
      // 只能挂在 `history_begin` 上 —— 挂在 `history_end` 上等于把刚重放完的
      // 历史又擦掉一遍，屏幕上就什么都剩不下了。
      _terminal.write(_kClearSequence);
    });
    _status = client.status.listen((status) {
      if (mounted) setState(() => _ptyStatus = status);
    });
    client.connect();
    // 终端通常在连接**建成之前**就量好了尺寸，那一次 onResize 因为
    // `_client` 还是 null 被丢掉了。这里把当前尺寸补推给客户端：
    // 服务端要按它换行、也据此给进程发 SIGWINCH。
    client.resize(_terminal.viewWidth, _terminal.viewHeight);
  }

  Future<void> _detach() async {
    final output = _output;
    final status = _status;
    final historyBegin = _historyBegin;
    _output = null;
    _status = null;
    _historyBegin = null;

    // **不 await** cancel / close：订阅取消与关连接本身是同步生效的，
    // 返回的 Future 只是「清理完成」的信号 —— 而流已经关闭或没有监听者时，
    // 这个信号可能永远不来（`PtyClient.close` 里踩过同一个坑）。
    // 等它会把重连卡死在 detach 里，页面再也连不上新的流。
    unawaited(output?.cancel());
    unawaited(status?.cancel());
    unawaited(historyBegin?.cancel());
    final client = _client;
    _client = null;
    if (client != null) unawaited(client.close());

    _attachedUrl = null;
  }

  Future<void> _reconnect() async {
    _attachedUrl = null;
    await _attach();
  }

  /// 重启终端：交给页面把进程换掉（主机终端调 `shell.restart`），再重连。
  Future<void> _restart() async {
    final restart = widget.onRestart;
    if (restart == null) return;
    try {
      await restart();
    } catch (error) {
      if (!mounted) return;
      await showErrorDialog(context, '重启终端失败：$error');
      return;
    }
    if (!mounted) return;
    await _reconnect();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final consoleFont = ref.watch(consoleFontFamilyProvider);
    final showKeys = ref.watch(showConsoleKeysProvider);
    final prefix = widget.keyPrefix;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title),
            Text(
              widget.subtitle(_ptyStatus),
              key: Key('${prefix}_subtitle'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: _ptyStatus.alive
                    ? scheme.primary
                    : (_ptyStatus.hasError ? scheme.error : scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<double>(
            key: Key('${prefix}_font_size'),
            tooltip: '字号',
            icon: const Icon(Icons.format_size),
            initialValue: _fontSize,
            onSelected: (size) => setState(() => _fontSize = size),
            itemBuilder: (context) => [
              for (final size in _kFontSizes)
                PopupMenuItem(value: size, child: Text('$size')),
            ],
          ),
          IconButton(
            key: Key('${prefix}_clear'),
            tooltip: '清屏',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: () => _terminal.write(_kClearSequence),
          ),
          if (widget.onRestart != null)
            IconButton(
              key: Key('${prefix}_restart'),
              tooltip: '重启终端',
              icon: const Icon(Icons.restart_alt),
              onPressed: () => unawaited(_restart()),
            ),
          IconButton(
            key: Key('${prefix}_reconnect'),
            tooltip: '重新连接',
            icon: const Icon(Icons.refresh),
            onPressed: () => unawaited(_reconnect()),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: widget.url == null
                ? (widget.emptyState ?? const SizedBox.shrink())
                : ColoredBox(
                    color: _terminalTheme.background,
                    // xterm2 内部 import 的还是 `package:flutter/material.dart`，
                    // 属于 AGENTS.md 说的「仍依赖内建 Material 的第三方子树」——
                    // 规定的做法就是用桥接把 ThemeData / MaterialLocalizations
                    // 递进去。它标 deprecated 是因为「临时」而非「有替代品」，
                    // 目前没有别的写法，所以显式忽略这一条。
                    // ignore: deprecated_member_use
                    child: MaterialUiCompatibilityBridge(
                      child: xterm.TerminalView(
                        _terminal,
                        theme: _terminalTheme,
                        textStyle: xterm.TerminalStyle(
                          fontSize: _fontSize,
                          // 终端字体（设置页可改，null = 用 xterm2 默认等宽）
                          fontFamily: consoleFont ?? _kDefaultConsoleFont,
                        ),
                        padding: const EdgeInsets.all(8),
                        // 宽度自适应由 onResize 回给 daemon，终端自己跟着容器走
                        autoResize: true,
                      ),
                    ),
                  ),
          ),
          // 扩展按键栏（可在设置里关掉，默认显示）
          if (showKeys)
            SafeArea(top: false, child: TerminalKeysBar(_keys)),
        ],
      ),
    );
  }
}

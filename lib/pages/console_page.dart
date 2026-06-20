import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../config/terminal_store.dart';
import '../server/server_controller.dart';
import '../server/server_scope.dart';
import '../widgets/terminal_zoom.dart';

/// 控制台终端页：直接交互的伪终端（PTY + xterm）+ Termux 式扩展按键栏。
///
/// 不再有独立输入框——用户点击终端后即可像真实终端一样直接打字、回车，按键经 PTY
/// 送达服务端，支持 Tab 补全、命令历史、JLine 控制台与彩色输出。底部两排扩展按键
/// 补齐手机软键盘缺失的 ESC / CTRL / ALT / TAB / 方向键等。终端对象由全局
/// [ServerController] 持有，因此切实例 / 切页 / 页面重建时内容都不丢失。
class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key});

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  /// 终端字号（控制台独立记忆，持久化于 config/terminal.json）。
  double _fontSize = kDefaultTerminalFontSize;

  @override
  void initState() {
    super.initState();
    _loadFontSize();
  }

  Future<void> _loadFontSize() async {
    final size = await TerminalStore.loadConsoleFontSize();
    if (!mounted) return;
    setState(() => _fontSize = size);
  }

  void _setFontSize(double size) {
    if (size == _fontSize) return;
    setState(() => _fontSize = size);
  }

  void _saveFontSize() => TerminalStore.saveConsoleFontSize(_fontSize);

  @override
  Widget build(BuildContext context) {
    final server = ServerScope.of(context);
    final theme = Theme.of(context);
    final running = server.isRunning;
    final hasLog = server.log.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('控制台'),
            Text(
              '${_subtitle(server)} · ${server.lineMode ? "命令行" : "原始终端"}',
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    running ? Colors.green : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TerminalZoomButton(
            fontSize: _fontSize,
            onChanged: (size) {
              _setFontSize(size);
              _saveFontSize();
            },
          ),
          IconButton(
            icon: Icon(
              server.lineMode ? Icons.edit : Icons.keyboard,
            ),
            tooltip: server.lineMode ? '命令行编辑模式（点击切换原始终端）' : '原始终端模式（点击切换命令行编辑）',
            onPressed: server.toggleLineMode,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制全部日志',
            onPressed: !hasLog
                ? null
                : () {
                    Clipboard.setData(
                      ClipboardData(text: server.log.join('\n')),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('日志已复制到剪贴板')),
                    );
                  },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空终端',
            onPressed: !hasLog ? null : server.clearLog,
          ),
        ],
      ),
      // 键盘弹出时缩小终端区域；扩展按键栏紧贴键盘上方（Termux 式布局）。
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ZoomableTerminal(
                terminal: server.terminal,
                fontSize: _fontSize,
                onFontSizeChanged: _setFontSize,
                onFontSizeChangeEnd: _saveFontSize,
              ),
            ),
            _ExtraKeysBar(server),
          ],
        ),
      ),
    );
  }

  String _subtitle(ServerController server) {
    final name = server.runningInstanceName;
    return switch (server.status) {
      ServerStatus.preparing => '准备中 · ${name ?? ''}',
      ServerStatus.starting => '启动中 · ${name ?? ''}',
      ServerStatus.running => '运行中 · ${name ?? ''}',
      ServerStatus.stopping => '停止中 · ${name ?? ''}',
      ServerStatus.stopped => name == null ? '未运行' : '已停止 · $name',
    };
  }
}

/// 终端扩展按键栏：两排补齐软键盘缺失的终端控制键。
///
/// CTRL / ALT 是粘滞修饰键（点亮后对下一次输入生效一次）；其余为瞬时键，
/// 通过 [ServerController.sendKey] / [ServerController.sendText] 送往 PTY。
class _ExtraKeysBar extends StatelessWidget {
  const _ExtraKeysBar(this.server);

  final ServerController server;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _key(context, 'ESC', () => server.sendKey(TerminalKey.escape)),
                _key(context, '/', () => server.sendText('/')),
                _key(context, '-', () => server.sendText('-')),
                _key(context, 'HOME', () => server.sendKey(TerminalKey.home)),
                _key(context, '↑', () => server.sendKey(TerminalKey.arrowUp)),
                _key(context, 'END', () => server.sendKey(TerminalKey.end)),
                _key(context, 'PgUp', () => server.sendKey(TerminalKey.pageUp)),
              ],
            ),
            Row(
              children: [
                _key(context, 'TAB', () => server.sendKey(TerminalKey.tab)),
                _key(context, 'CTRL', server.toggleCtrl,
                    active: server.ctrlDown),
                _key(context, 'ALT', server.toggleAlt, active: server.altDown),
                _key(context, '←', () => server.sendKey(TerminalKey.arrowLeft)),
                _key(context, '↓', () => server.sendKey(TerminalKey.arrowDown)),
                _key(context, '→', () => server.sendKey(TerminalKey.arrowRight)),
                _key(context, 'PgDn', () => server.sendKey(TerminalKey.pageDown)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _key(
    BuildContext context,
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) =>
      Expanded(child: _KeyButton(label: label, onTap: onTap, active: active));
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = active ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = active ? scheme.onPrimary : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          // 不抢焦点，避免点击扩展键时收起软键盘 / 让终端失焦。
          canRequestFocus: false,
          child: Container(
            height: 38,
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

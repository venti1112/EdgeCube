import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../config/terminal_store.dart';
import '../i18n/locale_scope.dart';
import '../shell/shell_controller.dart';
import '../shell/shell_scope.dart';
import '../widgets/terminal_zoom.dart';

/// Shell 终端页：在设备上运行一个交互式 shell（系统 sh 或自带 busybox/bash）。
///
/// 直接交互的伪终端（PTY + xterm）+ Termux 式扩展按键栏，支持 `ls`/`cd`、彩色输出、
/// Tab 补全与命令历史（由 shell 自身在真实 TTY 上提供）。终端对象由全局
/// [ShellController] 持有，切页/重建内容不丢；打开页面时若未运行则自动启动。
class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  /// 终端字号（Shell 独立记忆，持久化于 config/terminal.json）。
  double _fontSize = kDefaultTerminalFontSize;

  @override
  void initState() {
    super.initState();
    _loadFontSize();
    // 打开页面时若未运行则自动启动一个 shell（在 build 之后访问 InheritedWidget）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final shell = ShellScope.of(context);
      if (!shell.isRunning) shell.start();
    });
  }

  Future<void> _loadFontSize() async {
    final size = await TerminalStore.loadShellFontSize();
    if (!mounted) return;
    setState(() => _fontSize = size);
  }

  void _setFontSize(double size) {
    if (size == _fontSize) return;
    setState(() => _fontSize = size);
  }

  void _saveFontSize() => TerminalStore.saveShellFontSize(_fontSize);

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('shell.title')),
            Text(
              shell.isRunning
                  ? (shell.shellLabel ?? 'shell')
                  : (shell.lastExitCode != null
                        ? context.tr('shell.exited', {
                            'code': shell.lastExitCode.toString(),
                          })
                        : context.tr('shell.notRunning')),
              style: theme.textTheme.bodySmall?.copyWith(
                color: shell.isRunning
                    ? Colors.green
                    : theme.colorScheme.onSurfaceVariant,
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
            icon: const Icon(Icons.restart_alt),
            tooltip: context.tr('shell.restart'),
            onPressed: () => shell.restart(),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: context.tr('shell.clear'),
            onPressed: shell.clear,
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
                terminal: shell.terminal,
                fontSize: _fontSize,
                onFontSizeChanged: _setFontSize,
                onFontSizeChangeEnd: _saveFontSize,
              ),
            ),
            _ExtraKeysBar(shell),
          ],
        ),
      ),
    );
  }
}

/// 终端扩展按键栏：两排补齐软键盘缺失的终端控制键（与控制台页一致）。
///
/// CTRL / ALT 是粘滞修饰键（点亮后对下一次输入生效一次）；其余为瞬时键，
/// 通过 [ShellController.sendKey] / [ShellController.sendText] 送往 PTY。
class _ExtraKeysBar extends StatelessWidget {
  const _ExtraKeysBar(this.shell);

  final ShellController shell;

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
                _key(context, 'ESC', () => shell.sendKey(TerminalKey.escape)),
                _key(context, '/', () => shell.sendText('/')),
                _key(context, '-', () => shell.sendText('-')),
                _key(context, 'HOME', () => shell.sendKey(TerminalKey.home)),
                _key(context, '↑', () => shell.sendKey(TerminalKey.arrowUp)),
                _key(context, 'END', () => shell.sendKey(TerminalKey.end)),
                _key(context, 'PgUp', () => shell.sendKey(TerminalKey.pageUp)),
              ],
            ),
            Row(
              children: [
                _key(context, 'TAB', () => shell.sendKey(TerminalKey.tab)),
                _key(context, 'CTRL', shell.toggleCtrl, active: shell.ctrlDown),
                _key(context, 'ALT', shell.toggleAlt, active: shell.altDown),
                _key(context, '←', () => shell.sendKey(TerminalKey.arrowLeft)),
                _key(context, '↓', () => shell.sendKey(TerminalKey.arrowDown)),
                _key(context, '→', () => shell.sendKey(TerminalKey.arrowRight)),
                _key(
                  context,
                  'PgDn',
                  () => shell.sendKey(TerminalKey.pageDown),
                ),
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
  }) => Expanded(
    child: _KeyButton(label: label, onTap: onTap, active: active),
  );
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

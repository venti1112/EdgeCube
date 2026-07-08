import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../config/terminal_store.dart';
import '../i18n/locale_scope.dart';
import '../shell/shell_controller.dart';
import '../shell/shell_scope.dart';
import '../shell/shell_service.dart';
import '../widgets/terminal_zoom.dart';

/// Shell 终端页：在设备上运行一个交互式 shell（系统 sh 或 proot 容器）。
///
/// 直接交互的伪终端（PTY + xterm）+ Termux 式扩展按键栏，支持 `ls`/`cd`、彩色输出、
/// Tab 补全与命令历史（由 shell 自身在真实 TTY 上提供）。终端对象由全局
/// [ShellController] 持有，切页/重建内容不丢；打开页面时若未运行则自动启动系统 sh。
class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  /// 终端字号（Shell 独立记忆，持久化于 config/terminal.json）。
  double _fontSize = kDefaultTerminalFontSize;

  /// 缓存的可用 shell 列表（用于下拉选择）。
  List<ShellOption> _options = const [];
  bool _optionsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadFontSize();
    _loadShellOptions();
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

  Future<void> _loadShellOptions() async {
    try {
      final service = ShellService();
      final opts = await service.availableShells();
      if (!mounted) return;
      setState(() {
        _options = opts;
        _optionsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _optionsLoaded = true);
    }
  }

  void _setFontSize(double size) {
    if (size == _fontSize) return;
    setState(() => _fontSize = size);
  }

  void _saveFontSize() => TerminalStore.saveShellFontSize(_fontSize);

  /// 切换到指定 shell：若当前正在运行则先停止，再以新 shellId 启动。
  Future<void> _switchShell(ShellOption opt) async {
    final shell = ShellScope.of(context);
    await shell.restart(shellId: opt.id);
  }

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
          // Shell 选择器：列出系统 sh 与已导入的 proot rootfs。
          // 仅在有多于一个选项时显示，避免单一 shell 时浪费空间。
          if (_optionsLoaded && _options.length > 1)
            PopupMenuButton<String>(
              tooltip: '切换 shell',
              icon: const Icon(Icons.terminal),
              onSelected: (id) {
                final opt = _options.firstWhere(
                  (o) => o.id == id,
                  orElse: () => _options.first,
                );
                _switchShell(opt);
              },
              itemBuilder: (ctx) => _options
                  .map((opt) => PopupMenuItem<String>(
                        value: opt.id,
                        child: Row(
                          children: [
                            Icon(
                              opt.type == 'proot'
                                  ? Icons.dns_outlined
                                  : Icons.terminal,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(opt.label)),
                          ],
                        ),
                      ))
                  .toList(),
            ),
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
/// 直接发送到 PTY（与控制台页共用同一套按键栏逻辑，但 shell 控制器不维护
/// 命令行编辑模式，所有键均以原始字节写入）。
class _ExtraKeysBar extends StatelessWidget {
  const _ExtraKeysBar(this.shell);

  final ShellController shell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Column(
        children: [
          // 第一排：粘滞修饰键 + ESC/TAB/方向/DEL
          Row(
            children: [
              _StickyKey('CTRL', shell.ctrlDown, shell.toggleCtrl),
              _StickyKey('ALT', shell.altDown, shell.toggleAlt),
              _InstantKey('ESC', () => shell.sendKey(TerminalKey.escape)),
              _InstantKey('TAB', () => shell.sendKey(TerminalKey.tab)),
              _InstantKey('↑', () => shell.sendKey(TerminalKey.arrowUp)),
              _InstantKey('↓', () => shell.sendKey(TerminalKey.arrowDown)),
              _InstantKey('←', () => shell.sendKey(TerminalKey.arrowLeft)),
              _InstantKey('→', () => shell.sendKey(TerminalKey.arrowRight)),
            ],
          ),
          // 第二排：HOME/END/PgUp/PgDn/INS/DEL + 常用符号
          Row(
            children: [
              _InstantKey('HOME', () => shell.sendKey(TerminalKey.home)),
              _InstantKey('END', () => shell.sendKey(TerminalKey.end)),
              _InstantKey('PGUP', () => shell.sendKey(TerminalKey.pageUp)),
              _InstantKey('PGDN', () => shell.sendKey(TerminalKey.pageDown)),
              _InstantKey('INS', () => shell.sendKey(TerminalKey.insert)),
              _InstantKey('DEL', () => shell.sendKey(TerminalKey.delete)),
              _InstantKey('-', () => shell.sendText('-')),
              _InstantKey('/', () => shell.sendText('/')),
            ],
          ),
        ],
      ),
    );
  }
}

/// 粘滞修饰键：点亮后对下一次输入生效一次，然后自动复位。
class _StickyKey extends StatelessWidget {
  const _StickyKey(this.label, this.active, this.onToggle);

  final String label;
  final bool active;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: FilledButton(
          onPressed: onToggle,
          style: FilledButton.styleFrom(
            backgroundColor: active
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            foregroundColor: active
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
            padding: const EdgeInsets.symmetric(vertical: 10),
            minimumSize: const Size(0, 0),
          ),
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }
}

/// 瞬时键：点击立即发送对应字节，无状态。
class _InstantKey extends StatelessWidget {
  const _InstantKey(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            foregroundColor: theme.colorScheme.onSurface,
            padding: const EdgeInsets.symmetric(vertical: 10),
            minimumSize: const Size(0, 0),
          ),
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }
}

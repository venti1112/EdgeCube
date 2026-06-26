import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xterm/xterm.dart';

import '../config/terminal_store.dart';
import '../i18n/locale_scope.dart';
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

  bool _exporting = false;

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

  Future<void> _exportLog(ServerController server) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/edgecube_log_$ts.log');
      await file.writeAsString(server.log.join('\n'));
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)]),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('console.exportFailed', {'error': '$e'})),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

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
            Text(context.tr('console.title')),
            Text(
              '${_subtitle(context, server)} · ${server.lineMode ? context.tr('console.modeCommandLine') : context.tr('console.modeRawTerminal')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: running
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
            icon: Icon(server.lineMode ? Icons.edit : Icons.keyboard),
            tooltip: server.lineMode
                ? context.tr('console.tooltipLineModeOn')
                : context.tr('console.tooltipLineModeOff'),
            onPressed: server.toggleLineMode,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: context.tr('console.tooltipCopyAllLogs'),
            onPressed: !hasLog
                ? null
                : () {
                    Clipboard.setData(
                      ClipboardData(text: server.log.join('\n')),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.tr('console.logCopied'))),
                    );
                  },
          ),
          IconButton(
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            tooltip: context.tr('console.tooltipExportLog'),
            onPressed: !hasLog ? null : () => _exportLog(server),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: context.tr('console.tooltipClearTerminal'),
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
            // RepaintBoundary 让按键栏拥有独立合成层，与 TerminalView 同步清除，
            // 避免 IndexedStack 切换时按键栏比终端慢一帧消失的视觉残留。
            RepaintBoundary(
              child: _ExtraKeysBar(server),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(BuildContext context, ServerController server) {
    final name = server.runningInstanceName;
    return switch (server.status) {
      ServerStatus.preparing => context.tr('console.statusPreparing', {
        'name': name ?? '',
      }),
      ServerStatus.starting => context.tr('console.statusStarting', {
        'name': name ?? '',
      }),
      ServerStatus.running => context.tr('console.statusRunning', {
        'name': name ?? '',
      }),
      ServerStatus.stopping => context.tr('console.statusStopping', {
        'name': name ?? '',
      }),
      ServerStatus.stopped =>
        name == null
            ? context.tr('console.statusNotRunning')
            : context.tr('console.statusStopped', {'name': name}),
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
                _key(
                  context,
                  'CTRL',
                  server.toggleCtrl,
                  active: server.ctrlDown,
                ),
                _key(context, 'ALT', server.toggleAlt, active: server.altDown),
                _key(context, '←', () => server.sendKey(TerminalKey.arrowLeft)),
                _key(context, '↓', () => server.sendKey(TerminalKey.arrowDown)),
                _key(
                  context,
                  '→',
                  () => server.sendKey(TerminalKey.arrowRight),
                ),
                _key(
                  context,
                  'PgDn',
                  () => server.sendKey(TerminalKey.pageDown),
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

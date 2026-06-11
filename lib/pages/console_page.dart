import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../server/server_controller.dart';
import '../server/server_scope.dart';

/// 控制台终端页：实时滚动日志 + 命令输入。
///
/// 日志与运行状态来自全局 [ServerController]，因此无论在哪个实例、哪个页面启动，
/// 这里都能看到同一个正在运行的服务端输出。
class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key});

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _cmd = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// 是否跟随到底部；用户上滑查看历史时自动暂停跟随。
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _cmd.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom =
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 24;
    if (atBottom != _autoScroll) {
      setState(() => _autoScroll = atBottom);
    }
  }

  void _scheduleAutoScroll() {
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _jumpToBottom() {
    setState(() => _autoScroll = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _send(ServerController server) {
    final text = _cmd.text;
    if (text.trim().isEmpty) return;
    server.sendCommand(text);
    _cmd.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final server = ServerScope.of(context);
    final theme = Theme.of(context);
    final log = server.log;
    final running = server.isRunning;

    _scheduleAutoScroll();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('控制台'),
            Text(
              _subtitle(server),
              style: theme.textTheme.bodySmall?.copyWith(
                color: running ? Colors.green : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制全部日志',
            onPressed: log.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: log.join('\n')));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('日志已复制到剪贴板')),
                    );
                  },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空日志',
            onPressed: log.isEmpty ? null : server.clearLog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: log.isEmpty
                      ? Center(
                          child: Text(
                            '暂无输出。\n在「服务器」页启动后，日志会实时显示在这里。',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : SelectionArea(
                          child: ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            itemCount: log.length,
                            itemBuilder: (context, i) {
                              final line = log[i];
                              final isCmd = line.startsWith('> ');
                              return Text(
                                line,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  height: 1.35,
                                  color: isCmd
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface,
                                  fontWeight:
                                      isCmd ? FontWeight.w600 : FontWeight.normal,
                                ),
                              );
                            },
                          ),
                        ),
                ),
                if (!_autoScroll && log.isNotEmpty)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      onPressed: _jumpToBottom,
                      child: const Icon(Icons.arrow_downward),
                    ),
                  ),
              ],
            ),
          ),
          _inputBar(context, server, running),
        ],
      ),
    );
  }

  String _subtitle(ServerController server) {
    final name = server.runningInstanceName;
    return switch (server.status) {
      ServerStatus.preparing => '准备中 · ${name ?? ''}',
      ServerStatus.starting  => '启动中 · ${name ?? ''}',
      ServerStatus.running   => '运行中 · ${name ?? ''}',
      ServerStatus.stopping  => '停止中 · ${name ?? ''}',
      ServerStatus.stopped   =>
        name == null ? '未运行' : '已停止 · $name',
    };
  }

  Widget _inputBar(BuildContext context, ServerController server, bool running) {
    final theme = Theme.of(context);
    return Material(
      elevation: 2,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cmd,
                  focusNode: _focus,
                  enabled: running,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(server),
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: running
                        ? '输入命令，回车发送（如 list、say hi、op <玩家>）'
                        : '服务器未运行',
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                color: theme.colorScheme.primary,
                onPressed: running ? () => _send(server) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

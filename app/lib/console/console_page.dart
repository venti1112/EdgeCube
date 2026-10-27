import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/state.dart';
import '../connection/settings.dart';
import '../instance/models.dart';
import '../instance/providers.dart';
import 'pty_client.dart';
import 'terminal_pane.dart';

/// 控制台：选中实例的 PTY 终端。
///
/// 终端本身（连接、历史、按键栏、字号、清屏、重连）在 [`TerminalPane`] 里，
/// 主机终端用的也是同一个组件 —— 两边协议完全一致，差别只有标题、
/// 副标题文案与「有没有重启按钮」。
///
/// 数据面走 daemon 的 `/pty/{id}`：
///
/// * 连上先收**历史快照**（daemon 侧保留最近 1 MiB），切页回来、App 重启后
///   连上都能看到之前的输出；
/// * 之后是实时输出；断开只是退订，**服务端进程照旧跑**；
/// * 服务端退出会推一条 `exit` 控制帧，这里的副标题随之变回「已停止」。
class ConsolePage extends ConsumerWidget {
  const ConsolePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(selectedInstanceDetailProvider).value;
    final instance = detail?.instance;
    final connected = ref.watch(isConnectedProvider);
    final settings = ref.watch(connectionSettingsProvider);

    return TerminalPane(
      keyPrefix: 'console',
      title: '控制台',
      subtitle: (status) => _subtitle(instance, connected, status),
      url: instance == null || !settings.isConfigured
          ? null
          : settings.ptyUri(instance.id),
      emptyState: _EmptyState(connected: connected),
    );
  }

  String _subtitle(Instance? instance, bool connected, PtyStatus status) {
    if (!connected) return '未连接到守护进程';
    if (instance == null) return '没有选中实例';
    return '${instance.name} · ${status.label}';
  }
}

/// 没有选中实例时的空态。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.terminal_outlined,
            size: 72,
            color: connected ? scheme.primary : scheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            connected ? '没有选中的实例' : '未连接到守护进程',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              connected ? '在「服务器」页右上角选一个实例，这里就是它的控制台。' : '连上之后这里会显示所选实例的控制台。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

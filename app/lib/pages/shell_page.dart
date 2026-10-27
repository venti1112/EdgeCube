import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/settings.dart';
import '../connection/state.dart';
import '../console/pty_client.dart';
import '../console/shell_api.dart';
import '../console/terminal_pane.dart';
import '../instance/models.dart';

/// 主机终端：daemon 所在机器上的一个交互式 shell。
///
/// 入口在「管理」页。跑的不是某个实例的控制台，而是 daemon 那台机器本身的
/// shell（`$SHELL` / bash / sh；Windows 上是 `cmd.exe`），工作目录默认是
/// daemon 的 `$HOME`。
///
/// 行为：
///
/// * **单会话**：一个 daemon 只有一个 shell，多端连上来共享同一条 PTY 与历史；
/// * 断开页面**不杀**进程，回来还能接着看；
/// * shell 自己 `exit` 后，下次进来会自动重开（历史保留，前面能看到退出码）；
/// * 顶栏的「重启终端」会调 `shell.restart`：杀掉当前进程并立即重开。
class ShellPage extends ConsumerWidget {
  const ShellPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(connectionSettingsProvider);
    final connected = ref.watch(isConnectedProvider);
    final api = ref.watch(shellApiProvider);

    return TerminalPane(
      keyPrefix: 'shell',
      title: '主机终端',
      subtitle: (status) => _subtitle(connected, status),
      url: connected && settings.isConfigured ? settings.shellUri : null,
      emptyState: _EmptyState(connected: connected),
      onRestart: api == null ? null : () => api.restart(),
    );
  }

  String _subtitle(bool connected, PtyStatus status) {
    if (!connected) return '未连接到守护进程';
    if (status.hasError) return status.label;
    if (status.phase == ServerPhase.running) return 'daemon 主机 · 运行中';
    final code = status.exitCode;
    return code == null ? 'daemon 主机 · 已退出' : 'daemon 主机 · 已退出（退出码 $code）';
  }
}

/// 没连上 daemon 时的空态。
///
/// 连上之后不会走到这里 —— `/shell` 一连接就会把 shell 拉起来，
/// 起不来也会把原因写进终端历史里。
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
            connected ? '正在打开主机终端…' : '未连接到守护进程',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              connected
                  ? '连上后这里会显示守护进程所在机器的 shell。'
                  : '先在「设置 → 连接」里连上守护进程。',
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

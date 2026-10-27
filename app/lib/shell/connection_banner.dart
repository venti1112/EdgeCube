import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/state.dart';
import '../local_service/model.dart';
import '../local_service/settings.dart';
import '../local_service/state.dart';

/// 主界面顶部的连接横幅:只在**没连上**或**本地服务正在准备**时出现。
///
/// 掉线为什么不像首次启动那样把人送回连接页:daemon 重启、网络抖动都很常见,
/// 每次都被踢走没法用。所以这里用横幅提示 + 一键重试,页面状态保留。
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionProvider);
    final localEnabled = ref.watch(localServiceEnabledProvider);
    // 只盯状态字段:daemon 每输出一行日志都重建横幅没有意义
    final local = ref.watch(
      localServiceProvider.select(
        (s) => (supported: s.supported, status: s.status, error: s.error),
      ),
    );
    final localPhase = local.status.phase;
    final localAvailable = localEnabled && local.supported != false;

    // 本地服务准备/启动/停止时优先展示它的进度,连接状态先放一边
    if (localAvailable && local.status.isBusy) {
      final stopping = localPhase == LocalServicePhase.stopping;
      final scheme = Theme.of(context).colorScheme;
      return _BannerBar(
        background: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
        leading: const _BarSpinner(),
        text: local.status.message ?? (stopping ? '正在停止本地服务…' : '正在准备本地环境…'),
        action: stopping
            ? null
            : TextButton(
                onPressed: () => ref.read(localServiceProvider.notifier).stop(),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onTertiaryContainer,
                ),
                child: const Text('停止'),
              ),
      );
    }

    if (status.isConnected) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // 本地服务没起来:给原因和重试,而不是只说「连接失败」
    if (localAvailable && localPhase == LocalServicePhase.failed) {
      final reason =
          local.status.message ??
          (local.error == null ? '本地服务启动失败' : '本地服务启动失败：${local.error}');
      return _BannerBar(
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
        leading: Icon(
          Icons.error_outline,
          size: 18,
          color: scheme.onErrorContainer,
        ),
        text: reason,
        action: TextButton(
          onPressed: () => ref.read(localServiceProvider.notifier).start(),
          style: TextButton.styleFrom(foregroundColor: scheme.onErrorContainer),
          child: const Text('重试'),
        ),
      );
    }

    final (icon, background, foreground) = switch (status.phase) {
      ConnectionPhase.connecting => (
        Icons.sync,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      ConnectionPhase.failed => (
        Icons.cloud_off_outlined,
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      _ => (
        Icons.cloud_queue_outlined,
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };

    final text = switch (status.phase) {
      ConnectionPhase.connecting => '正在连接 ${status.target ?? ''}…',
      ConnectionPhase.failed =>
        status.error ?? '与 ${status.target ?? '服务器'} 的连接已断开',
      _ => '未连接${status.target == null ? '' : '（${status.target}）'}',
    };

    return _BannerBar(
      background: background,
      foreground: foreground,
      leading: status.isConnecting
          ? _BarSpinner(color: foreground)
          : Icon(icon, size: 18, color: foreground),
      text: text,
      action: status.isConnecting
          ? null
          : TextButton(
              onPressed: () {
                // 本地服务已就绪时重连它,而不是去连手工填写的地址
                if (localAvailable && localPhase == LocalServicePhase.running) {
                  ref.read(localServiceProvider.notifier).retryConnection();
                } else {
                  ref.read(connectionProvider.notifier).retry();
                }
              },
              style: TextButton.styleFrom(foregroundColor: foreground),
              child: const Text('重试'),
            ),
    );
  }
}

class _BarSpinner extends StatelessWidget {
  const _BarSpinner({this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 16,
    child: CircularProgressIndicator(strokeWidth: 2, color: color),
  );
}

class _BannerBar extends StatelessWidget {
  const _BannerBar({
    required this.background,
    required this.foreground,
    required this.leading,
    required this.text,
    this.action,
  });

  final Color background;
  final Color foreground;
  final Widget leading;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          key: const Key('connection_banner'),
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: foreground),
              ),
            ),
            ?action,
            IconButton(
              tooltip: '连接设置',
              visualDensity: VisualDensity.compact,
              color: foreground,
              icon: const Icon(Icons.settings_outlined, size: 18),
              onPressed: () => context.go('/settings/connection'),
            ),
          ],
        ),
      ),
    );
  }
}

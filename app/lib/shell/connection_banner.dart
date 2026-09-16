import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/state.dart';

/// 主界面顶部的连接横幅:只在**没连上**时出现。
///
/// 掉线为什么不像首次启动那样把人送回连接页:daemon 重启、网络抖动都很常见,
/// 每次都被踢走没法用。所以这里用横幅提示 + 一键重试,页面状态保留。
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionProvider);
    if (status.isConnected) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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

    return Material(
      color: background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          key: const Key('connection_banner'),
          children: [
            if (status.isConnecting)
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            else
              Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: foreground),
              ),
            ),
            if (!status.isConnecting)
              TextButton(
                onPressed: ref.read(connectionProvider.notifier).retry,
                style: TextButton.styleFrom(foregroundColor: foreground),
                child: const Text('重试'),
              ),
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

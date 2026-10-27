import 'package:material_ui/material_ui.dart';

/// 向导里几个页面共用的「加载失败 + 重试」占位。
///
/// 与 `frp_tunnel_list_page.dart` 里的同名私有组件是同一套排版，放在这里是因为
/// 下载向导有四个页面都要用它。
class DownloadErrorState extends StatelessWidget {
  const DownloadErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

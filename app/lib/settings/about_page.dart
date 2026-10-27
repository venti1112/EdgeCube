import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/client.dart';
import 'about.dart';

/// 关于页：应用版本与两端设备信息。
///
/// 两张卡的数据来源不同：
/// * 前端：`clientDeviceInfoProvider`（本机插件 + 当前窗口的屏幕信息）；
/// * 后端：`daemonDeviceInfoProvider`（daemon 的 `core.host` + `core.info`）。
///
/// 未连接时后端卡只说明「未连接」，不当成错误；旧版 daemon 没有
/// `core.host` 时给升级提示，但仍然显示守护进程版本。
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(clientDeviceInfoProvider);
    final daemon = ref.watch(daemonDeviceInfoProvider);
    final size = MediaQuery.sizeOf(context);
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final screen =
        '${size.width.toStringAsFixed(0)} × '
        '${size.height.toStringAsFixed(0)} · '
        '${ratio.toStringAsFixed(1)}x';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('关于'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DeviceCard(
            icon: Icons.phone_android_outlined,
            title: '前端运行设备',
            child: client.when(
              data: (info) => Column(
                children: [
                  _InfoRow(label: '运行平台', value: info.platform),
                  _InfoRow(label: '系统版本', value: info.system),
                  _InfoRow(label: '设备', value: info.device),
                  _InfoRow(label: '处理器', value: info.cpuLabel),
                  _InfoRow(label: '内存', value: info.memoryLabel),
                  _InfoRow(label: '屏幕', value: screen),
                  _InfoRow(label: '应用版本', value: info.appVersion),
                ],
              ),
              loading: () => const _CardLoading(text: '正在读取本机信息…'),
              error: (error, _) => _CardNotice(
                icon: Icons.error_outline,
                text: '读取本机信息失败：$error',
              ),
            ),
          ),
          const SizedBox(height: 12),
          _DeviceCard(
            icon: Icons.dns_outlined,
            title: '后端运行设备',
            child: daemon.when(
              data: (info) => info == null
                  ? const _CardNotice(
                      icon: Icons.cloud_off_outlined,
                      text: '未连接守护进程。连接后会自动读取后端设备信息。',
                    )
                  : _DaemonInfo(info: info),
              loading: () => const _CardLoading(text: '正在读取守护进程信息…'),
              error: (error, _) => _DaemonError(
                error: error,
                onRetry: () => ref.invalidate(daemonDeviceInfoProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleSmall),
              ],
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _DaemonInfo extends StatelessWidget {
  const _DaemonInfo({required this.info});

  final DaemonDeviceInfo info;

  @override
  Widget build(BuildContext context) {
    final host = info.host;
    final rows = <Widget>[];

    if (host == null) {
      rows.add(
        _CardNotice(
          icon: Icons.info_outline,
          text: info.hostUnsupported
              ? '当前守护进程版本不支持 core.host，暂时读不到主机信息。升级 daemon 后即可显示。'
              : '暂时读不到主机信息。',
        ),
      );
    } else {
      rows.addAll([
        _InfoRow(label: '主机名', value: host.hostname ?? '未知'),
        _InfoRow(label: '系统版本', value: host.systemLabel),
        _InfoRow(label: '内核', value: host.kernelVersion ?? '未知'),
        _InfoRow(label: '架构', value: host.arch ?? '未知'),
        _InfoRow(label: '处理器', value: host.cpuBrand ?? '未知'),
        _InfoRow(label: '处理器核心', value: host.cpuCoresLabel),
        _InfoRow(label: '内存', value: host.memoryLabel),
        _InfoRow(label: '系统已运行', value: host.uptimeLabel),
      ]);
    }

    if (info.info.isNotEmpty) {
      rows.add(
        host == null ? const SizedBox(height: 8) : const Divider(height: 18),
      );
      rows.add(_InfoRow(label: '守护进程', value: info.daemonLabel));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _DaemonError extends StatelessWidget {
  const _DaemonError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error is DaemonException
        ? (error as DaemonException).message
        : '$error';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CardNotice(icon: Icons.error_outline, text: '读取后端设备信息失败：$message'),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ),
      ],
    );
  }
}

class _CardLoading extends StatelessWidget {
  const _CardLoading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardNotice extends StatelessWidget {
  const _CardNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

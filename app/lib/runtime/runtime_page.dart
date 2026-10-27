import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../download/format.dart';
import '../download/providers.dart' show downloadTaskProvider;
import '../task/providers.dart' show taskApiProvider;
import 'api.dart' show describeRuntimeError;
import 'models.dart';
import 'providers.dart';

/// 「运行环境」页：已装环境的列表 + 下载入口（JDK / frp 都在这里）。
///
/// 排版是一张张环境卡 + 底部操作（Material 的 Card + ListTile）。
/// V2 这页管的是**从上游下载**（Zulu 的 JDK、fatedier 的 frp）——
/// 有哪些厂商由 `runtime.catalog` 决定（daemon 的表），前端零硬编码。
/// 导入那套等有本机文件上传再做。
///
/// 安装是 daemon 侧的事（`runtime.install` 发出去就可以走人），这一页只管
/// 把「下载中 / 解压中 / 装好 / 失败」呈现出来：状态变化靠 `runtime.state`
/// 事件刷新列表，下载进度拿 `env.taskId` 订 `download.progress`。
class RuntimePage extends ConsumerWidget {
  const RuntimePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 页面活着就要收状态事件；列表本身在 [runtimeListProvider] 里
    ref.watch(runtimeEventsProvider);
    final list = ref.watch(runtimeListProvider);
    final catalog = ref.watch(runtimeCatalogProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('运行环境'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          message: describeRuntimeError(error),
          onRetry: () => ref.invalidate(runtimeListProvider),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(runtimeListProvider),
          child: _Body(
            environments: data.environments,
            dir: data.dir,
            catalog: catalog.value,
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.environments,
    required this.dir,
    required this.catalog,
  });

  final List<RuntimeEnv> environments;
  final String dir;
  final RuntimeCatalog? catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supported = catalog?.supported ?? false;
    final host = catalog?.host;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (!supported) ...[
          const _UnsupportedCard(),
          const SizedBox(height: 16),
        ] else ...[
          FilledButton.tonalIcon(
            onPressed: () => context.push('/manage/runtime/download'),
            icon: const Icon(Icons.download_outlined),
            label: const Text('下载运行环境'),
          ),
          const SizedBox(height: 8),
          Text(
            '装到 $dir'
            '${host == null ? '' : '（${host.label} 的构建）'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 16),
        if (environments.isEmpty)
          const _EmptyHint()
        else
          for (final env in environments) ...[
            _EnvCard(env: env, catalog: catalog),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

/// 这台机器装不了：入口置灰，但把原因摆出来（项目约定：不藏）。
class _UnsupportedCard extends StatelessWidget {
  const _UnsupportedCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.block_outlined, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '这台机器没有对应的 Zulu 构建，暂时装不了运行环境',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(
          '还没有运行环境，先下载一个（JDK 或 frp）',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// 一个环境一张卡。状态不同，卡里多出来的那块也不同。
class _EnvCard extends ConsumerWidget {
  const _EnvCard({required this.env, required this.catalog});

  final RuntimeEnv env;
  final RuntimeCatalog? catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final stateColor = switch (env.state) {
      RuntimeEnvState.installed => scheme.primary,
      RuntimeEnvState.failed => scheme.error,
      _ => scheme.onSurfaceVariant,
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon, size: 28, color: stateColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        runtimeEnvTitle(catalog, env),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: env.isBusy ? '取消并删除' : '删除',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context, ref),
                ),
              ],
            ),
            // 状态那块：下载中给进度条，解压中给不确定条，失败给原因 + 重试
            ..._stateBlock(context, ref),
          ],
        ),
      ),
    );
  }

  IconData get _icon => switch (env.state) {
    RuntimeEnvState.installed => Icons.verified_outlined,
    RuntimeEnvState.failed => Icons.error_outline,
    _ => Icons.downloading,
  };

  String get _subtitle {
    // 版本那一截由 daemon 的 catalog 决定口径（JDK 的 `Java 21` 是它拼的），
    // 环境对象里给的是更完整的版本串
    final version = env.versionName.isNotEmpty ? env.versionName : env.version;
    final parts = <String>[version];
    if (env.vendorVersion.isNotEmpty) {
      parts.add('${env.vendor.toUpperCase()} ${env.vendorVersion}');
    }
    parts.add(env.platformLabel);
    if (env.supportTerm case final term?) {
      parts.add(term.toUpperCase());
    }
    if (env.size case final size?) parts.add(formatBytes(size));
    return parts.join(' · ');
  }

  List<Widget> _stateBlock(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    switch (env.state) {
      case RuntimeEnvState.installed:
        final bin = env.binary;
        return [
          const SizedBox(height: 8),
          Text(
            bin == null ? '已安装' : '可执行文件：$bin',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ];
      case RuntimeEnvState.extracting:
        return [
          const SizedBox(height: 12),
          const LinearProgressIndicator(minHeight: 4),
          const SizedBox(height: 8),
          Text('正在解压…', style: Theme.of(context).textTheme.bodySmall),
        ];
      case RuntimeEnvState.downloading:
        return [
          const SizedBox(height: 12),
          _DownloadProgress(taskId: env.taskId, size: env.size),
        ];
      case RuntimeEnvState.failed:
        return [
          const SizedBox(height: 8),
          Text(
            '${env.stage?.label ?? ''}失败：${env.error ?? '未知原因'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _retry(context, ref),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ),
        ];
    }
  }

  /// 重试：重新提交一次 `runtime-install` 工作流。
  ///
  /// 装在 daemon 那边是「下载 → 解压」两步；失败时它会把半截产物清掉，
  /// 所以重试就是干干净净地再来一遍（暂存里若还有能用的包会跳过下载）。
  Future<void> _retry(BuildContext context, WidgetRef ref) async {
    final tasks = ref.read(taskApiProvider);
    if (tasks == null) return;
    try {
      await tasks.submit('runtime-install', {
        'provider': env.vendor,
        'package_type': env.packageType,
        'version': env.version,
      });
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除运行环境'),
        content: Text(
          env.isBusy
              ? '「${runtimeEnvTitle(catalog, env)}」正在安装。'
                    '现在删除会连下载一起取消，确定吗？'
              : '删掉「${runtimeEnvTitle(catalog, env)}」？'
                    '目录会一并删除，这个操作无法撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final api = ref.read(runtimeApiProvider);
    if (api == null) return;
    try {
      await api.delete(env.id);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  void _showError(BuildContext context, Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(describeRuntimeError(error))),
    );
  }
}

/// 下载中的那块：复用下载队列的进度订阅，不另开通道。
class _DownloadProgress extends ConsumerWidget {
  const _DownloadProgress({required this.taskId, required this.size});

  final String? taskId;

  /// 元数据里的包大小 —— 事件还没到时先拿它画个大概。
  final int? size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = taskId == null ? null : ref.watch(downloadTaskProvider(taskId!));
    final scheme = Theme.of(context).colorScheme;

    // 事件还没来：只知道总大小，画个不确定条 + 总量
    if (task == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(minHeight: 4),
          if (size != null) ...[
            const SizedBox(height: 8),
            Text(
              '共 ${formatBytes(size!)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      );
    }

    final fraction = task.fraction;
    final detail = [
      if (task.hasTotal) formatBytes(task.completedSize),
      formatSpeed(task.downloadSpeed),
      if (task.eta case final eta?) '剩余 ${formatEta(eta.inSeconds)}',
    ].where((part) => part.isNotEmpty).join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: fraction,
          minHeight: 4,
        ),
        const SizedBox(height: 8),
        Text(
          task.hasTotal
              ? '${((task.fraction ?? 0) * 100).toStringAsFixed(1)}% · $detail'
              : (detail.isEmpty ? '正在下载…' : detail),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 列表取失败：一句话 + 重试。
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

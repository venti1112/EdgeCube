import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/client.dart';
import '../task/api.dart';
import '../task/providers.dart';
import 'api.dart';
import 'models.dart';
import 'providers.dart';

/// 「下载运行环境」：列可装的版本，点一个就开始装。
///
/// 安装是 daemon 侧的事 —— 提交 `runtime-install` 工作流就回列表页看进度，
/// 这里不等人。版本列表来自 `runtime.versions`（daemon 现打上游），失败给
/// 重试；**默认只给最新那个**（`all = false`，一次上游请求就够），
/// 想看老版本点「历史版本」才去拉完整列表 —— frp 的清单走 GitHub API，
/// 未认证只有 60 次/小时，所以默认值必须是「最省」的那个。
class RuntimeDownloadPage extends ConsumerStatefulWidget {
  const RuntimeDownloadPage({super.key, this.provider});

  /// 打开时选中的厂商；不给就用 catalog 的默认那个。
  final String? provider;

  @override
  ConsumerState<RuntimeDownloadPage> createState() => _RuntimeDownloadPageState();
}

class _RuntimeDownloadPageState extends ConsumerState<RuntimeDownloadPage> {
  /// 正在发起安装的那个版本（按钮转圈用）。版本是**字符串**（`21` / `0.71.0`）。
  String? _installing;

  /// 用户在顶部选的厂商（`zulu` / `frp`）。`null` = 还没选，用 catalog 的默认值。
  String? _provider;

  /// 用户点了「历史版本」：这一轮去拉完整列表。
  ///
  /// 与列表本身分开存（而不是直接改 query）是为了让「收起」也做得出来：
  /// 再点一次就回到「只要最新」那一份。
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(runtimeCatalogProvider);
    final providers = catalog.value?.providers ?? const <RuntimeProvider>[];
    final providerId =
        _provider ?? widget.provider ?? catalog.value?.defaultProvider ?? 'zulu';
    // 包类型跟着厂商走：frp 只提供 `frpc`，拿默认的 `jdk` 去问会被 daemon 拒
    final provider = providers.where((p) => p.id == providerId).firstOrNull;
    final packageType = provider?.packageTypes.firstOrNull ??
        catalog.value?.defaultPackageType ??
        'jdk';
    // 「历史版本」是个开关：关着时只拉最新（默认省一次上游请求）
    final query = (
      provider: providerId,
      packageType: packageType,
      all: _showHistory,
    );
    final versions = ref.watch(runtimeVersionsProvider(query));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('下载运行环境'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: Column(
        children: [
          // 厂商是 daemon 的表给的（几个、叫什么都在那儿），前端只负责画出来。
          // 只有一个厂商时整块不显示 —— 别给用户一个只有唯一选项的选择器。
          if (providers.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SegmentedButton<String>(
                segments: [
                  for (final item in providers)
                    ButtonSegment(value: item.id, label: Text(item.name)),
                ],
                selected: {providerId},
                onSelectionChanged: (selection) => setState(() {
                  _provider = selection.first;
                  // 换厂商 = 换一份清单：历史版本的展开状态也复位
                  _showHistory = false;
                }),
              ),
            ),
          Expanded(
            child: versions.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorView(
                message: describeRuntimeError(error),
                onRetry: () => ref.invalidate(runtimeVersionsProvider(query)),
              ),
              data: (data) => _VersionList(
                versions: data,
                installing: _installing,
                onInstall: (version) =>
                    _install(version, providerId, packageType),
                onHistory: () => setState(() => _showHistory = !_showHistory),
                // 切到历史版本会换 query（= 换 provider 实例），这时 `versions`
                // 会回到 loading —— 所以「正在拉」就是「开着但这一份还没到」。
                loadingHistory: _showHistory && !data.all,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 提交 `runtime-install` 工作流（「下载 → 解压」两步都在 daemon 那边）。
  ///
  /// 提交成功就回列表页 —— 进度在列表里看（环境元数据带 `task_id`，页面拿它
  /// 订 `download.progress`）。**上游找不到版本这类失败发生在任务里**，
  /// 所以列表上的那个环境会变成 `failed` 并带上原因，而不是在这里弹错。
  Future<void> _install(
    String version,
    String providerId,
    String packageType,
  ) async {
    if (_installing != null) return;
    setState(() => _installing = version);

    try {
      final tasks = ref.read(taskApiProvider);
      if (tasks == null) {
        throw const DaemonException('unavailable', '还没有连接到守护进程');
      }
      await tasks.submit('runtime-install', {
        'provider': providerId,
        'package_type': packageType,
        'version': version,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('开始下载 $version，装完会出现在列表里')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      final message = error is DaemonException
          ? describeTaskError(error)
          : '$error';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _installing = null);
    }
  }
}

class _VersionList extends StatelessWidget {
  const _VersionList({
    required this.versions,
    required this.installing,
    required this.onInstall,
    required this.onHistory,
    required this.loadingHistory,
  });

  final RuntimeVersions versions;
  final String? installing;
  final void Function(String version) onInstall;

  /// 点「历史版本」：去拉完整列表。
  final VoidCallback onHistory;

  /// 正在拉历史版本（按钮转圈）。
  final bool loadingHistory;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '将安装 ${versions.os} · ${versions.arch} 的构建，装到运行环境目录',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
        // 默认只给最新那个。frp 绝大多数情况用最新版就够，所以老版本藏在
        // 这个按钮后面 —— 点了才去拉（也少打一次上游）。
        // `all == true` 时列表已经是全部了，按钮就不必再显示。
        if (!versions.all)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: loadingHistory ? null : onHistory,
                icon: loadingHistory
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.history, size: 18),
                label: const Text('历史版本'),
              ),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              for (final version in versions.versions) ...[
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    // 图标按厂商给：JDK 是咖啡杯，别的一律用通用图标
                    leading: Icon(
                      versions.provider == 'zulu'
                          ? Icons.coffee_outlined
                          : Icons.hub_outlined,
                    ),
                    // 主行 / 副行都是 daemon 给的（见 RuntimeVersion 的注释）
                    title: Text(version.label),
                    subtitle: version.subtitle.isEmpty
                        ? null
                        : Text(version.subtitle),
                    trailing: installing == version.version
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : FilledButton(
                            onPressed: () => onInstall(version.version),
                            child: const Text('安装'),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message, textAlign: TextAlign.center),
          ),
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

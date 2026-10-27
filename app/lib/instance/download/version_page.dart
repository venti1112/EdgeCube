import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../mcserver/api.dart';
import '../../mcserver/providers.dart';
import 'progress_page.dart';
import 'states.dart';
import 'wizard.dart';

/// 流程第 3 页：选择版本。
///
/// 选中之后分两路：
///
/// * 需要加载器版本的（Fabric）→ 先进 [DownloadLoaderVersionPage]；
/// * 其余 → 直接进下载页。
class DownloadVersionPage extends ConsumerWidget {
  const DownloadVersionPage({super.key, required this.wizard});

  final DownloadWizard wizard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = wizard.kind!;
    final versions = ref.watch(serverVersionsProvider(kind.id));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('选择版本'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: versions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => DownloadErrorState(
          message: describeMcserverError(error),
          onRetry: () => ref.invalidate(serverVersionsProvider(kind.id)),
        ),
        data: (versions) => _VersionList(
          versions: versions,
          // daemon 已经排好序（新版本在前），这里原样展示
          emptyHint: '${kind.name} 暂无可用版本',
          onSelect: (version) => _select(context, version),
        ),
      ),
    );
  }

  void _select(BuildContext context, String version) {
    wizard.version = version;
    final kind = wizard.kind!;
    final next = kind.needsLoader
        ? DownloadLoaderVersionPage(wizard: wizard)
        : DownloadProgressPage(wizard: wizard);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => next));
  }
}

/// 流程第 3.5 页：选择加载器版本（目前只有 Fabric 会走到这里）。
///
/// 两页结构：先选 Minecraft 版本，再选加载器版本 ——
/// 因为「某个 MC 版本下有哪些加载器」只有上游知道。
class DownloadLoaderVersionPage extends ConsumerWidget {
  const DownloadLoaderVersionPage({super.key, required this.wizard});

  final DownloadWizard wizard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = wizard.kind!;
    final mcVersion = wizard.version ?? '';
    final query = (type: kind.id, mcVersion: mcVersion);
    final loaders = ref.watch(serverLoadersProvider(query));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('选择加载器版本'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: Column(
        children: [
          // 上一层选了哪个 MC 版本，这里要看得见（否则用户会不知道自己在给谁选加载器）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Minecraft $mcVersion',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          Expanded(
            child: loaders.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => DownloadErrorState(
                message: describeMcserverError(error),
                onRetry: () => ref.invalidate(serverLoadersProvider(query)),
              ),
              data: (loaders) => _VersionList(
                versions: loaders,
                emptyHint: '$mcVersion 下没有可用的加载器版本',
                onSelect: (loader) {
                  wizard.loaderVersion = loader;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DownloadProgressPage(wizard: wizard),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 版本列表：一列卡片，每张一行。
///
/// 版本多的时候可能有一两百条 —— 用 [ListView.builder] 而不是一次性建出来。
class _VersionList extends StatelessWidget {
  const _VersionList({
    required this.versions,
    required this.emptyHint,
    required this.onSelect,
  });

  final List<String> versions;
  final String emptyHint;
  final void Function(String version) onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (versions.isEmpty) {
      return Center(
        child: Text(emptyHint, style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: versions.length,
      itemBuilder: (context, index) {
        final version = versions[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              title: Text(version),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onSelect(version),
            ),
          ),
        );
      },
    );
  }
}

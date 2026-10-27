import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../mcserver/models.dart';
import '../../mcserver/providers.dart';
import 'progress_page.dart';
import 'version_page.dart';
import 'wizard.dart';

/// 流程第 2 页：选择该分类下的具体服务端。
class DownloadServerPage extends ConsumerWidget {
  const DownloadServerPage({
    super.key,
    required this.wizard,
    required this.categoryId,
    required this.categoryName,
  });

  final DownloadWizard wizard;
  final String categoryId;
  final String categoryName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 分类页已经把类型表拉下来了，这里走缓存（同一个 Provider）
    final catalog = ref.watch(serverCatalogProvider).value;
    final category = _findCategory(catalog, categoryId);
    final kinds = category == null
        ? const <ServerKind>[]
        : catalog!.kindsOf(category);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(categoryName),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: kinds.isEmpty
          // 正常不会走到（上一页已经把类型表拉下来了）；真走到说明连接断了
          ? const Center(child: Text('暂时拿不到服务端列表，返回重试'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final kind in kinds) ...[
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: Icon(serverIcon(kind.id), size: 28),
                      title: Text(kind.name),
                      subtitle: Text(kind.description),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _select(context, kind),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }

  /// 选定服务端类型后往哪走。
  ///
  /// 没有版本概念的类型（BungeeCord）**跳过版本页直接下载**。
  void _select(BuildContext context, ServerKind kind) {
    wizard.kind = kind;
    wizard.version = null;
    wizard.loaderVersion = null;

    final next = kind.needsVersion
        ? DownloadVersionPage(wizard: wizard)
        : DownloadProgressPage(wizard: wizard);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => next));
  }

  static ServerCategory? _findCategory(
    ServerCatalog? catalog,
    String id,
  ) {
    if (catalog == null) return null;
    for (final category in catalog.categories) {
      if (category.id == id) return category;
    }
    return null;
  }
}

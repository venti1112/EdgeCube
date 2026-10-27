import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../mcserver/api.dart';
import '../../mcserver/providers.dart';
import 'server_page.dart';
import 'states.dart';
import 'wizard.dart';

/// 流程第 1 页：选择服务端分类（原版 / 插件 / 模组 / 代理）。
///
/// 分类与类型全部来自 daemon 的 `mcserver.types` —— 前端不硬编码任何源的知识。
///
/// 这一页是**流程的根**（推送时用 [kDownloadFlowRootRouteName] 命名），
/// 最后一步完成后由 [finishDownloadFlow] 一次弹回这里。
class DownloadCategoryPage extends ConsumerWidget {
  const DownloadCategoryPage({super.key, required this.wizard});

  final DownloadWizard wizard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(serverCatalogProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('选择服务端分类'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => DownloadErrorState(
          message: describeMcserverError(error),
          onRetry: () => ref.invalidate(serverCatalogProvider),
        ),
        data: (catalog) => catalog.categories.isEmpty
            // 未连接时 `serverCatalogProvider` 给的是空表而不是错误 ——
            // 这里要说明白，否则用户只看到一片空白
            ? const Center(child: Text('还没有连接到守护进程'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final category in catalog.categories) ...[
                    Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: Icon(categoryIcon(category.id), size: 28),
                        title: Text(category.name),
                        subtitle: Text(category.description),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => DownloadServerPage(
                              wizard: wizard,
                              categoryId: category.id,
                              categoryName: category.name,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
      ),
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../server/server_entry.dart';
import '../server/server_service.dart';

/// 服务器管理页:添加/删除服务器,查看连接状态,点击条目连接。
class ServerSettingsPage extends ConsumerWidget {
  const ServerSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serverListProvider);
    final currentId = ref.watch(currentServerIdProvider);
    final session = ref.watch(sessionProvider);
    final hasKey = ref.watch(hasLocalKeyProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('服务器'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加服务器',
            onPressed: () => context.push('/settings/servers/add'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/settings/servers/add'),
        child: const Icon(Icons.add),
      ),
      body: servers.isEmpty
          ? _EmptyView(hasKey: hasKey)
          : ListView(
              children: [
                for (final entry in servers)
                  _ServerTile(
                    entry: entry,
                    isCurrent: entry.id == currentId,
                    isConnected: session != null &&
                        session.serverId == entry.id,
                  ),
              ],
            ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.hasKey});

  final bool hasKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined, size: 48, color: cs.outline),
            const SizedBox(height: 12),
            Text(hasKey ? '未添加本地服务器' : '还没有服务器'),
            const SizedBox(height: 4),
            Text(
              hasKey ? '本机检测到 daemon,可添加本地服务器免密连接' : '点击右上角 + 添加服务器',
              style: TextStyle(color: cs.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerTile extends ConsumerWidget {
  const _ServerTile({
    required this.entry,
    required this.isCurrent,
    required this.isConnected,
  });

  final ServerEntry entry;
  final bool isCurrent;
  final bool isConnected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final local = entry.type == ServerType.local;
    final subtitle = local
        ? '${entry.host}:${entry.port} · 本地免密'
        : '${entry.host}:${entry.port} · 远程${entry.username == null ? '' : ' · ${entry.username}'}';
    return ListTile(
      leading: Icon(
        local ? Icons.computer : Icons.dns_outlined,
        color: cs.primary,
      ),
      title: Row(
        children: [
          Flexible(child: Text(entry.name, overflow: TextOverflow.ellipsis)),
          if (isConnected) ...[
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green,
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '$subtitle${isCurrent ? (isConnected ? ' · 已连接' : ' · 当前') : ''}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isConnected)
            IconButton(
              icon: const Icon(Icons.link_off),
              tooltip: '断开连接',
              onPressed: () =>
                  ref.read(serverServiceProvider).disconnect(),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除服务器',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      onTap: () async {
        final notifier = ref.read(serverServiceProvider);
        final toast = ScaffoldMessenger.of(context);
        try {
          await notifier.connectTo(entry);
          await ref.read(currentServerIdProvider.notifier).set(entry.id);
          toast.showSnackBar(const SnackBar(content: Text('已连接服务器')));
        } on ServerException catch (e) {
          toast.showSnackBar(SnackBar(content: Text(e.message)));
        }
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${entry.name}'),
        content: const Text('删除后将不再显示该服务器(不会影响 daemon 端数据)。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(serverListProvider.notifier).remove(entry.id);
    final current = ref.read(currentServerIdProvider);
    if (current == entry.id) {
      ref.read(serverServiceProvider).disconnect();
      await ref.read(currentServerIdProvider.notifier).set(null);
    }
  }
}
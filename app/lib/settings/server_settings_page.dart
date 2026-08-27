import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../server/server_entry.dart';
import '../server/server_service.dart';

/// 服务器管理页:单选列表管理连接。
/// - 打开时若无连接,默认自动连接上一次最后连接的服务器;
/// - 单选标记当前连接的服务器,点击其他条目即切换连接(同一时间仅一台);
/// - 支持添加/删除服务器。
class ServerSettingsPage extends ConsumerStatefulWidget {
  const ServerSettingsPage({super.key});

  @override
  ConsumerState<ServerSettingsPage> createState() =>
      _ServerSettingsPageState();
}

class _ServerSettingsPageState extends ConsumerState<ServerSettingsPage> {
  /// 正在连接的服务器 id(用于行内转圈与防重入)
  String? _connectingId;

  @override
  void initState() {
    super.initState();
    // 打开页面且未连接时,默认连接上次最后连接的服务器
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoConnectLast());
  }

  Future<void> _autoConnectLast() async {
    if (!mounted) return;
    final ref = this.ref;
    if (ref.read(sessionProvider) != null) return;
    final servers = ref.read(serverListProvider);
    if (servers.isEmpty) return;

    final lastId = ref.read(currentServerIdProvider);
    ServerEntry? target;
    for (final e in servers) {
      if (e.id == lastId) {
        target = e;
        break;
      }
    }
    await _connect(target ?? servers.first);
  }

  Future<void> _connect(ServerEntry entry) async {
    if (!mounted || _connectingId != null) return;
    if (ref.read(sessionProvider)?.serverId == entry.id) return; // 已是当前连接

    setState(() => _connectingId = entry.id);
    final toast = ScaffoldMessenger.of(context);
    try {
      await ref.read(serverServiceProvider).connectTo(entry);
      if (!mounted) return;
      toast.showSnackBar(SnackBar(content: Text('已连接 ${entry.name}')));
    } on ServerException catch (e) {
      if (!mounted) return;
      toast.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _connectingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(serverListProvider);
    final session = ref.watch(sessionProvider);
    final connectedId = session?.serverId;
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
          : RadioGroup<String?>(
              groupValue: connectedId,
              onChanged: (value) {
                if (value == null) return;
                for (final e in servers) {
                  if (e.id == value) {
                    _connect(e);
                    break;
                  }
                }
              },
              child: ListView(
                children: [
                  for (final entry in servers)
                    _ServerTile(
                      entry: entry,
                      groupValue: connectedId,
                      connecting: _connectingId == entry.id,
                      onSelect: () => _connect(entry),
                    ),
                ],
              ),
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
    required this.groupValue,
    required this.connecting,
    required this.onSelect,
  });

  final ServerEntry entry;
  final String? groupValue;
  final bool connecting;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final local = entry.type == ServerType.local;
    final connected = groupValue == entry.id;
    final subtitle = local
        ? '${entry.host}:${entry.port} · 本地免密'
        : '${entry.host}:${entry.port} · 远程${entry.username == null ? '' : ' · ${entry.username}'}';

    return ListTile(
      leading: Radio<String?>(value: entry.id),
      title: Row(
        children: [
          Flexible(child: Text(entry.name, overflow: TextOverflow.ellipsis)),
          if (connected) ...[
            const SizedBox(width: 8),
            Text('已连接', style: TextStyle(fontSize: 12, color: cs.primary)),
          ],
        ],
      ),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (connecting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除服务器',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      enabled: !connecting,
      onTap: onSelect,
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
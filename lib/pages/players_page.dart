import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../instance/instance.dart';
import '../instance/instance_scope.dart';
import '../server/server_controller.dart';
import '../server/server_scope.dart';

/// 玩家管理页：在线玩家、白名单、封禁名单、OP 名单的可视化管理。
class PlayersPage extends StatefulWidget {
  const PlayersPage({super.key});

  @override
  State<PlayersPage> createState() => _PlayersPageState();
}

class _PlayersPageState extends State<PlayersPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final instance = InstanceScope.of(context).selected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('玩家管理'),
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: '在线'),
            Tab(text: '白名单'),
            Tab(text: '封禁'),
            Tab(text: 'OP'),
          ],
        ),
      ),
      body: instance == null
          ? const Center(child: Text('请先在「服务器」页选择一个实例。'))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _OnlineTab(instance: instance),
                _WhitelistTab(instance: instance),
                _BansTab(instance: instance),
                _OpsTab(instance: instance),
              ],
            ),
    );
  }
}

// ───────────────────────────── 在线玩家 ─────────────────────────────

class _OnlineTab extends StatefulWidget {
  const _OnlineTab({required this.instance});
  final Instance instance;

  @override
  State<_OnlineTab> createState() => _OnlineTabState();
}

class _OnlineTabState extends State<_OnlineTab> {
  Set<String> _whitelist = {};
  Set<String> _ops = {};
  Set<String> _bans = {};

  @override
  void initState() {
    super.initState();
    _loadContextSets();
  }

  Future<void> _loadContextSets() async {
    final dir =
        await InstanceScope.of(context).directoryFor(widget.instance);
    Set<String> loadNames(String fileName, List<dynamic> json) {
      return json.map((e) => (e['name'] as String? ?? '').toLowerCase()).toSet();
    }
    Set<String> loadFile(String fileName) {
      try {
        final file = File(p.join(dir.path, fileName));
        if (!file.existsSync()) return {};
        final json = jsonDecode(file.readAsStringSync()) as List;
        return loadNames(fileName, json);
      } catch (_) {
        return {};
      }
    }
    setState(() {
      _whitelist = loadFile('whitelist.json');
      _ops = loadFile('ops.json');
      _bans = loadFile('banned-players.json');
    });
  }

  @override
  Widget build(BuildContext context) {
    final server = ServerScope.of(context);
    final theme = Theme.of(context);
    final running = server.isRunning && server.isActive(widget.instance.id);
    final players = server.onlinePlayers.toList()..sort();

    final Widget body;
    if (!running) {
      body = _emptyState(theme, Icons.power_settings_new, '服务端未运行',
          '启动服务器后，在线玩家将自动显示在这里。');
    } else if (players.isEmpty) {
      body = _emptyState(theme, Icons.person_off, '暂无在线玩家',
          '等待玩家加入服务器…');
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: players.length,
        itemBuilder: (ctx, i) {
          final name = players[i];
          final lower = name.toLowerCase();
          final inWhitelist = _whitelist.contains(lower);
          final isOp = _ops.contains(lower);
          final isBanned = _bans.contains(lower);
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  name[0].toUpperCase(),
                  style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(name),
              subtitle: Row(
                children: [
                  if (isOp)
                    _PlayerTag(label: 'OP', color: theme.colorScheme.tertiary),
                  if (inWhitelist)
                    _PlayerTag(label: '白名单', color: theme.colorScheme.primary),
                  if (isBanned)
                    _PlayerTag(label: '已封禁', color: theme.colorScheme.error),
                ],
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (action) =>
                    _handleAction(context, server, name, action),
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'kick',
                    child: ListTile(
                      leading: Icon(Icons.exit_to_app,
                          color: theme.colorScheme.error),
                      title: const Text('踢出'),
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: inWhitelist ? 'wl_remove' : 'wl_add',
                    child: ListTile(
                      leading: Icon(
                        inWhitelist ? Icons.delete : Icons.how_to_reg_outlined,
                        color: inWhitelist
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                      title: Text(inWhitelist ? '移出白名单' : '加入白名单'),
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  PopupMenuItem(
                    value: isOp ? 'deop' : 'op',
                    child: ListTile(
                      leading: Icon(
                        isOp ? Icons.delete : Icons.admin_panel_settings,
                        color: isOp
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                      title: Text(isOp ? '取消 OP' : '给予 OP'),
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'ban',
                    child: ListTile(
                      leading: Icon(Icons.block,
                          color: theme.colorScheme.error),
                      title: const Text('封禁'),
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return Column(
      children: [
        _ListHeader(
          title: '在线（${running ? players.length : 0}）',
          tooltip: '刷新（发送 list）',
          onRefresh: running
              ? () {
                  server.sendCommand('list');
                  _loadContextSets();
                }
              : null,
        ),
        Expanded(child: body),
      ],
    );
  }

  void _handleAction(
      BuildContext context, ServerController server, String name, String action) async {
    switch (action) {
      case 'kick':
        _confirmKick(context, server, name);
      case 'wl_add':
        server.sendCommand('whitelist add $name');
        _delayedRefresh();
      case 'wl_remove':
        server.sendCommand('whitelist remove $name');
        _delayedRefresh();
      case 'op':
        server.sendCommand('op $name');
        _delayedRefresh();
      case 'deop':
        server.sendCommand('deop $name');
        _delayedRefresh();
      case 'ban':
        _confirmBan(context, server, name);
    }
  }

  void _delayedRefresh() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _loadContextSets();
    });
  }

  Future<void> _confirmKick(
      BuildContext context, ServerController server, String name) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: Text('踢出 $name'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: '踢出原因（可选）',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('踢出'),
            ),
          ],
        );
      },
    );
    if (reason == null) return;
    final cmd = reason.isEmpty ? 'kick $name' : 'kick $name $reason';
    server.sendCommand(cmd);
  }

  Future<void> _confirmBan(
      BuildContext context, ServerController server, String name) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: Text('封禁 $name'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: '封禁原因（可选）',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('封禁'),
            ),
          ],
        );
      },
    );
    if (reason == null) return;
    final cmd = reason.isEmpty ? 'ban $name' : 'ban $name $reason';
    server.sendCommand(cmd);
    _delayedRefresh();
  }
}

// ───────────────────────────── 白名单 ─────────────────────────────

class _WhitelistTab extends StatefulWidget {
  const _WhitelistTab({required this.instance});
  final Instance instance;

  @override
  State<_WhitelistTab> createState() => _WhitelistTabState();
}

class _WhitelistTabState extends State<_WhitelistTab> {
  Future<List<_NamedEntry>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _loadWhitelist();
  }

  Future<List<_NamedEntry>> _loadWhitelist() async {
    final dir =
        await InstanceScope.of(context).directoryFor(widget.instance);
    final file = File(p.join(dir.path, 'whitelist.json'));
    if (!await file.exists()) return [];
    try {
      final json = jsonDecode(await file.readAsString()) as List;
      return json
          .map((e) => _NamedEntry(
                name: e['name'] as String? ?? '',
                uuid: e['uuid'] as String? ?? '',
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _refresh() => setState(() => _future = _loadWhitelist());

  @override
  Widget build(BuildContext context) {
    final server = ServerScope.of(context);
    final running = server.isRunning && server.isActive(widget.instance.id);
    final theme = Theme.of(context);

    return FutureBuilder<List<_NamedEntry>>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snap.data ?? [];
        return Column(
          children: [
            _ListHeader(
              title: '白名单（${entries.length}）',
              tooltip: '刷新',
              onRefresh: _refresh,
              actionLabel: '添加',
              actionIcon: Icons.add,
              onAction: running
                  ? () => _promptAndSend(
                        context, server,
                        title: '添加白名单',
                        hint: '玩家名称',
                        commandPrefix: 'whitelist add',
                        onDone: _refresh,
                      )
                  : null,
            ),
            if (!running)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  '只读模式，启动服务端后可进行操作',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            Expanded(
              child: entries.isEmpty
                  ? _emptyState(theme, Icons.how_to_reg, '白名单为空',
                      '点击上方「添加」按钮加入玩家。')
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: entries.length,
                      itemBuilder: (ctx, i) {
                        final e = entries[i];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.secondaryContainer,
                              child: Text(e.name[0].toUpperCase(),
                                  style: TextStyle(
                                      color: theme
                                          .colorScheme.onSecondaryContainer,
                                      fontWeight: FontWeight.bold)),
                            ),
                            title: Text(e.name),
                            subtitle: e.uuid.isNotEmpty
                                ? Text(e.uuid,
                                    style: theme.textTheme.bodySmall)
                                : null,
                            trailing: running
                                ? IconButton(
                                    icon: Icon(Icons.delete,
                                        color: theme.colorScheme.error),
                                    tooltip: '移除',
                                    onPressed: () {
                                      server.sendCommand(
                                          'whitelist remove ${e.name}');
                                      _refresh();
                                    },
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ───────────────────────────── 封禁 ─────────────────────────────

class _BansTab extends StatefulWidget {
  const _BansTab({required this.instance});
  final Instance instance;

  @override
  State<_BansTab> createState() => _BansTabState();
}

class _BansTabState extends State<_BansTab> {
  Future<List<_BanEntry>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _loadBans();
  }

  Future<List<_BanEntry>> _loadBans() async {
    final dir =
        await InstanceScope.of(context).directoryFor(widget.instance);
    final file = File(p.join(dir.path, 'banned-players.json'));
    if (!await file.exists()) return [];
    try {
      final json = jsonDecode(await file.readAsString()) as List;
      return json
          .map((e) => _BanEntry(
                name: e['name'] as String? ?? '',
                uuid: e['uuid'] as String? ?? '',
                reason: e['reason'] as String? ?? '',
                source: e['source'] as String? ?? '',
                expires: e['expires'] as String? ?? '',
                created: e['created'] as String? ?? '',
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _refresh() => setState(() => _future = _loadBans());

  @override
  Widget build(BuildContext context) {
    final server = ServerScope.of(context);
    final running = server.isRunning && server.isActive(widget.instance.id);
    final theme = Theme.of(context);

    return FutureBuilder<List<_BanEntry>>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snap.data ?? [];
        return Column(
          children: [
            _ListHeader(
              title: '封禁名单（${entries.length}）',
              tooltip: '刷新',
              onRefresh: _refresh,
              actionLabel: '封禁',
              actionIcon: Icons.add,
              onAction: running
                  ? () => _promptAndSend(
                        context, server,
                        title: '封禁玩家',
                        hint: '玩家名称',
                        commandPrefix: 'ban',
                        onDone: _refresh,
                        withReason: true,
                      )
                  : null,
            ),
            if (!running)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  '只读模式，启动服务端后可进行操作',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            Expanded(
              child: entries.isEmpty
                  ? _emptyState(theme, Icons.check_circle_outline, '暂无封禁',
                      '没有被封禁的玩家。')
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: entries.length,
                      itemBuilder: (ctx, i) {
                        final e = entries[i];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: theme.colorScheme.errorContainer,
                              child: Icon(Icons.block,
                                  color: theme.colorScheme.onErrorContainer,
                                  size: 20),
                            ),
                            title: Text(e.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (e.reason.isNotEmpty && e.reason != 'Banned by an operator.')
                                  Text('原因：${e.reason}',
                                      style: theme.textTheme.bodySmall),
                                if (e.expires.isNotEmpty && e.expires != 'forever')
                                  Text('到期：${e.expires}',
                                      style: theme.textTheme.bodySmall),
                                if (e.uuid.isNotEmpty)
                                  Text(e.uuid,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(fontSize: 10)),
                              ],
                            ),
                            trailing: running
                                ? IconButton(
                                    icon: Icon(Icons.delete,
                                        color: theme.colorScheme.primary),
                                    tooltip: '解封',
                                    onPressed: () {
                                      server
                                          .sendCommand('pardon ${e.name}');
                                      _refresh();
                                    },
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ───────────────────────────── OP ─────────────────────────────

class _OpsTab extends StatefulWidget {
  const _OpsTab({required this.instance});
  final Instance instance;

  @override
  State<_OpsTab> createState() => _OpsTabState();
}

class _OpsTabState extends State<_OpsTab> {
  Future<List<_NamedEntry>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _loadOps();
  }

  Future<List<_NamedEntry>> _loadOps() async {
    final dir =
        await InstanceScope.of(context).directoryFor(widget.instance);
    final file = File(p.join(dir.path, 'ops.json'));
    if (!await file.exists()) return [];
    try {
      final json = jsonDecode(await file.readAsString()) as List;
      return json
          .map((e) => _NamedEntry(
                name: e['name'] as String? ?? '',
                uuid: e['uuid'] as String? ?? '',
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _refresh() => setState(() => _future = _loadOps());

  @override
  Widget build(BuildContext context) {
    final server = ServerScope.of(context);
    final running = server.isRunning && server.isActive(widget.instance.id);
    final theme = Theme.of(context);

    return FutureBuilder<List<_NamedEntry>>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snap.data ?? [];
        return Column(
          children: [
            _ListHeader(
              title: 'OP 列表（${entries.length}）',
              tooltip: '刷新',
              onRefresh: _refresh,
              actionLabel: '添加',
              actionIcon: Icons.add,
              onAction: running
                  ? () => _promptAndSend(
                        context, server,
                        title: '添加 OP',
                        hint: '玩家名称',
                        commandPrefix: 'op',
                        onDone: _refresh,
                      )
                  : null,
            ),
            if (!running)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  '只读模式，启动服务端后可进行操作',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            Expanded(
              child: entries.isEmpty
                  ? _emptyState(theme, Icons.security, '暂无 OP',
                      '点击上方「添加」按钮授予玩家管理权限。')
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: entries.length,
                      itemBuilder: (ctx, i) {
                        final e = entries[i];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: theme.colorScheme.tertiaryContainer,
                              child: Icon(Icons.star,
                                  color: theme.colorScheme.onTertiaryContainer,
                                  size: 20),
                            ),
                            title: Text(e.name),
                            subtitle: e.uuid.isNotEmpty
                                ? Text(e.uuid,
                                    style: theme.textTheme.bodySmall)
                                : null,
                            trailing: running
                                ? IconButton(
                                    icon: Icon(Icons.delete,
                                        color: theme.colorScheme.error),
                                    tooltip: '取消 OP',
                                    onPressed: () {
                                      server
                                          .sendCommand('deop ${e.name}');
                                      _refresh();
                                    },
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ───────────────────────────── 通用组件 ─────────────────────────────

/// 玩家状态标签（用于在线玩家列表中显示 OP/白名单等状态）。
class _PlayerTag extends StatelessWidget {
  const _PlayerTag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// 列表头部：标题 + 刷新 + 操作按钮。
class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.title,
    required this.tooltip,
    required this.onRefresh,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final String title;
  final String tooltip;

  /// 刷新回调；为 null 时刷新按钮禁用（如在线页未运行时）。
  final VoidCallback? onRefresh;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: tooltip,
            onPressed: onRefresh,
          ),
          if (actionIcon != null)
            IconButton(
              icon: Icon(actionIcon, size: 20),
              tooltip: actionLabel,
              onPressed: onAction,
            ),
        ],
      ),
    );
  }
}

/// 空白占位状态。
Widget _emptyState(ThemeData theme, IconData icon, String title, String desc) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            desc,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    ),
  );
}

/// 弹出输入对话框，发送命令并回调刷新。
Future<void> _promptAndSend(
  BuildContext context,
  ServerController server, {
  required String title,
  required String hint,
  required String commandPrefix,
  required VoidCallback onDone,
  bool withReason = false,
}) async {
  final nameCtrl = TextEditingController();
  final reasonCtrl = TextEditingController();
  final result = await showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: hint,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                if (withReason) {
                  // 有原因字段时，不在此处提交
                } else {
                  Navigator.of(ctx).pop({'name': nameCtrl.text.trim()});
                }
              },
            ),
            if (withReason) ...[
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: '原因（可选）',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => Navigator.of(ctx).pop({
                  'name': nameCtrl.text.trim(),
                  'reason': reasonCtrl.text.trim(),
                }),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop({
              'name': nameCtrl.text.trim(),
              if (withReason) 'reason': reasonCtrl.text.trim(),
            }),
            child: const Text('确定'),
          ),
        ],
      );
    },
  );
  nameCtrl.dispose();
  reasonCtrl.dispose();
  if (result == null || result['name']!.isEmpty) return;
  final name = result['name']!;
  final reason = result['reason'] ?? '';
  final cmd = reason.isEmpty ? '$commandPrefix $name' : '$commandPrefix $name $reason';
  server.sendCommand(cmd);
  // 延迟刷新，给服务端处理时间
  Future.delayed(const Duration(milliseconds: 500), onDone);
}

// ───────────────────────────── 数据模型 ─────────────────────────────

class _NamedEntry {
  const _NamedEntry({required this.name, required this.uuid});
  final String name;
  final String uuid;
}

class _BanEntry {
  const _BanEntry({
    required this.name,
    required this.uuid,
    required this.reason,
    required this.source,
    required this.expires,
    required this.created,
  });
  final String name;
  final String uuid;
  final String reason;
  final String source;
  final String expires;
  final String created;
}

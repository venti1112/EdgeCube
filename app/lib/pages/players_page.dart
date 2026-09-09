import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../server/server_service.dart';
import 'api_error.dart';
import 'current_instance.dart';

/// 玩家管理页(移植自 V1 `players_page.dart`,布局对齐;UI 使用 material_ui):
/// 5 个 Tab(在线玩家 / 白名单 / 封禁 / IP 封禁 / OP)。
///
/// 数据源为聚合快照 `GET /instances/{id}/players`(在线玩家由 daemon 解析
/// 控制台输出维护,四类名单读实例 cwd 文件),3 秒轮询;增删操作复用
/// `POST /instances/{id}/command` 下发命令,仅运行时可操作(未运行只读提示)。
class PlayersPage extends ConsumerStatefulWidget {
  const PlayersPage({super.key});

  @override
  ConsumerState<PlayersPage> createState() => _PlayersPageState();
}

class _PlayersPageState extends ConsumerState<PlayersPage>
    with SingleTickerProviderStateMixin {
  static const _pollInterval = Duration(seconds: 3);

  late final TabController _tabCtrl;
  Timer? _timer;

  String? _instanceId;
  PlayerSnapshot? _snapshot;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _load();
    _timer = Timer.periodic(_pollInterval, (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabCtrl.dispose();
    super.dispose();
  }

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  Future<void> _load({bool silent = false}) async {
    final client = _client;
    final instance = ref.read(currentInstanceProvider);
    final id = instance?.id;
    if (client == null || id == null) {
      if (!silent && mounted) setState(() => _loading = false);
      return;
    }
    if (!silent) setState(() => _loading = true);
    try {
      final snap =
          (await client.getPlayersApi().getInstancePlayers(instanceId: id))
              .data!;
      if (!mounted) return;
      setState(() {
        _instanceId = id;
        _snapshot = snap;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 发送控制台命令(经 /command,仅运行时可调);成功后延迟重拉快照
  /// (对齐 V1 `_delayedRefresh` 500ms)。
  Future<void> _sendCommand(String command) async {
    final client = _client;
    final id = _instanceId;
    if (client == null || id == null) return;
    try {
      await client.getInstancesApi().sendInstanceCommand(
            instanceId: id,
            commandRequest: CommandRequest((b) => b.command = command),
          );
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _load(silent: true);
      });
    } on DioException catch (e) {
      _snack(apiErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final instance = ref.watch(currentInstanceProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('玩家管理'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: '在线玩家'),
            Tab(text: '白名单'),
            Tab(text: '封禁'),
            Tab(text: 'IP 封禁'),
            Tab(text: 'OP'),
          ],
        ),
      ),
      body: _buildBody(instance?.id),
    );
  }

  Widget _buildBody(String? instanceId) {
    if (instanceId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_outline, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('未选择实例', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      );
    }
    if (_loading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_snapshot == null) {
      return _errorView();
    }
    final snap = _snapshot!;
    final running = snap.instanceStatus == InstanceStatus.running;

    return TabBarView(
      controller: _tabCtrl,
      children: [
        _OnlineTab(
          snapshot: snap,
          running: running,
          onCommand: _sendCommand,
        ),
        _NamedListTab(
          title: '白名单',
          entries: snap.whitelist,
          running: running,
          avatarColor: Theme.of(context).colorScheme.secondaryContainer,
          avatarTextColor: Theme.of(context).colorScheme.onSecondaryContainer,
          emptyIcon: Icons.how_to_reg,
          emptyDesc: '开启白名单后,只有名单中的玩家可以加入服务器。',
          addCommandPrefix: 'whitelist add',
          removeCommandPrefix: 'whitelist remove',
          onCommand: _sendCommand,
        ),
        _BansTab(
          snapshot: snap,
          running: running,
          onCommand: _sendCommand,
        ),
        _BanIpsTab(
          snapshot: snap,
          running: running,
          onCommand: _sendCommand,
        ),
        _NamedListTab(
          title: 'OP',
          entries: snap.ops,
          running: running,
          avatarColor: Theme.of(context).colorScheme.tertiaryContainer,
          avatarTextColor: Theme.of(context).colorScheme.onTertiaryContainer,
          emptyIcon: Icons.security,
          emptyDesc: 'OP 玩家拥有管理权限,可执行管理员命令。',
          addCommandPrefix: 'op',
          removeCommandPrefix: 'deop',
          onCommand: _sendCommand,
        ),
      ],
    );
  }

  Widget _errorView() {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.cloud_off, size: 56, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Center(child: Text('加载失败:${_error ?? '(未知错误)'}')),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
            child: const Text('重试'),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────── 通用组件 ─────────────────────────────

/// 列表头部:标题(带数量) + 刷新 + 可选添加按钮(对齐 V1 `_ListHeader`)。
class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.title, this.onRefresh, this.onAdd});

  final String title;
  final VoidCallback? onRefresh;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          IconButton(
            tooltip: '刷新',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 20),
          ),
          if (onAdd != null)
            IconButton(
              tooltip: '添加',
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 20),
            ),
        ],
      ),
    );
  }
}

/// 空白占位状态(对齐 V1 `_emptyState`:图标 + 标题 + 描述)。
Widget _emptyState(BuildContext context, IconData icon, String title, String desc) {
  final cs = Theme.of(context).colorScheme;
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            desc,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    ),
  );
}

/// 玩家状态标签(对齐 V1 `_PlayerTag`:圆角描边小签)。
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

/// 添加玩家对话框(对齐 V1 `_promptAndSend`;可选原因字段)。
class _PromptResult {
  const _PromptResult(this.name, this.reason);

  final String name;
  final String? reason;
}

Future<_PromptResult?> _promptAndSend(
  BuildContext context, {
  required String title,
  required String hint,
  String? reasonHint,
}) {
  final nameCtrl = TextEditingController();
  final reasonCtrl = TextEditingController();
  return showDialog<_PromptResult>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title, textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: hint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (reasonHint != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: InputDecoration(
                  labelText: reasonHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              nameCtrl.dispose();
              reasonCtrl.dispose();
              Navigator.pop(ctx);
            },
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final reason = reasonCtrl.text.trim();
              nameCtrl.dispose();
              reasonCtrl.dispose();
              if (name.isEmpty) return;
              Navigator.pop(
                ctx,
                _PromptResult(name, reason.isEmpty ? null : reason),
              );
            },
            child: const Text('确认'),
          ),
        ],
      );
    },
  );
}

// ───────────────────────────── 在线玩家 ─────────────────────────────

/// 在线玩家 Tab:玩家名列表 + 状态标签 + 行尾下拉菜单(踢出/白名单/OP/封禁)。
class _OnlineTab extends StatefulWidget {
  const _OnlineTab({
    required this.snapshot,
    required this.running,
    required this.onCommand,
  });

  final PlayerSnapshot snapshot;
  final bool running;
  final Future<void> Function(String command) onCommand;

  @override
  State<_OnlineTab> createState() => _OnlineTabState();
}

class _OnlineTabState extends State<_OnlineTab> {
  /// 本地重载版本:操作后 +1 触发重建读取最新快照(对齐 V1 `_delayedRefresh`)。
  int _dataVersion = 0;
  final Set<String> _whitelist = {};
  final Set<String> _ops = {};
  final Set<String> _bans = {};

  @override
  void didUpdateWidget(covariant _OnlineTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot != widget.snapshot) {
      _whitelist
        ..clear()
        ..addAll(widget.snapshot.whitelist.map((e) => e.name.toLowerCase()));
      _ops
        ..clear()
        ..addAll(widget.snapshot.ops.map((e) => e.name.toLowerCase()));
      _bans
        ..clear()
        ..addAll(widget.snapshot.bans.map((e) => e.name.toLowerCase()));
    }
  }

  void _bump() => setState(() => _dataVersion++);

  @override
  Widget build(BuildContext context) {
    final players = widget.snapshot.online.toList()..sort();
    final cs = Theme.of(context).colorScheme;

    final Widget body;
    if (!widget.running) {
      body = _emptyState(
        context,
        Icons.power_settings_new,
        '实例未运行',
        '启动实例后才能在游戏中查看在线玩家。',
      );
    } else if (players.isEmpty) {
      body = _emptyState(
        context,
        Icons.person_off,
        '暂无在线玩家',
        '等待玩家加入服务器。',
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: players.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final name = players[i];
          final lower = name.toLowerCase();
          final inWhitelist = _whitelist.contains(lower);
          final isOp = _ops.contains(lower);
          final isBanned = _bans.contains(lower);
          return Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Text(
                  name[0].toUpperCase(),
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(name),
              subtitle: Row(
                children: [
                  if (isOp)
                    _PlayerTag(label: 'OP', color: cs.onTertiaryContainer),
                  if (inWhitelist) _PlayerTag(label: '白名单', color: cs.primary),
                  if (isBanned) _PlayerTag(label: '封禁', color: cs.error),
                ],
              ),
              trailing: PopupMenuButton<_OnlineAction>(
                onSelected: (action) =>
                    _handleAction(context, name, inWhitelist, isOp, action),
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: _OnlineAction.kick,
                    child: Text('踢出'),
                  ),
                  PopupMenuItem(
                    value: inWhitelist
                        ? _OnlineAction.wlRemove
                        : _OnlineAction.wlAdd,
                    child: Text(inWhitelist ? '移出白名单' : '加入白名单'),
                  ),
                  PopupMenuItem(
                    value: isOp ? _OnlineAction.deop : _OnlineAction.op,
                    child: Text(isOp ? '取消 OP' : '设为 OP'),
                  ),
                  const PopupMenuItem(
                    value: _OnlineAction.ban,
                    child: Text('封禁'),
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
          title: '在线玩家(${widget.running ? players.length : 0})',
          onRefresh: widget.running
              ? () {
                  widget.onCommand('list');
                  Future.delayed(
                      const Duration(milliseconds: 300), _bump);
                }
              : null,
        ),
        Expanded(child: body),
      ],
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    String name,
    bool inWhitelist,
    bool isOp,
    _OnlineAction action,
  ) async {
    switch (action) {
      case _OnlineAction.kick:
        await _confirmWithReason(
          context,
          title: '踢出 $name',
          hint: '踢出原因(可选)',
          commandPrefix: 'kick $name',
          onCommand: widget.onCommand,
          onDone: _bump,
        );
      case _OnlineAction.wlAdd:
        await widget.onCommand('whitelist add $name');
        _bump();
      case _OnlineAction.wlRemove:
        await widget.onCommand('whitelist remove $name');
        _bump();
      case _OnlineAction.op:
        await widget.onCommand('op $name');
        _bump();
      case _OnlineAction.deop:
        await widget.onCommand('deop $name');
        _bump();
      case _OnlineAction.ban:
        await _confirmWithReason(
          context,
          title: '封禁 $name',
          hint: '封禁原因(可选)',
          commandPrefix: 'ban $name',
          onCommand: widget.onCommand,
          onDone: _bump,
        );
    }
  }
}

enum _OnlineAction { kick, wlAdd, wlRemove, op, deop, ban }

// ───────────────────────────── 白名单 / OP ─────────────────────────────

/// 名称名单 Tab(白名单与 OP 共用):头像 + 名字 + uuid 小字 + 行尾删除;
/// 未运行只读(提示 + 禁用添加/删除)。添加经 `_promptAndSend` 对话框。
class _NamedListTab extends StatefulWidget {
  const _NamedListTab({
    required this.title,
    required this.entries,
    required this.running,
    required this.avatarColor,
    required this.avatarTextColor,
    required this.emptyIcon,
    required this.emptyDesc,
    required this.addCommandPrefix,
    required this.removeCommandPrefix,
    required this.onCommand,
  });

  final String title;
  final BuiltList<PlayerNamedEntry> entries;
  final bool running;
  final Color avatarColor;
  final Color avatarTextColor;
  final IconData emptyIcon;
  final String emptyDesc;
  final String addCommandPrefix;
  final String removeCommandPrefix;
  final Future<void> Function(String command) onCommand;

  @override
  State<_NamedListTab> createState() => _NamedListTabState();
}

class _NamedListTabState extends State<_NamedListTab> {
  int _dataVersion = 0;

  void _bump() => setState(() => _dataVersion++);

  @override
  Widget build(BuildContext context) {
    final list = widget.entries.toList();

    final Widget body;
    if (list.isEmpty) {
      body = _emptyState(
        context,
        widget.emptyIcon,
        '暂无${widget.title}',
        widget.emptyDesc,
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final e = list[i];
          final uuid = e.uuid ?? '';
          return Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: widget.avatarColor,
                child: Text(
                  e.name[0].toUpperCase(),
                  style: TextStyle(
                    color: widget.avatarTextColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(e.name),
              subtitle: uuid.isNotEmpty ? Text(uuid) : null,
              trailing: widget.running
                  ? IconButton(
                      tooltip: '删除',
                      onPressed: () async {
                        await widget
                            .onCommand('${widget.removeCommandPrefix} ${e.name}');
                        _bump();
                      },
                      icon: const Icon(Icons.delete),
                    )
                  : null,
            ),
          );
        },
      );
    }

    return Column(
      children: [
        _ListHeader(
          title: '${widget.title}(${list.length})',
          onRefresh: _bump,
          onAdd: widget.running ? () => _add(context) : null,
        ),
        if (!widget.running) _readonlyNote(context),
        Expanded(child: body),
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    final result = await _promptAndSend(
      context,
      title: '添加${widget.title}玩家',
      hint: '玩家名',
    );
    if (result == null) return;
    await widget.onCommand('${widget.addCommandPrefix} ${result.name}');
    _bump();
  }
}

// ───────────────────────────── 封禁 ─────────────────────────────

/// 封禁玩家 Tab:名字 + 原因/过期时间/uuid 小字 + 行尾解除(pardon);
/// 添加经 `ban <名> [原因]` 对话框。
class _BansTab extends StatefulWidget {
  const _BansTab({
    required this.snapshot,
    required this.running,
    required this.onCommand,
  });

  final PlayerSnapshot snapshot;
  final bool running;
  final Future<void> Function(String command) onCommand;

  @override
  State<_BansTab> createState() => _BansTabState();
}

class _BansTabState extends State<_BansTab> {
  int _dataVersion = 0;

  void _bump() => setState(() => _dataVersion++);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = widget.snapshot.bans.toList();

    final Widget body;
    if (list.isEmpty) {
      body = _emptyState(
        context,
        Icons.check_circle_outline,
        '暂无封禁玩家',
        '被封禁的玩家将无法进入服务器。',
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final e = list[i];
          final uuid = e.uuid ?? '';
          final reason = e.reason ?? '';
          final expires = e.expires ?? '';
          return Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.errorContainer,
                child: Icon(Icons.block, size: 20, color: cs.onErrorContainer),
              ),
              title: Text(e.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (reason.isNotEmpty && reason != 'Banned by an operator.')
                    Text('原因:$reason'),
                  if (expires.isNotEmpty && expires.toLowerCase() != 'forever')
                    Text('到期:$expires'),
                  if (uuid.isNotEmpty) Text(uuid),
                ],
              ),
              trailing: widget.running
                  ? IconButton(
                      tooltip: '解除封禁',
                      onPressed: () async {
                        await widget.onCommand('pardon ${e.name}');
                        _bump();
                      },
                      icon: const Icon(Icons.delete),
                    )
                  : null,
            ),
          );
        },
      );
    }

    return Column(
      children: [
        _ListHeader(
          title: '封禁(${list.length})',
          onRefresh: _bump,
          onAdd: widget.running ? () => _add(context) : null,
        ),
        if (!widget.running) _readonlyNote(context),
        Expanded(child: body),
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    final result = await _promptAndSend(
      context,
      title: '封禁玩家',
      hint: '玩家名',
      reasonHint: '封禁原因(可选)',
    );
    if (result == null) return;
    final reason = result.reason;
    await widget.onCommand(
        reason == null ? 'ban ${result.name}' : 'ban ${result.name} $reason');
    _bump();
  }
}

// ───────────────────────────── IP 封禁 ─────────────────────────────

/// IP 封禁 Tab:IP + 原因小字 + 行尾解除(pardon-ip);
/// 添加经 `ban-ip <IP> [原因]` 对话框。
class _BanIpsTab extends StatefulWidget {
  const _BanIpsTab({
    required this.snapshot,
    required this.running,
    required this.onCommand,
  });

  final PlayerSnapshot snapshot;
  final bool running;
  final Future<void> Function(String command) onCommand;

  @override
  State<_BanIpsTab> createState() => _BanIpsTabState();
}

class _BanIpsTabState extends State<_BanIpsTab> {
  int _dataVersion = 0;

  void _bump() => setState(() => _dataVersion++);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = widget.snapshot.banIps.toList();

    final Widget body;
    if (list.isEmpty) {
      body = _emptyState(
        context,
        Icons.check_circle_outline,
        '暂无 IP 封禁',
        '被封禁的 IP 将无法连接服务器。',
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final e = list[i];
          final reason = e.reason ?? '';
          return Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.errorContainer,
                child: Icon(Icons.router, size: 20, color: cs.onErrorContainer),
              ),
              title: Text(e.ip),
              subtitle: reason.isNotEmpty ? Text('原因:$reason') : null,
              trailing: widget.running
                  ? IconButton(
                      tooltip: '解除封禁',
                      onPressed: () async {
                        await widget.onCommand('pardon-ip ${e.ip}');
                        _bump();
                      },
                      icon: const Icon(Icons.delete),
                    )
                  : null,
            ),
          );
        },
      );
    }

    return Column(
      children: [
        _ListHeader(
          title: 'IP 封禁(${list.length})',
          onRefresh: _bump,
          onAdd: widget.running ? () => _add(context) : null,
        ),
        if (!widget.running) _readonlyNote(context),
        Expanded(child: body),
      ],
    );
  }

  Future<void> _add(BuildContext context) async {
    final result = await _promptAndSend(
      context,
      title: '封禁 IP',
      hint: 'IP 地址',
      reasonHint: '封禁原因(可选)',
    );
    if (result == null) return;
    final reason = result.reason;
    await widget.onCommand(
        reason == null
            ? 'ban-ip ${result.name}'
            : 'ban-ip ${result.name} $reason');
    _bump();
  }
}

// ───────────────────────────── 只读提示 ─────────────────────────────

/// 未运行只读小字提示(对齐 V1 `players.readonlyNote`)。
Widget _readonlyNote(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Text(
      '实例未运行,名单为只读;启动实例后可编辑。',
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

/// 带原因确认对话框(kick / ban),原因可选(对齐 V1 `_confirmKick` / `_confirmBan`)。
Future<void> _confirmWithReason(
  BuildContext context, {
  required String title,
  required String hint,
  required String commandPrefix,
  required Future<void> Function(String command) onCommand,
  required VoidCallback onDone,
}) async {
  final result =
      await _promptAndSend(context, title: title, hint: hint);
  if (result == null) return;
  final reason = result.reason;
  await onCommand(reason == null ? commandPrefix : '$commandPrefix $reason');
  onDone();
}
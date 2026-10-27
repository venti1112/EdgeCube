import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/client.dart';
import '../instance/models.dart';
import '../instance/providers.dart';
import 'api.dart';
import 'models.dart';
import 'providers.dart';

/// 玩家管理页：在线玩家、白名单、封禁名单、IP 封禁与 OP 名单。
///
/// 数据两头都在 daemon：
///
/// * 五个标签页；没选中实例时只给一句提示；
/// * **在线玩家由 daemon 从控制台输出里解析**（进程归它管，输出流从头到尾一条
///   不漏），本页只订阅 `instance.players` 事件 + 拉一次快照；
/// * 白名单 / OP / 封禁 / IP 封禁也由 daemon 读盘（`instance.players.*`），
///   「JSON 优先、纯文本兜底」的规则在那边实现一次；
/// * 一切改动都靠**往控制台写命令**（`kick` / `whitelist add` / `ban`
///   / `pardon` …，`instance.console.write`）；
/// * 服务端没在运行时整页**只读**：加/删按钮都不给，几个名单页顶部另有一行说明。
class PlayersPage extends ConsumerStatefulWidget {
  const PlayersPage({super.key});

  @override
  ConsumerState<PlayersPage> createState() => _PlayersPageState();
}

class _PlayersPageState extends ConsumerState<PlayersPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// 选中实例的当前阶段（daemon 推回来的那份）。
  ServerPhase get _phase =>
      ref.read(selectedInstanceDetailProvider).value?.status.phase ??
      ServerPhase.stopped;

  /// 往控制台写一行命令（命令 + 实例配的行尾，daemon 原样写进 PTY）。
  ///
  /// 只有启动中 / 运行中 / 停止中才发；
  /// 换行符用实例自己配的那个（命令尾补上 `lineEnding`）。
  void _sendCommand(String line) {
    final instance = ref.read(selectedInstanceDetailProvider).value?.instance;
    final cmd = line.trim();
    if (instance == null || cmd.isEmpty) return;
    final phase = _phase;
    if (phase != ServerPhase.starting &&
        phase != ServerPhase.running &&
        phase != ServerPhase.stopping) {
      return;
    }
    unawaited(_write(instance.id, '$cmd${instance.lineEnding}'));
  }

  Future<void> _write(String instanceId, String data) async {
    final api = ref.read(playersApiProvider(instanceId));
    if (api == null) return;
    try {
      await api.consoleWrite(data);
    } on DaemonException catch (error) {
      // 进程刚好退下去 / 连接断了：命令没落地。守卫已经拦掉绝大多数情况，
      // 这点竞态不值得弹一个错误打断用户。
      debugPrint('控制台写入失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 订阅 instance.*：阶段变化要立刻反映成「能不能操作」（同「服务器」页）
    ref.watch(instanceEventsProvider);

    final detail = ref.watch(selectedInstanceDetailProvider).value;
    final instance = detail?.instance;
    final running = detail?.status.running ?? false;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('玩家管理'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '在线'),
            Tab(text: '白名单'),
            Tab(text: '封禁'),
            Tab(text: 'IP 封禁'),
            Tab(text: 'OP'),
          ],
        ),
      ),
      // 没选实例：正文里给一句提示，标签页照旧摆着
      body: instance == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('请先在「服务器」页选择一个实例。'),
              ),
            )
          : TabBarView(
              // 照「文件」页：换实例时整棵子树重建，各页的名单重新读一遍
              key: ValueKey(instance.id),
              controller: _tabs,
              children: [
                _OnlineTab(
                  instanceId: instance.id,
                  running: running,
                  send: _sendCommand,
                ),
                _WhitelistTab(
                  instanceId: instance.id,
                  running: running,
                  send: _sendCommand,
                ),
                _BansTab(
                  instanceId: instance.id,
                  running: running,
                  send: _sendCommand,
                ),
                _BanIpsTab(
                  instanceId: instance.id,
                  running: running,
                  send: _sendCommand,
                ),
                _OpsTab(
                  instanceId: instance.id,
                  running: running,
                  send: _sendCommand,
                ),
              ],
            ),
    );
  }
}

// ───────────────────────────── 在线玩家 ─────────────────────────────

/// 在线玩家页。
///
/// 名单来自 daemon（`onlinePlayersProvider`：快照 + `instance.players` 事件），
/// 这里只管展示、打标签与下命令；标签要的三张名单（白名单 / OP / 封禁）自己拉
/// 一遍，命令发出去 500 ms 后重拉 —— 服务端落盘要一点时间。
class _OnlineTab extends ConsumerStatefulWidget {
  const _OnlineTab({
    required this.instanceId,
    required this.running,
    required this.send,
  });

  final String instanceId;
  final bool running;
  final void Function(String line) send;

  @override
  ConsumerState<_OnlineTab> createState() => _OnlineTabState();
}

class _OnlineTabState extends ConsumerState<_OnlineTab> {
  Set<String> _whitelist = {};
  Set<String> _ops = {};
  Set<String> _bans = {};

  @override
  void initState() {
    super.initState();
    // 读 Provider 不能放在 initState 里，推到首帧之后
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadContextSets());
  }

  Future<void> _loadContextSets() async {
    final api = ref.read(playersApiProvider(widget.instanceId));
    if (api == null) return;
    final PlayerContextSets sets;
    try {
      sets = await api.contextSets();
    } on DaemonException {
      // 断线：整页本来就是「未运行」态，标签不打也罢
      return;
    }
    if (!mounted) return;
    setState(() {
      _whitelist = sets.whitelist;
      _ops = sets.ops;
      _bans = sets.bans;
    });
  }

  /// 命令发出去 500 ms 再重读名单：服务端落盘要一点时间。
  void _delayedRefresh() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _loadContextSets();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final players = ref.watch(onlinePlayersProvider(widget.instanceId));
    final running = widget.running;

    final Widget body;
    if (!running) {
      body = _emptyState(
        theme,
        Icons.power_settings_new,
        '服务端未运行',
        '启动服务器后，在线玩家将自动显示在这里。',
      );
    } else if (players.isEmpty) {
      body = _emptyState(
        theme,
        Icons.person_off,
        '暂无在线玩家',
        '等待玩家加入服务器…',
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: players.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final name = players[index];
          final lower = name.toLowerCase();
          final inWhitelist = _whitelist.contains(lower);
          final isOp = _ops.contains(lower);
          final isBanned = _bans.contains(lower);
          return Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              key: Key('player_row_$name'),
              leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  _initial(name),
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(name),
              subtitle: Row(
                children: [
                  if (isOp) _PlayerTag(label: 'OP', color: scheme.onTertiaryContainer),
                  if (inWhitelist) _PlayerTag(label: '白名单', color: scheme.primary),
                  if (isBanned) _PlayerTag(label: '已封禁', color: scheme.error),
                ],
              ),
              trailing: PopupMenuButton<_OnlineAction>(
                key: Key('player_menu_$name'),
                tooltip: '',
                onSelected: (action) => _handleAction(action, name),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: _OnlineAction.kick,
                    child: Text('踢出'),
                  ),
                  PopupMenuItem(
                    value: _OnlineAction.whitelist,
                    child: Text(inWhitelist ? '移出白名单' : '加入白名单'),
                  ),
                  PopupMenuItem(
                    value: _OnlineAction.op,
                    child: Text(isOp ? '取消 OP' : '给予 OP'),
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
          // 没在跑就按 0 显示（名单可能还留着上一次的解析结果，但没意义）
          title: '在线（${running ? players.length : 0}）',
          refreshTooltip: '刷新（发送 list）',
          onRefresh: running
              ? () {
                  widget.send('list');
                  _loadContextSets();
                }
              : null,
        ),
        Expanded(child: body),
      ],
    );
  }

  void _handleAction(_OnlineAction action, String name) {
    switch (action) {
      case _OnlineAction.kick:
        unawaited(_confirmKick(name));
      case _OnlineAction.whitelist:
        final inWhitelist = _whitelist.contains(name.toLowerCase());
        widget.send(inWhitelist ? 'whitelist remove $name' : 'whitelist add $name');
        _delayedRefresh();
      case _OnlineAction.op:
        final isOp = _ops.contains(name.toLowerCase());
        widget.send(isOp ? 'deop $name' : 'op $name');
        _delayedRefresh();
      case _OnlineAction.ban:
        unawaited(_confirmBan(name));
    }
  }

  Future<void> _confirmKick(String name) async {
    final reason = await _askReason(
      context,
      title: '踢出 $name',
      hint: '踢出原因（可选）',
      confirmLabel: '踢出',
    );
    if (reason == null) return;
    widget.send(reason.isEmpty ? 'kick $name' : 'kick $name $reason');
  }

  Future<void> _confirmBan(String name) async {
    final reason = await _askReason(
      context,
      title: '封禁 $name',
      hint: '封禁原因（可选）',
      confirmLabel: '封禁',
    );
    if (reason == null) return;
    widget.send(reason.isEmpty ? 'ban $name' : 'ban $name $reason');
    _delayedRefresh();
  }
}

/// 在线玩家右侧菜单里的四项。
enum _OnlineAction { kick, whitelist, op, ban }

// ───────────────────────────── 白名单 ─────────────────────────────

class _WhitelistTab extends ConsumerStatefulWidget {
  const _WhitelistTab({
    required this.instanceId,
    required this.running,
    required this.send,
  });

  final String instanceId;
  final bool running;
  final void Function(String line) send;

  @override
  ConsumerState<_WhitelistTab> createState() => _WhitelistTabState();
}

class _WhitelistTabState extends ConsumerState<_WhitelistTab> {
  Future<List<NamedEntry>>? _future;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() { _future = _load(); });
    });
  }

  Future<List<NamedEntry>> _load() async =>
      await ref.read(playersApiProvider(widget.instanceId))?.whitelist() ?? const [];

  void _refresh() {
    if (mounted) setState(() { _future = _load(); });
  }

  @override
  Widget build(BuildContext context) => _NamedList<NamedEntry>(
    future: _future,
    running: widget.running,
    title: (count) => '白名单（$count）',
    emptyIcon: Icons.how_to_reg,
    emptyTitle: '白名单为空',
    emptyHint: '点击上方「添加」按钮加入玩家。',
    avatar: (context, entry) => _LetterAvatar(
      name: entry.name,
      background: Theme.of(context).colorScheme.secondaryContainer,
      foreground: Theme.of(context).colorScheme.onSecondaryContainer,
    ),
    name: (entry) => entry.name,
    uuid: (entry) => entry.uuid,
    deleteTint: (context) => Theme.of(context).colorScheme.error,
    onAdd: () => _promptAndSend(
      context,
      title: '添加白名单',
      nameHint: '玩家名称',
      commandPrefix: 'whitelist add',
      send: widget.send,
      onDone: _refresh,
    ),
    onDelete: (entry) {
      widget.send('whitelist remove ${entry.name}');
      _refresh();
    },
    deleteKey: (entry) => Key('player_delete_${entry.name}'),
    rowKey: (entry) => Key('player_row_${entry.name}'),
  );
}

// ───────────────────────────── 封禁 ─────────────────────────────

class _BansTab extends ConsumerStatefulWidget {
  const _BansTab({
    required this.instanceId,
    required this.running,
    required this.send,
  });

  final String instanceId;
  final bool running;
  final void Function(String line) send;

  @override
  ConsumerState<_BansTab> createState() => _BansTabState();
}

class _BansTabState extends ConsumerState<_BansTab> {
  Future<List<BanEntry>>? _future;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() { _future = _load(); });
    });
  }

  Future<List<BanEntry>> _load() async =>
      await ref.read(playersApiProvider(widget.instanceId))?.bans() ?? const [];

  void _refresh() {
    if (mounted) setState(() { _future = _load(); });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _BansLikeList<BanEntry>(
      future: _future,
      running: widget.running,
      title: (count) => '封禁名单（$count）',
      emptyIcon: Icons.check_circle_outline,
      emptyTitle: '暂无封禁',
      emptyHint: '没有被封禁的玩家。',
      lead: _BadgeAvatar(icon: Icons.block, background: scheme.errorContainer, foreground: scheme.onErrorContainer),
      name: (entry) => entry.name,
      lines: (entry) => [
        // 默认原因「Banned by an operator.」不显示，免得每条都挂一行废话
        if (entry.reason.isNotEmpty && entry.reason != 'Banned by an operator.')
          '原因：${entry.reason}',
        // 永久封禁（`forever`）不显示到期行
        if (entry.expires.isNotEmpty && entry.expires.toLowerCase() != 'forever')
          '到期：${entry.expires}',
        if (entry.uuid.isNotEmpty) entry.uuid,
      ],
      onAdd: () => _promptAndSend(
        context,
        title: '封禁玩家',
        nameHint: '玩家名称',
        commandPrefix: 'ban',
        send: widget.send,
        onDone: _refresh,
        withReason: true,
      ),
      onDelete: (entry) {
        widget.send('pardon ${entry.name}');
        _refresh();
      },
      deleteKey: (entry) => Key('player_delete_${entry.name}'),
      rowKey: (entry) => Key('player_row_${entry.name}'),
    );
  }
}

// ───────────────────────────── IP 封禁 ─────────────────────────────

class _BanIpsTab extends ConsumerStatefulWidget {
  const _BanIpsTab({
    required this.instanceId,
    required this.running,
    required this.send,
  });

  final String instanceId;
  final bool running;
  final void Function(String line) send;

  @override
  ConsumerState<_BanIpsTab> createState() => _BanIpsTabState();
}

class _BanIpsTabState extends ConsumerState<_BanIpsTab> {
  Future<List<IpBanEntry>>? _future;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() { _future = _load(); });
    });
  }

  Future<List<IpBanEntry>> _load() async =>
      await ref.read(playersApiProvider(widget.instanceId))?.ipBans() ?? const [];

  void _refresh() {
    if (mounted) setState(() { _future = _load(); });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _BansLikeList<IpBanEntry>(
      future: _future,
      running: widget.running,
      title: (count) => 'IP 封禁（$count）',
      emptyIcon: Icons.check_circle_outline,
      emptyTitle: '暂无封禁 IP',
      emptyHint: '没有被封禁的 IP 地址。',
      lead: _BadgeAvatar(icon: Icons.router, background: scheme.errorContainer, foreground: scheme.onErrorContainer),
      name: (entry) => entry.ip,
      // IP 封禁页只显示原因，且不过滤默认原因
      lines: (entry) => [
        if (entry.reason.isNotEmpty) '原因：${entry.reason}',
      ],
      onAdd: () => _promptAndSend(
        context,
        title: '封禁 IP',
        nameHint: 'IP 地址',
        commandPrefix: 'ban-ip',
        send: widget.send,
        onDone: _refresh,
        withReason: true,
      ),
      onDelete: (entry) {
        widget.send('pardon-ip ${entry.ip}');
        _refresh();
      },
      deleteKey: (entry) => Key('player_delete_${entry.ip}'),
      rowKey: (entry) => Key('player_row_${entry.ip}'),
    );
  }
}

// ───────────────────────────── OP ─────────────────────────────

class _OpsTab extends ConsumerStatefulWidget {
  const _OpsTab({
    required this.instanceId,
    required this.running,
    required this.send,
  });

  final String instanceId;
  final bool running;
  final void Function(String line) send;

  @override
  ConsumerState<_OpsTab> createState() => _OpsTabState();
}

class _OpsTabState extends ConsumerState<_OpsTab> {
  Future<List<NamedEntry>>? _future;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() { _future = _load(); });
    });
  }

  Future<List<NamedEntry>> _load() async =>
      await ref.read(playersApiProvider(widget.instanceId))?.ops() ?? const [];

  void _refresh() {
    if (mounted) setState(() { _future = _load(); });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _NamedList<NamedEntry>(
      future: _future,
      running: widget.running,
      title: (count) => 'OP 列表（$count）',
      emptyIcon: Icons.security,
      emptyTitle: '暂无 OP',
      emptyHint: '点击上方「添加」按钮授予玩家管理权限。',
      avatar: (context, entry) => _BadgeAvatar(
        icon: Icons.star,
        background: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
      ),
      name: (entry) => entry.name,
      uuid: (entry) => entry.uuid,
      deleteTint: (context) => scheme.error,
      onAdd: () => _promptAndSend(
        context,
        title: '添加 OP',
        nameHint: '玩家名称',
        commandPrefix: 'op',
        send: widget.send,
        onDone: _refresh,
      ),
      onDelete: (entry) {
        widget.send('deop ${entry.name}');
        _refresh();
      },
      deleteKey: (entry) => Key('player_delete_${entry.name}'),
      rowKey: (entry) => Key('player_row_${entry.name}'),
    );
  }
}

// ───────────────────────────── 列表骨架 ─────────────────────────────

/// 「名字 + uuid」那种名单（白名单 / OP）的列表骨架。
class _NamedList<T> extends StatelessWidget {
  const _NamedList({
    required this.future,
    required this.running,
    required this.title,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyHint,
    required this.avatar,
    required this.name,
    required this.uuid,
    required this.deleteTint,
    required this.onAdd,
    required this.onDelete,
    required this.deleteKey,
    required this.rowKey,
  });

  final Future<List<T>>? future;
  final bool running;
  final String Function(int count) title;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyHint;
  final Widget Function(BuildContext, T) avatar;
  final String Function(T) name;
  final String Function(T) uuid;
  final Color Function(BuildContext) deleteTint;
  final VoidCallback onAdd;
  final void Function(T entry) onDelete;
  final Key Function(T) deleteKey;
  final Key Function(T) rowKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<T>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snapshot.data ?? const [];
        return Column(
          children: [
            _ListHeader(
              title: title(entries.length),
              action: _HeaderAction(onAdd: running ? onAdd : null),
            ),
            if (!running) const _ReadonlyNote(),
            Expanded(
              child: entries.isEmpty
                  ? _emptyState(theme, emptyIcon, emptyTitle, emptyHint)
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final id = uuid(entry);
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            key: rowKey(entry),
                            leading: avatar(context, entry),
                            title: Text(name(entry)),
                            subtitle: id.isEmpty
                                ? null
                                : Text(
                                    id,
                                    style: theme.textTheme.bodySmall,
                                  ),
                            trailing: running
                                ? IconButton(
                                    key: deleteKey(entry),
                                    tooltip: '删除',
                                    onPressed: () => onDelete(entry),
                                    icon: Icon(
                                      Icons.delete,
                                      color: deleteTint(context),
                                    ),
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

/// 白名单 / OP 之外那两种（封禁 / IP 封禁）的列表骨架：名字 + 任意行附加信息。
class _BansLikeList<T> extends StatelessWidget {
  const _BansLikeList({
    required this.future,
    required this.running,
    required this.title,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyHint,
    required this.lead,
    required this.name,
    required this.lines,
    required this.onAdd,
    required this.onDelete,
    required this.deleteKey,
    required this.rowKey,
  });

  final Future<List<T>>? future;
  final bool running;
  final String Function(int count) title;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyHint;
  final Widget lead;
  final String Function(T) name;
  final List<String> Function(T) lines;
  final VoidCallback onAdd;
  final void Function(T entry) onDelete;
  final Key Function(T) deleteKey;
  final Key Function(T) rowKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<T>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snapshot.data ?? const [];
        return Column(
          children: [
            _ListHeader(
              title: title(entries.length),
              action: _HeaderAction(onAdd: running ? onAdd : null),
            ),
            if (!running) const _ReadonlyNote(),
            Expanded(
              child: entries.isEmpty
                  ? _emptyState(theme, emptyIcon, emptyTitle, emptyHint)
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final extra = lines(entry);
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            key: rowKey(entry),
                            leading: lead,
                            title: Text(name(entry)),
                            subtitle: extra.isEmpty
                                ? null
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      for (final line in extra)
                                        Text(
                                          line,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                    ],
                                  ),
                            trailing: running
                                ? IconButton(
                                    key: deleteKey(entry),
                                    tooltip: '删除',
                                    onPressed: () => onDelete(entry),
                                    // 封禁 / IP 封禁两处都用主色
                                    icon: Icon(
                                      Icons.delete,
                                      color: theme.colorScheme.primary,
                                    ),
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

/// 玩家状态标签（在线页里显示 OP / 白名单 / 已封禁）。
class _PlayerTag extends StatelessWidget {
  const _PlayerTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
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

/// 名字首字母头像（白名单 / 在线玩家）。
class _LetterAvatar extends StatelessWidget {
  const _LetterAvatar({
    required this.name,
    required this.background,
    required this.foreground,
  });

  final String name;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    backgroundColor: background,
    child: Text(
      _initial(name),
      style: TextStyle(color: foreground, fontWeight: FontWeight.bold),
    ),
  );
}

/// 图标头像（封禁 / IP 封禁 / OP）。
class _BadgeAvatar extends StatelessWidget {
  const _BadgeAvatar({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    backgroundColor: background,
    child: Icon(icon, color: foreground, size: 20),
  );
}

/// 没在跑时那几个名单页顶部的一行说明。
class _ReadonlyNote extends StatelessWidget {
  const _ReadonlyNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '只读模式，启动服务端后可进行操作',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 名单头部：标题 + 刷新 + 添加。
class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.title,
    this.refreshTooltip = '刷新',
    this.onRefresh,
    this.action,
  });

  final String title;
  final String refreshTooltip;

  /// 刷新回调；`null` = 禁用（在线页未运行时就是禁用态）。
  final VoidCallback? onRefresh;

  /// 「添加」按钮；不给就没有（在线页没有这个按钮）。
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const Spacer(),
          IconButton(
            key: const Key('players_refresh'),
            tooltip: refreshTooltip,
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 20),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// 头部的「添加」按钮。
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('players_add'),
    tooltip: '添加',
    onPressed: onAdd,
    icon: const Icon(Icons.add, size: 20),
  );
}

/// 空白占位状态。
Widget _emptyState(
  ThemeData theme,
  IconData icon,
  String title,
  String desc,
) => Center(
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
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  ),
);

/// 名字的首字母；空名字给空串。
String _initial(String name) =>
    name.isEmpty ? '' : name[0].toUpperCase();

// ───────────────────────────── 对话框 ─────────────────────────────

/// 问一个原因（踢出 / 封禁某个在线玩家）。
///
/// 取消返回 `null`；确定返回去首尾空白的原因（可能就是空串 = 不写原因）。
Future<String?> _askReason(
  BuildContext context, {
  required String title,
  required String hint,
  required String confirmLabel,
}) async {
  final result = await _playerDialog(
    context,
    title: title,
    reasonHint: hint,
    confirmLabel: confirmLabel,
  );
  return result?.reason;
}

/// 「输入玩家名（可带原因）→ 发命令 → 稍后刷新」的那一套。
Future<void> _promptAndSend(
  BuildContext context, {
  required String title,
  required String nameHint,
  required String commandPrefix,
  required void Function(String line) send,
  required VoidCallback onDone,
  bool withReason = false,
}) async {
  final result = await _playerDialog(
    context,
    title: title,
    nameHint: nameHint,
    reasonHint: withReason ? '原因（可选）' : null,
    confirmLabel: '确定',
  );
  if (result == null || result.name.isEmpty) return;
  final reason = result.reason;
  send(
    reason.isEmpty
        ? '$commandPrefix ${result.name}'
        : '$commandPrefix ${result.name} $reason',
  );
  // 命令写完等 500 ms 再刷新：服务端处理并落盘名单要一点时间
  Future.delayed(const Duration(milliseconds: 500), onDone);
}

/// 玩家对话框：名字字段（[nameHint] 为 `null` 就没有）与原因字段
/// （[reasonHint] 为 `null` 就没有），至少得有一个。
Future<({String name, String reason})?> _playerDialog(
  BuildContext context, {
  required String title,
  String? nameHint,
  String? reasonHint,
  required String confirmLabel,
}) => showDialog<({String name, String reason})>(
  context: context,
  builder: (_) => _PlayerDialog(
    title: title,
    nameHint: nameHint,
    reasonHint: reasonHint,
    confirmLabel: confirmLabel,
  ),
);

class _PlayerDialog extends StatefulWidget {
  const _PlayerDialog({
    required this.title,
    required this.nameHint,
    required this.reasonHint,
    required this.confirmLabel,
  });

  final String title;
  final String? nameHint;
  final String? reasonHint;
  final String confirmLabel;

  @override
  State<_PlayerDialog> createState() => _PlayerDialogState();
}

/// controller 由弹窗自己持有：`showDialog` 的 Future 在退场前就完成，
/// 交给外面释放会踩到「已释放还在用」。
class _PlayerDialogState extends State<_PlayerDialog> {
  final _name = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop((
    name: _name.text.trim(),
    reason: _reason.text.trim(),
  ));

  @override
  Widget build(BuildContext context) {
    final askName = widget.nameHint != null;
    final askReason = widget.reasonHint != null;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (askName)
            TextField(
              key: const Key('player_name_field'),
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: widget.nameHint,
                border: const OutlineInputBorder(),
              ),
              // 有原因字段时这里不提交（先填完再一起确定）
              onSubmitted: askReason ? null : (_) => _submit(),
            ),
          if (askName && askReason) const SizedBox(height: 12),
          if (askReason)
            TextField(
              key: const Key('player_reason_field'),
              controller: _reason,
              decoration: InputDecoration(
                labelText: widget.reasonHint,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('player_dialog_ok'),
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

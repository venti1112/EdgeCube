import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:path/path.dart' as p;

import '../i18n/locale_scope.dart';
import '../instance/instance.dart';
import '../instance/instance_scope.dart';
import '../server/server_controller.dart';
import '../server/server_scope.dart';
import '../widgets/ec_text_field.dart';
import '../widgets/miuix_dialog.dart';
import '../widgets/ec_preference.dart';

/// 玩家管理页：在线玩家、白名单、封禁名单、OP 名单的可视化管理。
class PlayersPage extends StatefulWidget {
  const PlayersPage({super.key});

  @override
  State<PlayersPage> createState() => _PlayersPageState();
}

class _PlayersPageState extends State<PlayersPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  /// MiuixTabRow 是受控组件，需自持选中项；滑动 TabBarView 时反向同步。
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.index != _tabIndex && mounted) {
        setState(() => _tabIndex = _tabCtrl.index);
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final instance = InstanceScope.of(context).selected;
    return MiuixScaffold(
      topBar: EcTopAppBar(
        title: context.tr('players.title'),

        // 只换有 Material 观感的标签条；TabController + TabBarView 作为
        // 不可见的翻页管道保留（它们不绘制任何 Material 装饰）。
        bottomContent: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: MiuixTabRow(
            tabs: [
              context.tr('players.tab.online'),
              context.tr('players.tab.whitelist'),
              context.tr('players.tab.bans'),
              context.tr('players.tab.banIps'),
              context.tr('players.tab.ops'),
            ],
            selectedTabIndex: _tabIndex,
            onTabSelected: (i) {
              setState(() => _tabIndex = i);
              _tabCtrl.animateTo(i);
            },
          ),
        ),
      ),
      content: (padding) => Padding(
        padding: padding,
        child: instance == null
            ? Center(child: Text(context.tr('players.noInstanceHint')))
            : TabBarView(
                controller: _tabCtrl,
                children: [
                  _OnlineTab(instance: instance),
                  _WhitelistTab(instance: instance),
                  _BansTab(instance: instance),
                  _BanIpsTab(instance: instance),
                  _OpsTab(instance: instance),
                ],
              ),
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
    // _loadContextSets 内会调用 InstanceScope.of(context)，依赖 inherited widget，
    // 不能在 initState 中直接同步调用，否则触发
    // dependOnInheritedWidgetOfExactType 断言错误。改用 post-frame 回调延迟启动。
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadContextSets());
  }

  Future<void> _loadContextSets() async {
    final dir = await InstanceScope.of(context).directoryFor(widget.instance);

    Set<String> loadJsonNames(String fileName) {
      try {
        final file = File(p.join(dir.path, fileName));
        if (!file.existsSync()) return {};
        final json = jsonDecode(file.readAsStringSync()) as List;
        return json
            .map((e) => (e['name'] as String? ?? '').toLowerCase())
            .toSet();
      } catch (_) {
        return {};
      }
    }

    Set<String> loadPlainNames(String fileName) {
      try {
        final file = File(p.join(dir.path, fileName));
        if (!file.existsSync()) return {};
        return file
            .readAsLinesSync()
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .map((l) => l.toLowerCase())
            .toSet();
      } catch (_) {
        return {};
      }
    }

    Set<String> loadWithFallback(String jsonFile, String txtFile) {
      final jsonResult = loadJsonNames(jsonFile);
      if (jsonResult.isNotEmpty) return jsonResult;
      return loadPlainNames(txtFile);
    }

    setState(() {
      _whitelist = loadWithFallback('whitelist.json', 'white-list.txt');
      _ops = loadWithFallback('ops.json', 'ops.txt');
      _bans = loadWithFallback('banned-players.json', 'banned-players.txt');
    });
  }

  @override
  Widget build(BuildContext context) {
    final server = ServerScope.of(context);
    final theme = MiuixTheme.of(context);
    final running = server.isRunning && server.isActive(widget.instance.id);
    final players = server.onlinePlayers.toList()..sort();

    final Widget body;
    if (!running) {
      body = _emptyState(
        theme,
        Icons.power_settings_new,
        context.tr('players.offline.title'),
        context.tr('players.offline.desc'),
      );
    } else if (players.isEmpty) {
      body = _emptyState(
        theme,
        Icons.person_off,
        context.tr('players.online.empty'),
        context.tr('players.online.waiting'),
      );
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
          return MiuixCard(
            child: MiuixBasicComponent(
              startAction: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: CircleAvatar(
                  backgroundColor: theme.colors.primaryContainer,
                  child: Text(
                    name[0].toUpperCase(),
                    style: TextStyle(
                      color: theme.colors.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              content: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name),
                    Row(
                      children: [
                        if (isOp)
                          _PlayerTag(
                            label: 'OP',
                            color: theme.colors.onTertiaryContainer,
                          ),
                        if (inWhitelist)
                          _PlayerTag(
                            label: context.tr('players.tag.whitelist'),
                            color: theme.colors.primary,
                          ),
                        if (isBanned)
                          _PlayerTag(
                            label: context.tr('players.tag.banned'),
                            color: theme.colors.error,
                          ),
                      ],
                    ),
                  ],
                ),
              ],
              endActions: [
                MiuixOverlayIconDropdownMenu(
                  entry: MiuixDropdownEntry(
                    items: [
                      MiuixDropdownItem(
                        text: context.tr('players.action.kick'),
                        onClick: () =>
                            _handleAction(context, server, name, 'kick'),
                      ),
                      MiuixDropdownItem(
                        text: inWhitelist
                            ? context.tr('players.action.removeFromWhitelist')
                            : context.tr('players.action.addToWhitelist'),
                        onClick: () => _handleAction(
                          context,
                          server,
                          name,
                          inWhitelist ? 'wl_remove' : 'wl_add',
                        ),
                      ),
                      MiuixDropdownItem(
                        text: isOp
                            ? context.tr('players.action.deop')
                            : context.tr('players.action.op'),
                        onClick: () => _handleAction(
                          context,
                          server,
                          name,
                          isOp ? 'deop' : 'op',
                        ),
                      ),
                      MiuixDropdownItem(
                        text: context.tr('players.action.ban'),
                        onClick: () =>
                            _handleAction(context, server, name, 'ban'),
                      ),
                    ],
                  ),
                  child: const MiuixIcon(icon: Icons.more_vert),
                ),
              ],
            ),
          );
        },
      );
    }

    return Column(
      children: [
        _ListHeader(
          title: context.tr('players.online.count', {
            'count': '${running ? players.length : 0}',
          }),
          tooltip: context.tr('players.online.refreshTooltip'),
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
    BuildContext context,
    ServerController server,
    String name,
    String action,
  ) async {
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
    BuildContext context,
    ServerController server,
    String name,
  ) async {
    final reason = await showMiuixDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: double.infinity,
              child: MiuixText(
                context.tr('players.kick.title', {'name': name}),
                textAlign: TextAlign.center,
                style: MiuixTheme.of(context).textStyles.title4,
              ),
            ),
            const SizedBox(height: 12),
            EcTextField(
              controller: ctrl,
              label: context.tr('players.kick.reasonHint'),
            ),
            const SizedBox(height: 20),
            MiuixDialogActions(
              children: [
                MiuixTextButton(
                  ctx.tr('common.cancel'),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
                MiuixButton(
                  onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                  colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                  child: MiuixText(ctx.tr('players.action.kick')),
                ),
              ],
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
    BuildContext context,
    ServerController server,
    String name,
  ) async {
    final reason = await showMiuixDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: double.infinity,
              child: MiuixText(
                context.tr('players.ban.title', {'name': name}),
                textAlign: TextAlign.center,
                style: MiuixTheme.of(context).textStyles.title4,
              ),
            ),
            const SizedBox(height: 12),
            EcTextField(
              controller: ctrl,
              label: context.tr('players.ban.reasonHint'),
            ),
            const SizedBox(height: 20),
            MiuixDialogActions(
              children: [
                MiuixTextButton(
                  ctx.tr('common.cancel'),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
                MiuixButton(
                  onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                  colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                  child: MiuixText(ctx.tr('players.action.ban')),
                ),
              ],
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
    // _loadWhitelist 内会调用 InstanceScope.of(context)，依赖 inherited widget，
    // 不能在 initState 中直接同步调用，否则触发
    // dependOnInheritedWidgetOfExactType 断言错误。改用 post-frame 回调延迟启动。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _future = _loadWhitelist());
      }
    });
  }

  Future<List<_NamedEntry>> _loadWhitelist() async {
    final dir = await InstanceScope.of(context).directoryFor(widget.instance);

    // 优先读取 Java 版 whitelist.json
    final jsonFile = File(p.join(dir.path, 'whitelist.json'));
    if (await jsonFile.exists()) {
      try {
        final json = jsonDecode(await jsonFile.readAsString()) as List;
        return json
            .map(
              (e) => _NamedEntry(
                name: e['name'] as String? ?? '',
                uuid: e['uuid'] as String? ?? '',
              ),
            )
            .toList();
      } catch (_) {}
    }

    // 回退到 PNX white-list.txt
    final txtFile = File(p.join(dir.path, 'white-list.txt'));
    if (await txtFile.exists()) {
      try {
        final lines = await txtFile.readAsLines();
        return lines
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .map((l) => _NamedEntry(name: l, uuid: ''))
            .toList();
      } catch (_) {}
    }

    return [];
  }

  void _refresh() => setState(() => _future = _loadWhitelist());

  @override
  Widget build(BuildContext context) {
    final server = ServerScope.of(context);
    final running = server.isRunning && server.isActive(widget.instance.id);
    final theme = MiuixTheme.of(context);

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
              title: context.tr('players.whitelist.count', {
                'count': '${entries.length}',
              }),
              tooltip: context.tr('common.refresh'),
              onRefresh: _refresh,
              actionLabel: context.tr('common.add'),
              actionIcon: Icons.add,
              onAction: running
                  ? () => _promptAndSend(
                      context,
                      server,
                      title: context.tr('players.whitelist.addTitle'),
                      hint: context.tr('players.addPlayerHint'),
                      commandPrefix: 'whitelist add',
                      onDone: _refresh,
                    )
                  : null,
            ),
            if (!running)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  context.tr('players.readonlyNote'),
                  style: theme.textStyles.footnote1.copyWith(
                    color: theme.colors.onSurfaceVariantSummary,
                  ),
                ),
              ),
            Expanded(
              child: entries.isEmpty
                  ? _emptyState(
                      theme,
                      Icons.how_to_reg,
                      context.tr('players.whitelist.empty'),
                      context.tr('players.whitelist.emptyHint'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: entries.length,
                      itemBuilder: (ctx, i) {
                        final e = entries[i];
                        return MiuixCard(
                          child: MiuixBasicComponent(
                            startAction: Padding(
                              padding: const EdgeInsets.only(right: 16),
                              child: CircleAvatar(
                                backgroundColor:
                                    theme.colors.secondaryContainer,
                                child: Text(
                                  e.name[0].toUpperCase(),
                                  style: TextStyle(
                                    color: theme.colors.onSecondaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            content: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(e.name),
                                  ?e.uuid.isNotEmpty
                                      ? Text(
                                          e.uuid,
                                          style: theme.textStyles.footnote1,
                                        )
                                      : null,
                                ],
                              ),
                            ],
                            endActions: [
                              ?running
                                  ? MiuixIconButton(
                                      onPressed: () {
                                        server.sendCommand(
                                          'whitelist remove ${e.name}',
                                        );
                                        _refresh();
                                      },
                                      child: MiuixIcon(
                                        icon: Icons.delete,
                                        tint: theme.colors.error,
                                      ),
                                    )
                                  : null,
                            ],
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
    // _loadBans 内会调用 InstanceScope.of(context)，依赖 inherited widget，
    // 不能在 initState 中直接同步调用，否则触发
    // dependOnInheritedWidgetOfExactType 断言错误。改用 post-frame 回调延迟启动。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _future = _loadBans());
      }
    });
  }

  Future<List<_BanEntry>> _loadBans() async {
    final dir = await InstanceScope.of(context).directoryFor(widget.instance);

    // 优先读取 Java/PNX 的 banned-players.json
    final jsonFile = File(p.join(dir.path, 'banned-players.json'));
    if (await jsonFile.exists()) {
      try {
        final json = jsonDecode(await jsonFile.readAsString()) as List;
        return json
            .map(
              (e) => _BanEntry(
                name: e['name'] as String? ?? '',
                uuid: e['uuid'] as String? ?? '',
                reason: e['reason'] as String? ?? '',
                source: e['source'] as String? ?? '',
                // PNX uses "expireDate", Java uses "expires"
                expires: (e['expires'] ?? e['expireDate'] ?? '') as String,
                // PNX uses "creationDate", Java uses "created"
                created: (e['created'] ?? e['creationDate'] ?? '') as String,
              ),
            )
            .toList();
      } catch (_) {}
    }

    // 回退到 PMMP 的 banned-players.txt（每行一个玩家名，无元数据）
    final txtFile = File(p.join(dir.path, 'banned-players.txt'));
    if (await txtFile.exists()) {
      try {
        final lines = await txtFile.readAsLines();
        return lines
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .map(
              (l) => _BanEntry(
                name: l,
                uuid: '',
                reason: '',
                source: '',
                expires: '',
                created: '',
              ),
            )
            .toList();
      } catch (_) {}
    }

    return [];
  }

  void _refresh() => setState(() => _future = _loadBans());

  @override
  Widget build(BuildContext context) {
    final server = ServerScope.of(context);
    final running = server.isRunning && server.isActive(widget.instance.id);
    final theme = MiuixTheme.of(context);

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
              title: context.tr('players.bans.count', {
                'count': '${entries.length}',
              }),
              tooltip: context.tr('common.refresh'),
              onRefresh: _refresh,
              actionLabel: context.tr('players.action.ban'),
              actionIcon: Icons.add,
              onAction: running
                  ? () => _promptAndSend(
                      context,
                      server,
                      title: context.tr('players.bans.addTitle'),
                      hint: context.tr('players.addPlayerHint'),
                      commandPrefix: 'ban',
                      onDone: _refresh,
                      withReason: true,
                    )
                  : null,
            ),
            if (!running)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  context.tr('players.readonlyNote'),
                  style: theme.textStyles.footnote1.copyWith(
                    color: theme.colors.onSurfaceVariantSummary,
                  ),
                ),
              ),
            Expanded(
              child: entries.isEmpty
                  ? _emptyState(
                      theme,
                      Icons.check_circle_outline,
                      context.tr('players.bans.empty'),
                      context.tr('players.bans.emptyHint'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: entries.length,
                      itemBuilder: (ctx, i) {
                        final e = entries[i];
                        return MiuixCard(
                          child: MiuixBasicComponent(
                            startAction: Padding(
                              padding: const EdgeInsets.only(right: 16),
                              child: CircleAvatar(
                                backgroundColor: theme.colors.errorContainer,
                                child: Icon(
                                  Icons.block,
                                  color: theme.colors.onErrorContainer,
                                  size: 20,
                                ),
                              ),
                            ),
                            content: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(e.name),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (e.reason.isNotEmpty &&
                                          e.reason != 'Banned by an operator.')
                                        Text(
                                          context.tr('players.bans.reason', {
                                            'reason': e.reason,
                                          }),
                                          style: theme.textStyles.footnote1,
                                        ),
                                      if (e.expires.isNotEmpty &&
                                          e.expires.toLowerCase() != 'forever')
                                        Text(
                                          context.tr('players.bans.expires', {
                                            'expires': e.expires,
                                          }),
                                          style: theme.textStyles.footnote1,
                                        ),
                                      if (e.uuid.isNotEmpty)
                                        Text(
                                          e.uuid,
                                          style: theme.textStyles.footnote1
                                              .copyWith(fontSize: 10),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                            endActions: [
                              ?running
                                  ? MiuixIconButton(
                                      onPressed: () {
                                        server.sendCommand('pardon ${e.name}');
                                        _refresh();
                                      },
                                      child: MiuixIcon(
                                        icon: Icons.delete,
                                        tint: theme.colors.primary,
                                      ),
                                    )
                                  : null,
                            ],
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

// ───────────────────────────── IP 封禁 ─────────────────────────────

class _BanIpsTab extends StatefulWidget {
  const _BanIpsTab({required this.instance});
  final Instance instance;

  @override
  State<_BanIpsTab> createState() => _BanIpsTabState();
}

class _BanIpsTabState extends State<_BanIpsTab> {
  Future<List<_IpBanEntry>>? _future;
  @override
  void initState() {
    super.initState();
    // _loadBanIps 内会调用 InstanceScope.of(context)，依赖 inherited widget，
    // 不能在 initState 中直接同步调用，否则触发
    // dependOnInheritedWidgetOfExactType 断言错误。改用 post-frame 回调延迟启动。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _future = _loadBanIps());
      }
    });
  }

  Future<List<_IpBanEntry>> _loadBanIps() async {
    final dir = await InstanceScope.of(context).directoryFor(widget.instance);

    // Java 版 banned-ips.json
    final jsonFile = File(p.join(dir.path, 'banned-ips.json'));
    if (await jsonFile.exists()) {
      try {
        final json = jsonDecode(await jsonFile.readAsString()) as List;
        return json
            .map(
              (e) => _IpBanEntry(
                ip: e['ip'] as String? ?? '',
                reason: e['reason'] as String? ?? '',
                source: e['source'] as String? ?? '',
                expires: (e['expires'] ?? e['expireDate'] ?? '') as String,
                created: (e['created'] ?? e['creationDate'] ?? '') as String,
              ),
            )
            .toList();
      } catch (_) {}
    }

    // PMMP/Java 通用 banned-ips.txt（每行一个 IP）
    final txtFile = File(p.join(dir.path, 'banned-ips.txt'));
    if (await txtFile.exists()) {
      try {
        final lines = await txtFile.readAsLines();
        return lines
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .map(
              (l) => _IpBanEntry(
                ip: l,
                reason: '',
                source: '',
                expires: '',
                created: '',
              ),
            )
            .toList();
      } catch (_) {}
    }

    return [];
  }

  void _refresh() => setState(() => _future = _loadBanIps());

  @override
  Widget build(BuildContext context) {
    final server = ServerScope.of(context);
    final running = server.isRunning && server.isActive(widget.instance.id);
    final theme = MiuixTheme.of(context);

    return FutureBuilder<List<_IpBanEntry>>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snap.data ?? [];
        return Column(
          children: [
            _ListHeader(
              title: context.tr('players.banIps.count', {
                'count': '${entries.length}',
              }),
              tooltip: context.tr('common.refresh'),
              onRefresh: _refresh,
              actionLabel: context.tr('players.action.banIp'),
              actionIcon: Icons.add,
              onAction: running
                  ? () => _promptAndSend(
                      context,
                      server,
                      title: context.tr('players.banIps.addTitle'),
                      hint: context.tr('players.banIps.hint'),
                      commandPrefix: 'ban-ip',
                      onDone: _refresh,
                      withReason: true,
                    )
                  : null,
            ),
            if (!running)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  context.tr('players.readonlyNote'),
                  style: theme.textStyles.footnote1.copyWith(
                    color: theme.colors.onSurfaceVariantSummary,
                  ),
                ),
              ),
            Expanded(
              child: entries.isEmpty
                  ? _emptyState(
                      theme,
                      Icons.check_circle_outline,
                      context.tr('players.banIps.empty'),
                      context.tr('players.banIps.emptyHint'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: entries.length,
                      itemBuilder: (ctx, i) {
                        final e = entries[i];
                        return MiuixCard(
                          child: MiuixBasicComponent(
                            startAction: Padding(
                              padding: const EdgeInsets.only(right: 16),
                              child: CircleAvatar(
                                backgroundColor: theme.colors.errorContainer,
                                child: Icon(
                                  Icons.router,
                                  color: theme.colors.onErrorContainer,
                                  size: 20,
                                ),
                              ),
                            ),
                            content: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(e.ip),
                                  ?e.reason.isNotEmpty
                                      ? Text(
                                          context.tr('players.bans.reason', {
                                            'reason': e.reason,
                                          }),
                                          style: theme.textStyles.footnote1,
                                        )
                                      : null,
                                ],
                              ),
                            ],
                            endActions: [
                              ?running
                                  ? MiuixIconButton(
                                      onPressed: () {
                                        server.sendCommand('pardon-ip ${e.ip}');
                                        _refresh();
                                      },
                                      child: MiuixIcon(
                                        icon: Icons.delete,
                                        tint: theme.colors.primary,
                                      ),
                                    )
                                  : null,
                            ],
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
    // _loadOps 内会调用 InstanceScope.of(context)，依赖 inherited widget，
    // 不能在 initState 中直接同步调用，否则触发
    // dependOnInheritedWidgetOfExactType 断言错误。改用 post-frame 回调延迟启动。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _future = _loadOps());
      }
    });
  }

  Future<List<_NamedEntry>> _loadOps() async {
    final dir = await InstanceScope.of(context).directoryFor(widget.instance);

    // 优先读取 Java 版 ops.json
    final jsonFile = File(p.join(dir.path, 'ops.json'));
    if (await jsonFile.exists()) {
      try {
        final json = jsonDecode(await jsonFile.readAsString()) as List;
        return json
            .map(
              (e) => _NamedEntry(
                name: e['name'] as String? ?? '',
                uuid: e['uuid'] as String? ?? '',
              ),
            )
            .toList();
      } catch (_) {}
    }

    // 回退到 PNX ops.txt
    final txtFile = File(p.join(dir.path, 'ops.txt'));
    if (await txtFile.exists()) {
      try {
        final lines = await txtFile.readAsLines();
        return lines
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .map((l) => _NamedEntry(name: l, uuid: ''))
            .toList();
      } catch (_) {}
    }

    return [];
  }

  void _refresh() => setState(() => _future = _loadOps());

  @override
  Widget build(BuildContext context) {
    final server = ServerScope.of(context);
    final running = server.isRunning && server.isActive(widget.instance.id);
    final theme = MiuixTheme.of(context);

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
              title: context.tr('players.ops.count', {
                'count': '${entries.length}',
              }),
              tooltip: context.tr('common.refresh'),
              onRefresh: _refresh,
              actionLabel: context.tr('common.add'),
              actionIcon: Icons.add,
              onAction: running
                  ? () => _promptAndSend(
                      context,
                      server,
                      title: context.tr('players.ops.addTitle'),
                      hint: context.tr('players.addPlayerHint'),
                      commandPrefix: 'op',
                      onDone: _refresh,
                    )
                  : null,
            ),
            if (!running)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  context.tr('players.readonlyNote'),
                  style: theme.textStyles.footnote1.copyWith(
                    color: theme.colors.onSurfaceVariantSummary,
                  ),
                ),
              ),
            Expanded(
              child: entries.isEmpty
                  ? _emptyState(
                      theme,
                      Icons.security,
                      context.tr('players.ops.empty'),
                      context.tr('players.ops.emptyHint'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: entries.length,
                      itemBuilder: (ctx, i) {
                        final e = entries[i];
                        return MiuixCard(
                          child: MiuixBasicComponent(
                            startAction: Padding(
                              padding: const EdgeInsets.only(right: 16),
                              child: CircleAvatar(
                                backgroundColor: theme.colors.tertiaryContainer,
                                child: Icon(
                                  Icons.star,
                                  color: theme.colors.onTertiaryContainer,
                                  size: 20,
                                ),
                              ),
                            ),
                            content: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(e.name),
                                  ?e.uuid.isNotEmpty
                                      ? Text(
                                          e.uuid,
                                          style: theme.textStyles.footnote1,
                                        )
                                      : null,
                                ],
                              ),
                            ],
                            endActions: [
                              ?running
                                  ? MiuixIconButton(
                                      onPressed: () {
                                        server.sendCommand('deop ${e.name}');
                                        _refresh();
                                      },
                                      child: MiuixIcon(
                                        icon: Icons.delete,
                                        tint: theme.colors.error,
                                      ),
                                    )
                                  : null,
                            ],
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
    final theme = MiuixTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Text(title, style: theme.textStyles.subtitle),
          const Spacer(),
          MiuixIconButton(
            onPressed: onRefresh,
            child: MiuixIcon(icon: Icons.refresh, size: 20),
          ),
          if (actionIcon != null)
            MiuixIconButton(
              onPressed: onAction,
              child: MiuixIcon(icon: actionIcon, size: 20),
            ),
        ],
      ),
    );
  }
}

/// 空白占位状态。
Widget _emptyState(
  MiuixThemeData theme,
  IconData icon,
  String title,
  String desc,
) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: theme.colors.onSurfaceVariantSummary),
          const SizedBox(height: 12),
          Text(title, style: theme.textStyles.title4),
          const SizedBox(height: 4),
          Text(
            desc,
            textAlign: TextAlign.center,
            style: theme.textStyles.body2.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
            ),
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
  final result = await showMiuixDialog<Map<String, String>>(
    context: context,
    builder: (ctx) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            child: MiuixText(
              title,
              textAlign: TextAlign.center,
              style: MiuixTheme.of(context).textStyles.title4,
            ),
          ),
          const SizedBox(height: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EcTextField(
                controller: nameCtrl,
                label: hint,
                onSubmitted: (_) {
                  if (withReason) {
                    // 有原因字段时，不在此处提交
                  } else {
                    Navigator.of(ctx).pop({'name': nameCtrl.text.trim()});
                  }
                },
                autofocus: true,
              ),
              if (withReason) ...[
                const SizedBox(height: 12),
                EcTextField(
                  controller: reasonCtrl,
                  label: ctx.tr('players.reasonHint'),
                  onSubmitted: (_) => Navigator.of(ctx).pop({
                    'name': nameCtrl.text.trim(),
                    'reason': reasonCtrl.text.trim(),
                  }),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          MiuixDialogActions(
            children: [
              MiuixTextButton(
                ctx.tr('common.cancel'),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
              MiuixButton(
                onPressed: () => Navigator.of(ctx).pop({
                  'name': nameCtrl.text.trim(),
                  if (withReason) 'reason': reasonCtrl.text.trim(),
                }),
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                child: MiuixText(ctx.tr('common.ok')),
              ),
            ],
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
  final cmd = reason.isEmpty
      ? '$commandPrefix $name'
      : '$commandPrefix $name $reason';
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

/// IP 封禁条目。Java 版 banned-ips.json 含完整元数据，PMMP/通用 banned-ips.txt
/// 仅含 IP，其余字段为空字符串。
class _IpBanEntry {
  const _IpBanEntry({
    required this.ip,
    required this.reason,
    required this.source,
    required this.expires,
    required this.created,
  });
  final String ip;
  final String reason;
  final String source;
  final String expires;
  final String created;
}

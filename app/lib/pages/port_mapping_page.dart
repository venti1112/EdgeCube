import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../connection/client.dart';
import '../download/format.dart';
import '../frp/models.dart';
import '../frp/providers.dart';
import '../stun/models.dart';
import '../stun/providers.dart';
import '../upnp/models.dart';
import '../upnp/providers.dart';

/// 「网络映射」页：本机对外的几条路，都在这儿。
///
/// 排版与卡片顺序：
///
/// ```text
/// FRP 隧道  →  STUN 隧道  →  路由器端口映射  →  DDNS 动态域名
/// ```
///
/// **前三张是真的**，DDNS 是**字段完整摆出来的置灰卡**——
/// 项目约定：还没做的能力摆出位置并置灰，注释写明依赖哪个后端模块，
/// 让人一眼看到整体规划（同 `create_instance_page` 的四种导入方式、
/// `servers_page` 的四个按钮）。真做起来是「照着补齐 + 把 `enabled` 换掉」，
/// 而不是重新设计一遍页面。
///
/// FRP 那张卡：**FRP 实例 = 一条隧道配置**（`config/frp/toml/*.toml`），
/// 所以卡里剩「用哪个 frpc 运行环境」与「管理隧道」两件事，没有「启用开关 /
/// 默认隧道」—— 起停在某一条隧道自己的运行页上。
///
/// STUN 那张卡：开关、PROXY protocol 与目标端口在**每个实例自己的设置**里
/// （实例设置 → STUN 隧道），卡里是总览（每实例隧道行）+ 全局调参
/// （服务器列表 / 保活 / 并发 / 连接日志）+ 隧道日志。
///
/// UPnP 那张卡：开关、协议、外部端口都在**每个实例自己的设置**里
/// （实例设置 → 路由器端口映射），卡里只是总览 —— 网关发现到没有 /
/// 公网 IP 多少、每个实例映射到了哪，外加一个「重新探测」。
class PortMappingPage extends ConsumerWidget {
  const PortMappingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('网络映射'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _FrpCard(),
          const SizedBox(height: 16),

          // ── STUN 隧道 ──
          //
          // 每实例的开关 / PROXY / 目标端口在实例设置里，这张卡是总览：
          // 每实例隧道行（daemon 的投影）+ 全局调参 + 日志。
          // 速度统计与日志行 daemon 不推事件，卡片可见时自己每秒轮询一圈
          // （见 `_StunCard._syncPolling`）。
          const _StunCard(),
          const SizedBox(height: 16),

          // ── 路由器端口映射（UPnP）──
          //
          // 开关与参数在**每个实例自己的设置**里（实例设置 → 路由器端口映射），
          // 这张卡是 daemon 侧的投影：网关状态 + 每实例映射行 + 重新探测。
          const _UpnpCard(),
          const SizedBox(height: 16),

          // ── DDNS 动态域名 ──
          //
          // 缺的是**后端**：各 DNS 服务商的 API 客户端（阿里云 / DNSPod 的签名）、
          // 公网 IP 轮询与「IP 变了才更新」、以及服务器停止时删解析。
          const _PlannedCard(
            icon: Icons.language_outlined,
            title: 'DDNS 动态域名',
            switchTitle: '启用 DDNS 动态域名解析',
            switchSubtitle: '服务器启动后自动把域名解析到当前公网 IP\n公网 IP 变化时自动更新，与端口映射配合使用',
            dependsOn: 'daemon 的 DDNS 客户端（各 DNS 服务商 API + 公网 IP 轮询）',
            fields: [
              ('DNS 服务商', ''),
              ('主机记录', ''),
              ('域名', ''),
              ('令牌 ID', ''),
              ('令牌（Token）', ''),
              ('AccessKey ID', ''),
              ('AccessKey Secret', ''),
              ('API 令牌', ''),
              ('更新 URL（支持 {ipv4} {ipv6} {domain} 占位符）', ''),
              ('IP 检查间隔（分钟）', ''),
            ],
            toggles: [
              ('在关闭服务器后删除解析', '服务器停止时自动删除域名的解析记录，避免域名继续指向已下线的地址'),
            ],
            actions: ['立即更新', '保存配置'],
            note: 'DDNS 只把域名指向你的公网 IP，玩家还需要能通过端口连入：'
                '建议同时开启上方的路由器端口映射（UPnP），或在路由器上手动做端口转发。'
                '若 UPnP 提示公网 IP 为保留地址（CGNAT），则 DDNS 也无法使外网直连，'
                '请改用 FRP 隧道。',
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// FRP 卡（唯一真能用的那一张）
// ══════════════════════════════════════════════════════════════════════════

/// 「FRP 隧道」卡：选一个 frpc 运行环境 + 进隧道管理。
///
/// 卡里没有「启用开关 / 默认隧道」两截 —— 那两截是
/// 「全局一个 frpc 随服务器启停」时代的产物，现在一条隧道一个实例，
/// 起停归各条隧道自己的运行页。
class _FrpCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final list = ref.watch(frpRuntimesProvider).value ?? FrpcRuntimeList.empty;

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.cloud_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'FRP 隧道',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: list.runtimes.isEmpty
                ? _RuntimeMissing()
                : _RuntimePicker(state: list),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              '一条隧道就是一个 FRP 实例：一条配置对应一个 frpc 进程，'
              '自己启停、互不影响。游戏实例可以「连带启动」某一条，'
              '但不会跟着停。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                key: const Key('port_mapping_manage_tunnels'),
                onPressed: () => context.push('/manage/network/tunnels'),
                icon: const Icon(Icons.cable, size: 18),
                label: const Text('管理隧道'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一个 frpc 都没装时的警示条。
class _RuntimeMissing extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_outlined,
            size: 18,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '未安装 FRP 客户端运行环境，无法启动隧道。'
              '请前往「运行环境」下载一个 frpc。',
              style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
            ),
          ),
          TextButton(
            onPressed: () => context.push('/manage/runtime'),
            child: const Text('去安装'),
          ),
        ],
      ),
    );
  }
}

/// 「跑隧道用哪个 frpc」下拉。选项来自 `frp.runtimes`（已装好的那些）。
class _RuntimePicker extends ConsumerWidget {
  const _RuntimePicker({required this.state});

  final FrpcRuntimeList state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DropdownButtonFormField<String>(
      key: const Key('port_mapping_frpc_runtime'),
      initialValue: state.selected,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'FRP 运行环境',
        helperText: '装了多个版本时可以挑一个',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final runtime in state.runtimes)
          DropdownMenuItem(
            value: runtime.id,
            child: Text(runtime.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) async {
        final api = ref.read(frpApiProvider);
        if (api == null) return;
        try {
          await api.saveFrpcRuntime(value);
        } finally {
          ref.invalidate(frpRuntimesProvider);
        }
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// STUN 隧道
// ══════════════════════════════════════════════════════════════════════════

/// 「STUN 隧道」卡：每实例隧道行 + 全局调参 + 隧道日志。
///
/// 开关、PROXY protocol 与目标端口不在卡上 —— 它们按**实例**配
/// （实例设置 → STUN 隧道），`enabled && running` 的实例各跑一条隧道。
/// 卡里三截：
///
/// * **隧道状态** —— daemon 的投影（相位 / 公网地址 / 连接数 / 流量）；
/// * **全局设置** —— 服务器列表 / 保活 / 并发 / 连接日志，保存即重建；
/// * **隧道日志** —— 环形缓冲快照，可清空。
///
/// 相位与统计的翻转由 daemon 经 `stun.evt` 推过来（事件里就是完整快照）；
/// **速度统计与日志行不推**（每秒都在动的东西），卡片可见时每秒轮询一圈。
class _StunCard extends ConsumerStatefulWidget {
  const _StunCard();

  @override
  ConsumerState<_StunCard> createState() => _StunCardState();
}

class _StunCardState extends ConsumerState<_StunCard> {
  /// 在飞的轮询定时器（有隧道在探测 / 转发时才挂）。
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// 按「有没有活的隧道」开关轮询（幂等，`build` 里可以放心调）。
  ///
  /// 为什么不推事件：`stun.evt` 只在**相位 / 地址 / 错误**翻转时来，
  /// 速度统计（每秒采样）与日志行不推 —— 每行一条消息对一个调试看板太重了
  /// （同 FRP 运行日志的理由）。1 秒一次的小快照，代价可以忽略。
  void _syncPolling(bool active) {
    if (active) {
      _poll ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        unawaited(ref.read(stunStatusProvider.notifier).refresh());
        ref.invalidate(stunLogsProvider);
      });
    } else if (_poll != null) {
      _poll!.cancel();
      _poll = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snapshot = ref.watch(stunStatusProvider);
    final status = snapshot.value;
    _syncPolling(status?.hasActive ?? false);

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Icon(Icons.wifi_tethering, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'STUN 隧道',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '利用 NAT 打洞让玩家直连你的家宽，无需中转服务器。'
              '每个实例的开关、PROXY protocol 与目标端口在「实例设置 → STUN 隧道」里 —— '
              '实例启动时自动建立，停止时自动关闭。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (status == null && snapshot.hasError)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '读取 STUN 状态失败：${_errorLine(snapshot.error)}',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            )
          else if (status == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '读取中…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            const SizedBox(height: 12),
            _sectionTitle(context, '隧道状态'),
            if (status.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  '还没有实例开启 STUN 隧道。'
                  '在实例的「设置 → STUN 隧道」里打开开关 —— '
                  '实例启动时 daemon 会自动打洞建立隧道，停止时拆除。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final row in status.tunnels) _StunRow(row: row),
            const Divider(height: 24),
            _sectionTitle(context, '全局设置'),
            _StunSettingsForm(settings: status.settings),
            const Divider(height: 24),
            const _StunLogPanel(),
          ],
          // 给后来的人留一句：这张卡的能力边界
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Text(
              'STUN 隧道通过向 STUN 服务器发起探测，让路由器为本机保留一个公网端口，'
              '玩家直接连到该端口，速度取决于你的家宽上行，不消耗任何流量套餐。'
              '仅在全锥形 NAT（NAT1）下可用：移动数据、校园网以及运营商级 NAT（CGNAT）'
              '通常无法建立，此时请改用 FRP 隧道。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _errorLine(Object? error) =>
      error is DaemonException ? error.message : '$error';
}

/// 卡里的小节标题（隧道状态 / 全局设置 / 隧道日志）。
Widget _sectionTitle(BuildContext context, String text) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// 一行实例隧道：图标 + 实例名 + （地址 / 端口 / 流量）· 状态，外加复制按钮。
class _StunRow extends StatelessWidget {
  const _StunRow({required this.row});

  final StunTunnelRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, color) = switch (row.state) {
      StunTunnelState.running => (Icons.link, scheme.primary),
      StunTunnelState.probing => (Icons.sync, scheme.tertiary),
      StunTunnelState.failed => (Icons.link_off, scheme.error),
      StunTunnelState.idle => (Icons.link_off, scheme.onSurfaceVariant),
    };
    final address = row.publicAddress;
    return ListTile(
      key: Key('stun_row_${row.instanceId}'),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, size: 20, color: color),
      title: Text(
        row.instanceName.isEmpty ? row.instanceId : row.instanceName,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: row.state == StunTunnelState.failed
              ? scheme.error
              : scheme.onSurfaceVariant,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (address != null)
            IconButton(
              key: Key('stun_row_copy_${row.instanceId}'),
              tooltip: '复制公网直连地址',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () => _copyAddress(context, address),
            ),
          Text(row.state.label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  /// 那一行详情：按相位给出最有用的信息（同 UPnP 行的写法）。
  String get _subtitle {
    final target = row.targetPort == null ? null : '目标 ${row.targetPort}';
    switch (row.state) {
      case StunTunnelState.running:
        final up = formatSpeed(row.upSpeed);
        final down = formatSpeed(row.downSpeed);
        return [
          if (row.publicAddress != null) '公网 ${row.publicAddress}',
          if (row.localPort != null && target != null) '${row.localPort} → $target',
          '连接 ${row.activeConnections}/${row.maxConnections}',
          if (up.isNotEmpty || down.isNotEmpty) '↑$up ↓$down',
        ].join(' · ');
      case StunTunnelState.probing:
        return ['正在探测公网映射…', ?target].join(' · ');
      case StunTunnelState.failed:
        return [row.error ?? '隧道建立失败', ?target].join(' · ');
      case StunTunnelState.idle:
        return [
          !row.enabled ? '开关已关闭' : (row.running ? '等待启动' : '实例未在运行'),
          ?target,
        ].join(' · ');
    }
  }

  Future<void> _copyAddress(BuildContext context, String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text('已复制 $address')));
  }
}

/// 全局设置表单：服务器列表 / 并发上限 / 保活间隔 / 连接日志。
///
/// 表单只在第一次拿到快照时回填（V1 同款），之后不再跟着快照走 ——
/// 否则每秒的轮询刷新会把正在编辑的输入冲掉。保存后拿 daemon 的返回
/// 再回填一次（越界输入会被夹到合法区间，以返回值为准）。
class _StunSettingsForm extends ConsumerStatefulWidget {
  const _StunSettingsForm({required this.settings});

  final StunSettings settings;

  @override
  ConsumerState<_StunSettingsForm> createState() => _StunSettingsFormState();
}

class _StunSettingsFormState extends ConsumerState<_StunSettingsForm> {
  late final TextEditingController _servers;
  late final TextEditingController _keepAlive;
  late final TextEditingController _maxConnections;
  late bool _showLog;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _servers = TextEditingController(text: widget.settings.servers.join('\n'));
    _keepAlive = TextEditingController(
      text: '${widget.settings.keepAliveSeconds}',
    );
    _maxConnections = TextEditingController(
      text: '${widget.settings.maxConnections}',
    );
    _showLog = widget.settings.showConnectionLog;
  }

  @override
  void dispose() {
    _servers.dispose();
    _keepAlive.dispose();
    _maxConnections.dispose();
    super.dispose();
  }

  /// 服务器列表：每行一台，空行丢掉（空列表 = 用内置的，daemon 会回退）。
  List<String> _parseServers() => [
    for (final line in _servers.text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  Future<void> _save() async {
    final api = ref.read(stunApiProvider);
    if (api == null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('未连接到守护进程')));
      return;
    }
    setState(() => _saving = true);
    try {
      final status = await api.saveSettings(
        servers: _parseServers(),
        keepAliveSeconds: int.tryParse(_keepAlive.text.trim()),
        maxConnections: int.tryParse(_maxConnections.text.trim()),
        showConnectionLog: _showLog,
      );
      if (!mounted) return;
      // daemon 夹取后的值回填（越界 / 非法输入以它为准）
      _servers.text = status.settings.servers.join('\n');
      _keepAlive.text = '${status.settings.keepAliveSeconds}';
      _maxConnections.text = '${status.settings.maxConnections}';
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('设置已保存')));
    } on DaemonException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('保存失败：${error.message}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('port_mapping_stun_servers'),
            controller: _servers,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'STUN 服务器',
              hintText: 'fwa.lifesizecloud.com',
              helperText: '每行一台（host 或 host:port）；留空使用内置列表',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('port_mapping_stun_max_connections'),
                  controller: _maxConnections,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '最大并发连接数',
                    helperText: '1-1024',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('port_mapping_stun_keep_alive'),
                  controller: _keepAlive,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '保活间隔（秒）',
                    helperText: '5-300',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          SwitchListTile(
            key: const Key('port_mapping_stun_show_log'),
            contentPadding: EdgeInsets.zero,
            title: const Text('记录连接日志'),
            subtitle: const Text('把每条入站连接的建立 / 断开写进下方日志'),
            value: _showLog,
            onChanged: _saving
                ? null
                : (value) => setState(() => _showLog = value),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              key: const Key('port_mapping_stun_save'),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: Text(_saving ? '保存中…' : '保存设置'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 隧道日志面板：环形缓冲快照 + 清空按钮。
///
/// 日志行 daemon 不推事件 —— 卡片可见时由 `_StunCard` 每秒 invalidate
/// `stunLogsProvider` 重拉；「清空」发给 daemon 后同样重拉。
/// 有新行到达才自动滚到底：轮询每秒都有返回，别打扰正在往上翻的人。
class _StunLogPanel extends ConsumerStatefulWidget {
  const _StunLogPanel();

  @override
  ConsumerState<_StunLogPanel> createState() => _StunLogPanelState();
}

class _StunLogPanelState extends ConsumerState<_StunLogPanel> {
  final _scroll = ScrollController();
  int _lastCount = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _clear() async {
    final api = ref.read(stunApiProvider);
    if (api == null) return;
    try {
      await api.clearLogs();
    } on DaemonException {
      // 清日志失败没什么好打断用户的（下一次轮询就回到真值）
    }
    if (!mounted) return;
    ref.invalidate(stunLogsProvider);
  }

  /// 有新行才滚到底（`maxScrollExtent` 要等新行布局完才准，排到帧后）。
  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final logs = ref.watch(stunLogsProvider).value ?? StunLogs.empty;
    if (logs.count != _lastCount) {
      _lastCount = logs.count;
      _jumpToBottom();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '隧道日志',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton.icon(
                key: const Key('port_mapping_stun_clear_logs'),
                onPressed: _clear,
                icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                label: const Text('清空'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(8),
            child: logs.lines.isEmpty
                ? Center(
                    child: Text(
                      '暂无日志',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: EdgeInsets.zero,
                    itemCount: logs.lines.length,
                    itemBuilder: (_, index) => Text(
                      _lineText(logs.lines[index]),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  /// 一行日志：`[12:03:45] [实例名] 文本`（没有实例归属的全局行不标实例）。
  static String _lineText(StunLogLine line) {
    final time = _timeText(line.timeMs);
    final name = line.instanceName;
    final who = name == null || name.isEmpty ? '' : '[$name] ';
    final prefix = time == null ? '' : '$time ';
    return '$prefix$who${line.text}';
  }

  static String? _timeText(int? timeMs) {
    if (timeMs == null) return null;
    final time = DateTime.fromMillisecondsSinceEpoch(timeMs);
    String two(int value) => '$value'.padLeft(2, '0');
    return '[${two(time.hour)}:${two(time.minute)}:${two(time.second)}]';
  }
}

// ══════════════════════════════════════════════════════════════════════════
// 路由器端口映射（UPnP）
// ══════════════════════════════════════════════════════════════════════════

/// 「路由器端口映射」卡：网关状态 + 每实例映射行 + 重新探测。
///
/// 开关与参数不在卡上 —— 它们按**实例**配（实例设置 → 路由器端口映射），
/// 卡里看的是 daemon 的投影：发现到哪个网关、公网 IP、每行映射到哪一步。
/// 状态变化由 daemon 经 `upnp.evt` 推过来（事件里就是完整快照）。
class _UpnpCard extends ConsumerStatefulWidget {
  const _UpnpCard();

  @override
  ConsumerState<_UpnpCard> createState() => _UpnpCardState();
}

class _UpnpCardState extends ConsumerState<_UpnpCard> {
  bool _probing = false;

  Future<void> _probe() async {
    if (ref.read(upnpApiProvider) == null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('未连接到守护进程')));
      return;
    }
    setState(() => _probing = true);
    try {
      await ref.read(upnpStatusProvider.notifier).probe();
    } on DaemonException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('探测失败：${error.message}')));
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snapshot = ref.watch(upnpStatusProvider);
    final status = snapshot.value;
    final busy = _probing || snapshot.isLoading;

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Icon(Icons.router_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '路由器端口映射',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: const Key('port_mapping_upnp_probe'),
                  onPressed: busy ? null : _probe,
                  icon: _probing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(_probing ? '探测中…' : '重新探测'),
                ),
              ],
            ),
          ),
          if (status == null && snapshot.hasError)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '读取 UPnP 状态失败：${_errorLine(snapshot.error)}',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            )
          else if (status == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '读取中…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            _GatewayLine(gateway: status.gateway),
            if (status.gateway.cgnat) const _CgnatBanner(),
            if (status.gateway.state == UpnpGatewayState.error &&
                status.gateway.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  status.gateway.error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
            const Divider(height: 24),
            if (status.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  '还没有实例开启端口映射。'
                  '在实例的「设置 → 路由器端口映射」里打开开关 —— '
                  '实例启动时 daemon 会自动在路由器上加映射，停止时撤销。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final row in status.mappings) _UpnpRow(row: row),
          ],
          // 给后来的人留一句：这张卡的能力边界
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Text(
              '开关、协议与外部端口按实例配置。需路由器支持 UPnP'
              '（多数家用路由器默认关闭，要在路由器后台打开）。'
              '若公网 IP 是运营商级 NAT（CGNAT），映射成功外网也进不来，请改用 FRP 隧道。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _errorLine(Object? error) =>
      error is DaemonException ? error.message : '$error';
}

/// 网关状态行：一枚状态圆点 + 网关地址 / 公网 IP 一句话。
class _GatewayLine extends StatelessWidget {
  const _GatewayLine({required this.gateway});

  final UpnpGateway gateway;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = switch (gateway.state) {
      UpnpGatewayState.ready => scheme.primary,
      UpnpGatewayState.searching => scheme.tertiary,
      UpnpGatewayState.error => scheme.error,
      UpnpGatewayState.unknown => scheme.onSurfaceVariant,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            gateway.state.label,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 那一句话：按状态给出最有用的信息。
  String get _detail {
    switch (gateway.state) {
      case UpnpGatewayState.unknown:
        return '还没探测过网关（实例启动时会自动发现）';
      case UpnpGatewayState.searching:
        return '正在搜索局域网里的 UPnP 网关…';
      case UpnpGatewayState.error:
        return '';
      case UpnpGatewayState.ready:
        final parts = <String>[
          if (gateway.address != null) '网关 ${gateway.address}',
          if (gateway.externalIp != null)
            '公网 IP ${gateway.externalIp}'
          else
            '公网 IP 未知',
        ];
        return parts.join(' · ');
    }
  }
}

/// CGNAT 警示条（公网 IP 是运营商级 NAT 地址）。
class _CgnatBanner extends StatelessWidget {
  const _CgnatBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_outlined,
            size: 18,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '公网 IP 是运营商级 NAT（CGNAT）地址：映射成功外网也连不进来，'
              '建议改用 FRP 隧道。',
              style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一行实例映射：图标 + 实例名 + （地址 / 原因）· 端口 + 状态。
class _UpnpRow extends StatelessWidget {
  const _UpnpRow({required this.row});

  final UpnpMappingRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, color) = switch (row.state) {
      UpnpMapState.mapped => (Icons.link, scheme.primary),
      UpnpMapState.mapping => (Icons.sync, scheme.tertiary),
      UpnpMapState.failed => (Icons.link_off, scheme.error),
      UpnpMapState.idle => (Icons.link_off, scheme.onSurfaceVariant),
    };
    return ListTile(
      key: Key('upnp_row_${row.instanceId}'),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, size: 20, color: color),
      title: Text(
        row.instanceName.isEmpty ? row.instanceId : row.instanceName,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: row.state == UpnpMapState.failed
              ? scheme.error
              : scheme.onSurfaceVariant,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        row.state.label,
        style: TextStyle(fontSize: 12, color: color),
      ),
    );
  }

  String get _subtitle => switch (row.state) {
    UpnpMapState.mapped =>
      '${row.publicAddress ?? '已映射'} · ${row.portText}',
    UpnpMapState.mapping => '正在写入映射 · ${row.portText}',
    UpnpMapState.failed => '${row.error ?? '映射失败'} · ${row.portText}',
    UpnpMapState.idle => !row.enabled
        ? '开关已关闭 · ${row.portText}'
        : row.running
        ? '等待映射 · ${row.portText}'
        : '实例未在运行 · ${row.portText}',
  };
}

// ══════════════════════════════════════════════════════════════════════════
// 还没做的那些：字段摆全，整张置灰
// ══════════════════════════════════════════════════════════════════════════

/// 一张「还没做」的卡。
///
/// 每一块的字段与顺序都摆全，但**全部不可操作**（`onPressed: null` /
/// 只读的 `InputDecorator`）。[dependsOn] 写明卡在哪一步 —— 做的时候按它去补后端。
class _PlannedCard extends StatelessWidget {
  const _PlannedCard({
    required this.icon,
    required this.title,
    required this.switchTitle,
    required this.switchSubtitle,
    required this.dependsOn,
    this.fields = const [],
    this.toggles = const [],
    this.actions = const [],
    this.note,
  });

  final IconData icon;
  final String title;

  /// 开关的标题与副标题。
  final String switchTitle;
  final String switchSubtitle;

  /// 这一卡还缺什么（注释给开发者看，只读行给用户看）。
  final String dependsOn;

  /// `(标签, 提示 / 占位值)` 的只读字段。
  final List<(String, String)> fields;

  /// 置灰的开关 `(标题, 副标题)`。
  final List<(String, String)> toggles;

  /// 置灰的按钮文案。
  final List<String> actions;

  /// 卡片底部那段说明。
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                // 一眼看出「这张还没做」，不用点下去才知道
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '未实现',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: Text(switchTitle),
            subtitle: Text(switchSubtitle),
            value: false,
            // 置灰：依赖还没落地（见 dependsOn）
            onChanged: null,
          ),
          for (final (label, hint) in fields)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: label,
                  helperText: hint.isEmpty ? null : hint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  enabled: false,
                ),
                child: const SizedBox(height: 16),
              ),
            ),
          for (final (toggleTitle, toggleSubtitle) in toggles)
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Text(toggleTitle),
              subtitle: toggleSubtitle.isEmpty ? null : Text(toggleSubtitle),
              value: false,
              onChanged: null,
            ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final label in actions)
                    OutlinedButton(onPressed: null, child: Text(label)),
                ],
              ),
            ),
          if (note case final text?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          // 给后来的人留一句：这张卡缺的是哪一块
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Text(
              '待实现：$dependsOn',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

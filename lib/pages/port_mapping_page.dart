import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter/services.dart';

import '../config/ddns_store.dart';
import '../config/network_store.dart';
import '../config/stun_store.dart';
import '../frp/frp_models.dart';
import '../frp/frp_provider.dart';
import '../frp/frp_registry_store.dart';
import '../i18n/locale_scope.dart';
import '../widgets/error_dialog.dart';
import '../server/runtime_service.dart';
import '../server/server_scope.dart';
import '../stun/stun_tunnel_service.dart';
import '../tunnel/tunnel_service.dart';
import '../widgets/ec_preference.dart';
import '../widgets/ec_text_field.dart';
import '../widgets/miuix_dialog.dart';
import '../widgets/miuix_snackbar.dart';
import 'frp/frp_tunnel_list_page.dart';
import 'runtime_page.dart';

/// 网络映射页：UPnP 自动端口映射 + FRP 隧道，均随服务器自动启停。
///
/// 所有配置持久化到 config/network.json。
class PortMappingPage extends StatefulWidget {
  const PortMappingPage({super.key});

  @override
  State<PortMappingPage> createState() => _PortMappingPageState();
}

class _PortMappingPageState extends State<PortMappingPage> {
  final _tunnel = TunnelService();
  final _stun = StunTunnelService.instance;

  // —— UPnP / FRP 开关状态 ——
  bool _upnpEnabled = false;
  bool _tunnelEnabled = false;

  // —— UPnP 外网端口与协议 ——
  final _upnpExternalPort = TextEditingController();
  String _upnpProtocol = 'tcp';

  // —— DDNS 配置 ——
  DdnsConfig _ddnsConfig = const DdnsConfig();
  final _ddnsDomain = TextEditingController();
  final _ddnsHost = TextEditingController();
  final _ddnsTokenId = TextEditingController();
  final _ddnsToken = TextEditingController();
  final _ddnsCustomUrl = TextEditingController();
  final _ddnsInterval = TextEditingController();
  bool _ddnsUpdating = false;

  // —— frpc 运行时 ——
  List<RuntimeInfo> _frpcRuntimes = [];
  String? _selectedFrpcRuntimeId;

  // —— 默认映射隧道（FRP 开关打开时随服务端启停的隧道）——
  List<SavedFrpTunnel> _savedTunnels = [];
  String? _defaultTunnelId;

  // —— 隧道运行状态 ——
  // _tunnelStatus: 非 null 表示 frpc 正在运行/连接中（preparing/starting/running）。
  // _tunnelExitCode: 非 null 表示 frpc 已退出（保留日志框以便排查异常退出原因）。
  // 两者同时为 null 表示从未启动或已清空状态。
  String? _tunnelStatus;
  int? _tunnelExitCode;
  final List<String> _logs = [];
  final _logScroll = ScrollController();
  StreamSubscription<TunnelEvent>? _sub;

  // —— STUN 隧道配置与日志 ——
  StunConfig _stunConfig = const StunConfig();
  final _stunLocalPort = TextEditingController();
  final _stunMaxConnections = TextEditingController();
  final _stunKeepAlive = TextEditingController();
  final List<String> _stunLogs = [];
  final _stunLogScroll = ScrollController();
  StreamSubscription<String>? _stunLogSub;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _subscribe();
    RuntimeService.refreshSignal.addListener(_onRuntimesChanged);
    _stun.addListener(_onStunChanged);
  }

  @override
  void dispose() {
    RuntimeService.refreshSignal.removeListener(_onRuntimesChanged);
    _stun.removeListener(_onStunChanged);
    _sub?.cancel();
    _stunLogSub?.cancel();
    _logScroll.dispose();
    _stunLogScroll.dispose();
    _upnpExternalPort.dispose();
    _ddnsDomain.dispose();
    _ddnsHost.dispose();
    _ddnsTokenId.dispose();
    _ddnsToken.dispose();
    _ddnsCustomUrl.dispose();
    _ddnsInterval.dispose();
    _stunLocalPort.dispose();
    _stunMaxConnections.dispose();
    _stunKeepAlive.dispose();
    super.dispose();
  }

  /// 隧道服务状态/流量变化时刷新卡片（服务每秒推送一次流量统计）。
  void _onStunChanged() {
    if (mounted) setState(() {});
  }

  // —— 加载 ——

  Future<void> _loadAll() async {
    final upnp = await NetworkStore.loadUpnpEnabled();
    final extPort = await NetworkStore.loadUpnpExternalPort();
    final protocol = await NetworkStore.loadUpnpProtocol();
    final tunnel = await NetworkStore.loadTunnelEnabled();
    final runtimeId = await NetworkStore.loadFrpcRuntimeId();
    final runtimes = await const RuntimeService().installedFrpcRuntimes();
    final savedTunnels = await FrpRegistryStore.load();
    final defaultTunnelId = await NetworkStore.loadDefaultFrpTunnelId();
    final ddns = await DdnsStore.load();
    final stun = await StunStore.load();
    if (!mounted) return;
    if (stun.enabled) _subscribeStunLog();
    setState(() {
      _stunConfig = stun;
      _stunLocalPort.text = stun.localPort?.toString() ?? '';
      _stunMaxConnections.text = stun.maxConnections.toString();
      _stunKeepAlive.text = stun.keepAliveSeconds.toString();
      _upnpEnabled = upnp;
      _upnpExternalPort.text = extPort?.toString() ?? '';
      _upnpProtocol = protocol;
      _tunnelEnabled = tunnel;
      _ddnsConfig = ddns;
      _ddnsDomain.text = ddns.domain;
      _ddnsHost.text = ddns.host;
      _ddnsTokenId.text = ddns.tokenId;
      _ddnsToken.text = ddns.token;
      _ddnsCustomUrl.text = ddns.customUrl;
      _ddnsInterval.text = ddns.intervalMinutes.toString();
      _frpcRuntimes = runtimes;
      if (runtimes.isNotEmpty) {
        final valid = runtimes.any((r) => r.id == runtimeId);
        _selectedFrpcRuntimeId = valid ? runtimeId : runtimes.first.id;
      } else {
        _selectedFrpcRuntimeId = null;
      }
      _savedTunnels = savedTunnels;
      // 已保存的默认隧道被删除时按未设置处理（同 frpcRuntimeId 校验模式）。
      _defaultTunnelId = savedTunnels.any((t) => t.localId == defaultTunnelId)
          ? defaultTunnelId
          : null;
    });
  }

  void _onRuntimesChanged() {
    if (mounted) _loadAll();
  }

  // —— 保存 + 即时生效 ——

  Future<void> _setUpnp(bool value) async {
    await NetworkStore.saveUpnpEnabled(value);
    await _saveUpnpSettings();
    if (!mounted) return;
    setState(() => _upnpEnabled = value);
    final server = ServerScope.of(context);
    if (value) {
      server.enableUpnpNow();
    } else {
      server.disableUpnpNow();
    }
  }

  Future<void> _saveUpnpSettings() async {
    final text = _upnpExternalPort.text.trim();
    final port = text.isEmpty ? null : int.tryParse(text);
    await NetworkStore.saveUpnpExternalPort(port);
    await NetworkStore.saveUpnpProtocol(_upnpProtocol);
  }

  // —— DDNS 保存 + 即时生效 ——

  /// 从表单收集当前 DDNS 配置（enabled 沿用现值，除非显式传入）。
  DdnsConfig _collectDdnsConfig({bool? enabled}) {
    final interval = int.tryParse(_ddnsInterval.text.trim());
    return _ddnsConfig.copyWith(
      enabled: enabled,
      domain: _ddnsDomain.text.trim(),
      host: _ddnsHost.text.trim(),
      tokenId: _ddnsTokenId.text.trim(),
      token: _ddnsToken.text.trim(),
      customUrl: _ddnsCustomUrl.text.trim(),
      intervalMinutes: (interval == null || interval < 1) ? 10 : interval,
    );
  }

  Future<void> _setDdns(bool value) async {
    final config = _collectDdnsConfig(enabled: value);
    await DdnsStore.save(config);
    if (!mounted) return;
    setState(() => _ddnsConfig = config);
    final server = ServerScope.of(context);
    if (value) {
      server.enableDdnsNow();
    } else {
      server.disableDdnsNow();
    }
  }

  Future<void> _saveDdnsSettings() async {
    final config = _collectDdnsConfig();
    await DdnsStore.save(config);
    if (!mounted) return;
    setState(() => _ddnsConfig = config);
    // 运行中则重启 DDNS 周期任务以应用新配置。
    ServerScope.of(context).applyDdnsConfig();
    showMiuixSnackbar(context.tr('portMapping.saved'));
  }

  /// 保存配置后立即强制推送一次解析记录，用于验证凭据与域名配置。
  Future<void> _updateDdnsNow() async {
    final config = _collectDdnsConfig();
    await DdnsStore.save(config);
    if (!mounted) return;
    setState(() {
      _ddnsConfig = config;
      _ddnsUpdating = true;
    });
    final trans = LocaleScope.of(context).translations;
    try {
      final result = await ServerScope.of(context).updateDdnsOnce();
      if (!mounted) return;
      if (result.success) {
        showMiuixSnackbar(
          trans.get('portMapping.ddnsUpdateSuccess', {
            'ip': [result.ipv4, result.ipv6].whereType<String>().join(' / '),
          }),
        );
      } else {
        showErrorDialog(
          context,
          trans.get('portMapping.ddnsUpdateFailed', {
            'error': result.error ?? '',
          }),
        );
      }
    } finally {
      if (mounted) setState(() => _ddnsUpdating = false);
    }
  }

  // —— STUN 隧道保存 + 即时生效 ——

  /// 从表单收集当前 STUN 配置（enabled 沿用现值，除非显式传入）。
  StunConfig _collectStunConfig({bool? enabled}) {
    final port = int.tryParse(_stunLocalPort.text.trim());
    final maxConn = int.tryParse(_stunMaxConnections.text.trim());
    final keepAlive = int.tryParse(_stunKeepAlive.text.trim());
    return _stunConfig.copyWith(
      enabled: enabled,
      // 端口留空表示跟随服务端实际监听端口。
      localPort: (port != null && port > 0 && port < 65536) ? port : null,
      clearLocalPort: port == null || port <= 0 || port >= 65536,
      maxConnections: (maxConn == null || maxConn < 1) ? 128 : maxConn,
      keepAliveSeconds: (keepAlive == null || keepAlive < 5) ? 20 : keepAlive,
    );
  }

  Future<void> _setStun(bool value) async {
    final config = _collectStunConfig(enabled: value);
    await StunStore.save(config);
    if (!mounted) return;
    setState(() => _stunConfig = config);
    if (value) {
      _subscribeStunLog();
    } else {
      _stunLogSub?.cancel();
      _stunLogSub = null;
    }
    final server = ServerScope.of(context);
    if (value) {
      server.enableStunNow();
    } else {
      server.disableStunNow();
    }
  }

  Future<void> _saveStunSettings() async {
    final config = _collectStunConfig();
    await StunStore.save(config);
    if (!mounted) return;
    setState(() {
      _stunConfig = config;
      // 归一化后的值回填输入框（越界/非法输入会被夹到合法区间）。
      _stunMaxConnections.text = config.maxConnections.toString();
      _stunKeepAlive.text = config.keepAliveSeconds.toString();
    });
    // 运行中则重建隧道以应用新配置（公网端口会变化）。
    ServerScope.of(context).applyStunConfig();
    showMiuixSnackbar(context.tr('portMapping.saved'));
  }

  void _subscribeStunLog() {
    if (_stunLogSub != null) return;
    // 订阅时会先回放历史日志，先清空本地副本避免开关来回切换后重复堆积。
    _stunLogs.clear();
    _stunLogSub = _stun.logs().listen((line) {
      if (!mounted) return;
      setState(() {
        _stunLogs.add(line);
        if (_stunLogs.length > 500) {
          _stunLogs.removeRange(0, _stunLogs.length - 500);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_stunLogScroll.hasClients) {
          _stunLogScroll.jumpTo(_stunLogScroll.position.maxScrollExtent);
        }
      });
    });
  }

  /// 复制公网直连地址到剪贴板。
  Future<void> _copyStunAddress() async {
    final address = _stun.publicAddress?.toString();
    final trans = LocaleScope.of(context).translations;
    if (address == null) {
      showMiuixSnackbar(trans.get('portMapping.stunNoAddress'));
      return;
    }
    await Clipboard.setData(ClipboardData(text: address));
    showMiuixSnackbar(trans.get('portMapping.stunCopied'));
  }

  Future<void> _setTunnel(bool value) async {
    if (value && _frpcRuntimes.isEmpty) {
      _showFrpcRequiredDialog();
      return;
    }
    // 开启前必须有可用的映射隧道：无隧道时引导去「映射隧道」页创建。
    if (value && _savedTunnels.isEmpty) {
      _showTunnelRequiredDialog();
      return;
    }
    // 未选默认隧道时自动选第一条，保证开关打开即有明确的启动目标。
    if (value && _defaultTunnelId == null) {
      _defaultTunnelId = _savedTunnels.first.localId;
      await NetworkStore.saveDefaultFrpTunnelId(_defaultTunnelId);
    }
    await NetworkStore.saveTunnelEnabled(value);
    if (!mounted) return;
    setState(() => _tunnelEnabled = value);
    final server = ServerScope.of(context);
    if (value) {
      server.enableTunnelNow(runtimeId: _selectedFrpcRuntimeId);
    } else {
      server.disableTunnelNow();
    }
  }

  /// 保存默认隧道选择；自动隧道正在运行时立即重启换用新配置。
  Future<void> _setDefaultTunnel(String? localId) async {
    await NetworkStore.saveDefaultFrpTunnelId(localId);
    if (!mounted) return;
    setState(() => _defaultTunnelId = localId);
    final server = ServerScope.of(context);
    if (server.isTunnelActive && !server.isStandaloneTunnel) {
      await server.restartTunnel();
    }
  }

  /// 未创建任何映射隧道，提示用户前往「映射隧道」页新增。
  Future<void> _showTunnelRequiredDialog() async {
    final tr = LocaleScope.of(context).translations;
    final go = await showMiuixConfirm(
      context,
      title: tr.get('portMapping.noTunnelTitle'),
      message: tr.get('portMapping.noTunnelMessage'),
      cancelLabel: tr.get('common.cancel'),
      confirmLabel: tr.get('portMapping.manageTunnels'),
    );
    if (go == true && mounted) _openTunnelManager();
  }

  /// 未安装 frpc 运行时，提示用户前往「运行环境」页导入。
  Future<void> _showFrpcRequiredDialog() async {
    final tr = LocaleScope.of(context).translations;
    final go = await showMiuixConfirm(
      context,
      title: tr.get('server.runtimeRequiredTitle'),
      message: tr.get('portMapping.frpcRequiredContent'),
      cancelLabel: tr.get('common.cancel'),
      confirmLabel: tr.get('server.runtimeRequiredAction'),
    );
    if (go == true && mounted) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const RuntimePage()));
      if (mounted) _loadAll();
    }
  }

  // —— 编辑配置文件 ——

  /// 进入「映射隧道」子页面：登录各映射平台、管理与运行隧道。
  /// 返回后重载，同步隧道增删对默认隧道下拉框的影响。
  Future<void> _openTunnelManager() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FrpTunnelListPage()));
    if (mounted) _loadAll();
  }

  // —— 隧道状态订阅 ——

  void _subscribe() {
    _sub = _tunnel.events().listen((e) {
      if (!mounted) return;
      if (e is TunnelLogEvent) {
        setState(() {
          _logs.add(e.line);
          if (_logs.length > 2000) _logs.removeRange(0, _logs.length - 2000);
        });
        _scrollLogToBottom();
      } else if (e is TunnelStateEvent) {
        setState(() {
          if (e.status != null) {
            // 运行中 / 连接中 / 准备中：清除可能的退出码。
            _tunnelStatus = e.status;
            _tunnelExitCode = null;
          } else if (e.exitCode != null) {
            // frpc 已退出：保留日志框，记录退出码供排查。
            _tunnelStatus = null;
            _tunnelExitCode = e.exitCode;
          }
          // status == null && exitCode == null：状态回放（未运行），不改变状态。
        });
      }
    });
  }

  void _scrollLogToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  // —— UI ——

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixScaffold(
      topBar: EcTopAppBar(title: context.tr('portMapping.title')),
      content: (padding) => Padding(
        padding: padding,
        // padding.top 已含顶栏（连同状态栏）高度，故这里的 SafeArea 只保留
        // 左右与底部，top 置 false，否则状态栏高度会被重复计入。
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildFrpcCard(theme),
              if (_tunnelEnabled) ...[
                const SizedBox(height: 16),
                _buildLogSection(theme),
              ],
              const SizedBox(height: 16),
              _buildStunCard(theme),
              const SizedBox(height: 16),
              _buildUpnpCard(theme),
              const SizedBox(height: 16),
              _buildDdnsCard(theme),
            ],
          ),
        ),
      ),
    );
  }

  // —— STUN 隧道卡片 ——

  Widget _buildStunCard(MiuixThemeData theme) {
    final status = _stun.status;
    final running = status == StunTunnelStatus.running;
    final address = _stun.publicAddress?.toString();
    final serverRunning = ServerScope.of(context).isRunning;

    final (String statusText, Color statusColor) = switch (status) {
      StunTunnelStatus.running => (
        context.tr('portMapping.stunRunning'),
        theme.colors.primary,
      ),
      StunTunnelStatus.probing => (
        context.tr('portMapping.stunProbing'),
        theme.colors.onTertiaryContainer,
      ),
      StunTunnelStatus.failed => (
        context.tr('portMapping.stunFailed'),
        theme.colors.error,
      ),
      StunTunnelStatus.stopped => (
        context.tr('portMapping.stunNotStarted'),
        theme.colors.outline,
      ),
    };

    return MiuixCard(
      insideMargin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.hub_outlined, size: 20, color: theme.colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('portMapping.stunCardTitle'),
                    style: theme.textStyles.subtitle.copyWith(
                      color: theme.colors.primary,
                    ),
                  ),
                ),
                if (_stunConfig.enabled)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusText,
                      style: theme.textStyles.footnote2.copyWith(
                        color: statusColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          MiuixSwitchPreference(
            title: context.tr('portMapping.enableStun'),
            summary: context.tr('portMapping.enableStunSubtitle'),
            value: _stunConfig.enabled,
            onChanged: _setStun,
          ),
          if (_stunConfig.enabled) ...[
            // 公网直连地址 + 复制。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Padding(
                padding: EdgeInsets.zero,
                child: MiuixCard(
                  insideMargin: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  colors: MiuixCardColors(
                    color: theme.colors.surfaceContainerHighest,
                    contentColor: MiuixTheme.of(context).colors.onSurface,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.public, size: 18, color: statusColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('portMapping.stunPublicAddress'),
                              style: theme.textStyles.footnote2.copyWith(
                                color: theme.colors.onSurfaceVariantSummary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            SelectableText(
                              address ??
                                  (!serverRunning
                                      ? context.tr(
                                          'portMapping.stunServerNotRunning',
                                        )
                                      : statusText),
                              style: theme.textStyles.body2.copyWith(
                                fontWeight: FontWeight.w600,
                                fontFamily: address != null
                                    ? 'monospace'
                                    : null,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      MiuixIconButton(
                        onPressed: address == null ? null : _copyStunAddress,
                        child: MiuixIcon(icon: Icons.copy, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 建立失败时展示具体原因。
            if (status == StunTunnelStatus.failed && _stun.lastError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: MiuixCard(
                    insideMargin: const EdgeInsets.all(12),
                    colors: MiuixCardColors(
                      color: theme.colors.errorContainer,
                      contentColor: MiuixTheme.of(context).colors.onSurface,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_outlined,
                          size: 18,
                          color: theme.colors.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _stun.lastError!,
                            style: theme.textStyles.footnote1.copyWith(
                              color: theme.colors.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // 运行时的连接数与流量统计。
            if (running)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _stunStat(
                      theme,
                      Icons.people_outline,
                      context.tr('portMapping.stunConnections', {
                        'current': '${_stun.activeConnections}',
                        'max': '${_stun.maxConnections}',
                      }),
                    ),
                    const SizedBox(height: 4),
                    _stunStat(
                      theme,
                      Icons.speed_outlined,
                      context.tr('portMapping.stunSpeed', {
                        'up': StunTunnelService.formatBytes(_stun.uploadSpeed),
                        'down': StunTunnelService.formatBytes(
                          _stun.downloadSpeed,
                        ),
                      }),
                    ),
                    const SizedBox(height: 4),
                    _stunStat(
                      theme,
                      Icons.data_usage_outlined,
                      context.tr('portMapping.stunTraffic', {
                        'up': StunTunnelService.formatBytes(_stun.totalUpload),
                        'down': StunTunnelService.formatBytes(
                          _stun.totalDownload,
                        ),
                      }),
                    ),
                  ],
                ),
              ),
            // 端口与并发配置。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _field(
                      _stunLocalPort,
                      context.tr('portMapping.stunLocalPort'),
                      hint: context.tr('portMapping.stunLocalPortHint'),
                      number: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      _stunMaxConnections,
                      context.tr('portMapping.stunMaxConnections'),
                      hint: '128',
                      number: true,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _field(
                _stunKeepAlive,
                context.tr('portMapping.stunKeepAlive'),
                hint: '20',
                number: true,
              ),
            ),
            MiuixSwitchPreference(
              title: context.tr('portMapping.stunProxyProtocol'),
              summary: context.tr('portMapping.stunProxyProtocolSubtitle'),
              value: _stunConfig.proxyProtocol,
              onChanged: (v) => setState(() {
                _stunConfig = _stunConfig.copyWith(proxyProtocol: v);
              }),
            ),
            MiuixSwitchPreference(
              title: context.tr('portMapping.stunShowConnLog'),
              summary: context.tr('portMapping.stunShowConnLogSubtitle'),
              value: _stunConfig.showConnectionLog,
              onChanged: (v) => setState(() {
                _stunConfig = _stunConfig.copyWith(showConnectionLog: v);
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: MiuixButton(
                  onPressed: _saveStunSettings,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MiuixIcon(icon: Icons.save, size: 18),
                      const SizedBox(width: 8),
                      MiuixText(context.tr('portMapping.saveStunConfig')),
                    ],
                  ),
                ),
              ),
            ),
            // NAT 类型限制说明。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Padding(
                padding: EdgeInsets.zero,
                child: MiuixCard(
                  insideMargin: const EdgeInsets.all(12),
                  colors: MiuixCardColors(
                    color: theme.colors.surfaceContainerHighest,
                    contentColor: MiuixTheme.of(context).colors.onSurface,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: theme.colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.tr('portMapping.stunHint'),
                          style: theme.textStyles.footnote1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _buildStunLogSection(theme),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stunStat(MiuixThemeData theme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colors.onSurfaceVariantSummary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textStyles.footnote1.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStunLogSection(MiuixThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              context.tr('portMapping.stunLog'),
              style: theme.textStyles.subtitle.copyWith(
                color: theme.colors.primary,
              ),
            ),
            const Spacer(),
            MiuixIconButton(
              onPressed: () {
                _stun.clearLog();
                setState(() => _stunLogs.clear());
              },
              child: MiuixIcon(
                icon: Icons.cleaning_services_outlined,
                size: 18,
              ),
            ),
          ],
        ),
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: theme.colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(8),
          child: _stunLogs.isEmpty
              ? Center(
                  child: Text(
                    context.tr('portMapping.noLogs'),
                    style: theme.textStyles.footnote1.copyWith(
                      color: theme.colors.onSurfaceVariantSummary,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _stunLogScroll,
                  itemCount: _stunLogs.length,
                  itemBuilder: (_, i) => Text(
                    _stunLogs[i],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  // —— UPnP 卡片 ——

  Widget _buildUpnpCard(MiuixThemeData theme) {
    return MiuixCard(
      insideMargin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.router_outlined,
                  size: 20,
                  color: theme.colors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  context.tr('portMapping.upnpCardTitle'),
                  style: theme.textStyles.subtitle.copyWith(
                    color: theme.colors.primary,
                  ),
                ),
              ],
            ),
          ),
          MiuixSwitchPreference(
            title: context.tr('portMapping.enableUpnp'),
            summary: context.tr('portMapping.enableUpnpSubtitle'),
            value: _upnpEnabled,
            onChanged: _setUpnp,
          ),
          if (_upnpEnabled) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _field(
                      _upnpExternalPort,
                      context.tr('portMapping.upnpExternalPort'),
                      hint: context.tr('portMapping.upnpExternalPortHint'),
                      number: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _upnpProtocolDropdown()),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: MiuixButton(
                  onPressed: () async {
                    await _saveUpnpSettings();
                    if (!mounted) return;
                    final server = ServerScope.of(context);
                    if (server.isRunning) {
                      server.disableUpnpNow();
                      server.enableUpnpNow();
                    }
                    if (!mounted) return;
                    showMiuixSnackbar(context.tr('portMapping.saved'));
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MiuixIcon(icon: Icons.save, size: 18),
                      const SizedBox(width: 8),
                      MiuixText(context.tr('portMapping.saveConfig')),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // —— DDNS 卡片 ——

  Widget _buildDdnsCard(MiuixThemeData theme) {
    final provider = _ddnsConfig.provider;
    return MiuixCard(
      insideMargin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.dns_outlined, size: 20, color: theme.colors.primary),
                const SizedBox(width: 8),
                Text(
                  context.tr('portMapping.ddnsCardTitle'),
                  style: theme.textStyles.subtitle.copyWith(
                    color: theme.colors.primary,
                  ),
                ),
              ],
            ),
          ),
          MiuixSwitchPreference(
            title: context.tr('portMapping.enableDdns'),
            summary: context.tr('portMapping.enableDdnsSubtitle'),
            value: _ddnsConfig.enabled,
            onChanged: _setDdns,
          ),
          if (_ddnsConfig.enabled) ...[
            // 服务商选择。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _ddnsProviderDropdown(),
            ),
            // 域名与主机记录。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: provider == DdnsProvider.duckdns
                  ? _field(
                      _ddnsDomain,
                      context.tr('portMapping.ddnsDuckdnsDomain'),
                      hint: 'mysub',
                    )
                  : Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _field(
                            _ddnsHost,
                            context.tr('portMapping.ddnsHost'),
                            hint: 'mc',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: _field(
                            _ddnsDomain,
                            context.tr('portMapping.ddnsDomain'),
                            hint: 'example.com',
                          ),
                        ),
                      ],
                    ),
            ),
            // 凭据字段（依服务商变化）。
            if (provider == DdnsProvider.dnspod ||
                provider == DdnsProvider.aliyun)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _field(
                  _ddnsTokenId,
                  provider == DdnsProvider.dnspod
                      ? context.tr('portMapping.ddnsTokenId')
                      : context.tr('portMapping.ddnsAccessKeyId'),
                ),
              ),
            if (provider != DdnsProvider.custom)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _field(_ddnsToken, switch (provider) {
                  DdnsProvider.cloudflare => context.tr(
                    'portMapping.ddnsApiToken',
                  ),
                  DdnsProvider.duckdns => context.tr('portMapping.ddnsToken'),
                  DdnsProvider.dnspod => context.tr('portMapping.ddnsToken'),
                  _ => context.tr('portMapping.ddnsAccessKeySecret'),
                }, obscure: true),
              ),
            if (provider == DdnsProvider.custom)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _field(
                  _ddnsCustomUrl,
                  context.tr('portMapping.ddnsCustomUrl'),
                  hint: 'https://…?domain={domain}&ip={ipv4}',
                ),
              ),
            // 记录类型与检查间隔。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: MiuixCheckboxPreference(
                      title: 'IPv4 (A)',
                      value: _ddnsConfig.ipv4Enabled,
                      onChanged: (v) => setState(() {
                        _ddnsConfig = _ddnsConfig.copyWith(ipv4Enabled: v);
                      }),
                      insideMargin: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                  Expanded(
                    child: MiuixCheckboxPreference(
                      title: 'IPv6 (AAAA)',
                      value: _ddnsConfig.ipv6Enabled,
                      onChanged: (v) => setState(() {
                        _ddnsConfig = _ddnsConfig.copyWith(ipv6Enabled: v);
                      }),
                      insideMargin: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _field(
                _ddnsInterval,
                context.tr('portMapping.ddnsInterval'),
                hint: '10',
                number: true,
              ),
            ),
            // 停服时清理远端解析（自定义 URL 无删除接口，不提供该选项）。
            if (provider != DdnsProvider.custom)
              MiuixSwitchPreference(
                title: context.tr('portMapping.ddnsDeleteOnStop'),
                summary: context.tr('portMapping.ddnsDeleteOnStopSubtitle'),
                value: _ddnsConfig.deleteOnStop,
                onChanged: (v) => setState(() {
                  _ddnsConfig = _ddnsConfig.copyWith(deleteOnStop: v);
                }),
              ),
            // 保存 + 立即更新。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: MiuixButton(
                      onPressed: _saveDdnsSettings,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MiuixIcon(icon: Icons.save, size: 18),
                          const SizedBox(width: 8),
                          MiuixText(context.tr('portMapping.saveDdnsConfig')),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _ddnsUpdating ? null : _updateDdnsNow,
                      icon: _ddnsUpdating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: MiuixInfiniteProgressIndicator(size: 20),
                            )
                          : const Icon(Icons.sync, size: 18),
                      label: Text(context.tr('portMapping.ddnsUpdateNow')),
                    ),
                  ),
                ],
              ),
            ),
            // 与 UPnP 配合的说明。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Padding(
                padding: EdgeInsets.zero,
                child: MiuixCard(
                  insideMargin: const EdgeInsets.all(12),
                  colors: MiuixCardColors(
                    color: theme.colors.surfaceContainerHighest,
                    contentColor: MiuixTheme.of(context).colors.onSurface,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: theme.colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.tr('portMapping.ddnsUpnpHint'),
                          style: theme.textStyles.footnote1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ddnsProviderDropdown() {
    // 值与展示文案分离，按下标回写枚举值。
    const providers = [
      DdnsProvider.cloudflare,
      DdnsProvider.duckdns,
      DdnsProvider.dnspod,
      DdnsProvider.aliyun,
      DdnsProvider.custom,
    ];
    final labels = [
      'Cloudflare',
      'DuckDNS',
      context.tr('portMapping.ddnsProviderDnspod'),
      context.tr('portMapping.ddnsProviderAliyun'),
      context.tr('portMapping.ddnsProviderCustom'),
    ];
    return EcDropdownField(
      label: context.tr('portMapping.ddnsProvider'),
      items: labels,
      selectedIndex: providers.indexOf(_ddnsConfig.provider),
      onSelected: (i) => setState(() {
        _ddnsConfig = _ddnsConfig.copyWith(provider: providers[i]);
      }),
    );
  }

  // —— FRP 卡片 ——

  Widget _buildFrpcCard(MiuixThemeData theme) {
    final statusText = _tunnelExitCode != null
        ? (_tunnelExitCode == 0
              ? context.tr('portMapping.tunnelExited')
              : context.tr('portMapping.tunnelExitedWithError', {
                  'code': _tunnelExitCode.toString(),
                }))
        : switch (_tunnelStatus) {
            'running' => context.tr('portMapping.tunnelRunning'),
            'starting' => context.tr('portMapping.tunnelConnecting'),
            'preparing' => context.tr('portMapping.tunnelPreparing'),
            _ => null,
          };
    return MiuixCard(
      insideMargin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_outlined,
                  size: 20,
                  color: theme.colors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('portMapping.frpCardTitle'),
                    style: theme.textStyles.subtitle.copyWith(
                      color: theme.colors.primary,
                    ),
                  ),
                ),
                if (statusText != null) _statusChip(theme, statusText),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: _buildFrpcRuntimeSelector(theme),
          ),
          MiuixSwitchPreference(
            title: context.tr('portMapping.enableFrp'),
            summary: context.tr('portMapping.enableFrpSubtitle'),
            value: _tunnelEnabled,
            enabled: _frpcRuntimes.isNotEmpty,
            onChanged: _setTunnel,
          ),
          if (_tunnelEnabled) ...[
            const Divider(indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: _buildDefaultTunnelSelector(theme),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Padding(
                padding: EdgeInsets.zero,
                child: MiuixCard(
                  insideMargin: const EdgeInsets.all(12),
                  colors: MiuixCardColors(
                    color: theme.colors.surfaceContainerHighest,
                    contentColor: MiuixTheme.of(context).colors.onSurface,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: theme.colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.tr('portMapping.defaultTunnelInfo'),
                          style: theme.textStyles.footnote1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: MiuixButton(
                  onPressed: _openTunnelManager,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MiuixIcon(icon: Icons.cable, size: 18),
                      const SizedBox(width: 8),
                      MiuixText(context.tr('portMapping.manageTunnels')),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFrpcRuntimeSelector(MiuixThemeData theme) {
    if (_frpcRuntimes.isEmpty) {
      return Padding(
        padding: EdgeInsets.zero,
        child: MiuixCard(
          insideMargin: const EdgeInsets.all(12),
          colors: MiuixCardColors(
            color: theme.colors.errorContainer,
            contentColor: MiuixTheme.of(context).colors.onSurface,
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_outlined,
                size: 18,
                color: theme.colors.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('portMapping.frpcRequiredContent'),
                  style: theme.textStyles.footnote1.copyWith(
                    color: theme.colors.onErrorContainer,
                  ),
                ),
              ),
              MiuixTextButton(
                context.tr('server.runtimeRequiredAction'),
                onPressed: _showFrpcRequiredDialog,
              ),
            ],
          ),
        ),
      );
    }

    final runtimeNames = <String, String>{
      for (final r in _frpcRuntimes) r.id: '${r.name} (${r.displayVersion})',
    };

    return EcDropdownField(
      label: context.tr('portMapping.frpcRuntimeLabel'),
      items: [for (final r in _frpcRuntimes) runtimeNames[r.id] ?? r.id],
      selectedIndex: _frpcRuntimes.indexWhere(
        (r) => r.id == _selectedFrpcRuntimeId,
      ),
      onSelected: (i) {
        final id = _frpcRuntimes[i].id;
        setState(() => _selectedFrpcRuntimeId = id);
        NetworkStore.saveFrpcRuntimeId(id);
      },
    );
  }

  /// 默认映射隧道下拉框：选中的隧道随服务端自动启停。
  Widget _buildDefaultTunnelSelector(MiuixThemeData theme) {
    // 开关打开后隧道被全部删掉的场景：提示去「映射隧道」页创建。
    if (_savedTunnels.isEmpty) {
      return Padding(
        padding: EdgeInsets.zero,
        child: MiuixCard(
          insideMargin: const EdgeInsets.all(12),
          colors: MiuixCardColors(
            color: theme.colors.errorContainer,
            contentColor: MiuixTheme.of(context).colors.onSurface,
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_outlined,
                size: 18,
                color: theme.colors.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('portMapping.noTunnelMessage'),
                  style: theme.textStyles.footnote1.copyWith(
                    color: theme.colors.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    String tunnelLabel(SavedFrpTunnel t) {
      final providerName = t.provider == FrpProvider.custom
          ? context.tr('frp.provider.custom')
          : t.provider.displayName;
      return '${t.name} · $providerName';
    }

    return EcDropdownField(
      label: context.tr('portMapping.defaultTunnelLabel'),
      items: [for (final t in _savedTunnels) tunnelLabel(t)],
      selectedIndex: _savedTunnels.indexWhere(
        (t) => t.localId == _defaultTunnelId,
      ),
      onSelected: (i) => _setDefaultTunnel(_savedTunnels[i].localId),
    );
  }

  Widget _statusChip(MiuixThemeData theme, String text) {
    final Color color;
    if (_tunnelExitCode != null) {
      // 已退出：退出码 0 灰色，非 0 红色。
      color = _tunnelExitCode == 0 ? theme.colors.outline : theme.colors.error;
    } else if (_tunnelStatus == 'running') {
      color = theme.colors.primary;
    } else {
      // 连接中 / 准备中。
      color = theme.colors.onTertiaryContainer;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: theme.textStyles.footnote2.copyWith(color: color),
      ),
    );
  }

  // —— 工具 ——

  Widget _buildLogSection(MiuixThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text(
                context.tr('portMapping.tunnelLog'),
                style: theme.textStyles.subtitle.copyWith(
                  color: theme.colors.primary,
                ),
              ),
              const Spacer(),
              MiuixIconButton(
                onPressed: () {
                  _tunnel.clearLog();
                  setState(() => _logs.clear());
                },
                child: MiuixIcon(
                  icon: Icons.cleaning_services_outlined,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 220,
          decoration: BoxDecoration(
            color: theme.colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(8),
          child: _logs.isEmpty
              ? Center(
                  child: Text(
                    context.tr('portMapping.noLogs'),
                    style: theme.textStyles.footnote1.copyWith(
                      color: theme.colors.onSurfaceVariantSummary,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _logScroll,
                  itemCount: _logs.length,
                  itemBuilder: (_, i) => Text(
                    _logs[i],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    bool number = false,
    bool obscure = false,
  }) {
    return EcTextField(
      controller: c,
      label: label,
      hint: hint,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      obscureText: obscure,
    );
  }

  Widget _upnpProtocolDropdown() {
    return EcDropdownField(
      label: context.tr('portMapping.protocol'),
      items: const ['TCP', 'UDP'],
      selectedIndex: _upnpProtocol == 'udp' ? 1 : 0,
      onSelected: (i) => setState(() => _upnpProtocol = i == 1 ? 'udp' : 'tcp'),
    );
  }
}

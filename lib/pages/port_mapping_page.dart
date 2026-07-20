import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/ddns_store.dart';
import '../config/network_store.dart';
import '../files/text_editor_page.dart';
import '../i18n/locale_scope.dart';
import '../widgets/error_dialog.dart';
import '../server/runtime_service.dart';
import '../server/server_scope.dart';
import '../tunnel/tunnel_service.dart';
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

  // —— 隧道运行状态 ——
  // _tunnelStatus: 非 null 表示 frpc 正在运行/连接中（preparing/starting/running）。
  // _tunnelExitCode: 非 null 表示 frpc 已退出（保留日志框以便排查异常退出原因）。
  // 两者同时为 null 表示从未启动或已清空状态。
  String? _tunnelStatus;
  int? _tunnelExitCode;
  final List<String> _logs = [];
  final _logScroll = ScrollController();
  StreamSubscription<TunnelEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _subscribe();
    RuntimeService.refreshSignal.addListener(_onRuntimesChanged);
  }

  @override
  void dispose() {
    RuntimeService.refreshSignal.removeListener(_onRuntimesChanged);
    _sub?.cancel();
    _logScroll.dispose();
    _upnpExternalPort.dispose();
    _ddnsDomain.dispose();
    _ddnsHost.dispose();
    _ddnsTokenId.dispose();
    _ddnsToken.dispose();
    _ddnsCustomUrl.dispose();
    _ddnsInterval.dispose();
    super.dispose();
  }

  // —— 加载 ——

  Future<void> _loadAll() async {
    final upnp = await NetworkStore.loadUpnpEnabled();
    final extPort = await NetworkStore.loadUpnpExternalPort();
    final protocol = await NetworkStore.loadUpnpProtocol();
    final tunnel = await NetworkStore.loadTunnelEnabled();
    final runtimeId = await NetworkStore.loadFrpcRuntimeId();
    final runtimes = await const RuntimeService().installedFrpcRuntimes();
    final ddns = await DdnsStore.load();
    if (!mounted) return;
    setState(() {
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('portMapping.saved')),
        duration: const Duration(seconds: 2),
      ),
    );
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
    final messenger = ScaffoldMessenger.of(context);
    final trans = LocaleScope.of(context).translations;
    try {
      final result = await ServerScope.of(context).updateDdnsOnce();
      if (!mounted) return;
      if (result.success) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              trans.get('portMapping.ddnsUpdateSuccess', {
                'ip': [
                  result.ipv4,
                  result.ipv6,
                ].whereType<String>().join(' / '),
              }),
            ),
            duration: const Duration(seconds: 3),
          ),
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

  Future<void> _setTunnel(bool value) async {
    if (value && _frpcRuntimes.isEmpty) {
      _showFrpcRequiredDialog();
      return;
    }
    // 配置仍为默认模板时拒绝启用：占位地址连不上任何真实 frps 服务器。
    if (value && await _isTemplateConfig()) {
      if (mounted) _showTemplateConfigDialog();
      return;
    }
    await NetworkStore.saveTunnelEnabled(value);
    if (!mounted) return;
    setState(() => _tunnelEnabled = value);
    final server = ServerScope.of(context);
    if (value) {
      server.enableTunnelNow(null, _selectedFrpcRuntimeId);
    } else {
      server.disableTunnelNow();
    }
  }

  /// 当前 frpc.toml 是否仍为未修改的默认模板（文件不存在视为模板）。
  Future<bool> _isTemplateConfig() async {
    try {
      final file = await NetworkStore.ensureCustomFrpcFile();
      return NetworkStore.isTemplateFrpcConfig(await file.readAsString());
    } catch (_) {
      return false;
    }
  }

  /// frpc.toml 仍为默认模板，提示用户先修改配置再启用隧道。
  Future<void> _showTemplateConfigDialog() async {
    final tr = LocaleScope.of(context).translations;
    final edit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.get('portMapping.templateConfigTitle')),
        content: Text(tr.get('portMapping.templateConfigMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr.get('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr.get('portMapping.editConfigFile')),
          ),
        ],
      ),
    );
    if (edit == true && mounted) {
      await _editFrpcConfigFile();
      // 编辑返回后配置已修改的话，继续完成用户原本的「启用」操作。
      if (mounted && !await _isTemplateConfig()) {
        await _setTunnel(true);
      }
    }
  }

  /// 未安装 frpc 运行时，提示用户前往「运行环境」页导入。
  Future<void> _showFrpcRequiredDialog() async {
    final tr = LocaleScope.of(context).translations;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.get('server.runtimeRequiredTitle')),
        content: Text(tr.get('portMapping.frpcRequiredContent')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr.get('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr.get('server.runtimeRequiredAction')),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const RuntimePage()));
      if (mounted) _loadAll();
    }
  }

  // —— 编辑配置文件 ——

  /// 打开内置文本编辑器直接编辑 `config/frpc.toml`。返回后若隧道运行中则重启。
  Future<void> _editFrpcConfigFile() async {
    final file = await NetworkStore.ensureCustomFrpcFile();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TextEditorPage(path: file.path, name: 'frpc.toml'),
      ),
    );
    if (!mounted) return;
    // 编辑返回后，若隧道运行中，重启以应用最新内容；若启用了隧道但此前
    // 未能启动（如模板配置被拒绝、frpc 异常退出），则重新拉起。
    final server = ServerScope.of(context);
    if (_tunnelEnabled && server.isRunning) {
      if (server.isTunnelActive) {
        await server.restartTunnel();
      } else if (!await _isTemplateConfig()) {
        server.enableTunnelNow(null, _selectedFrpcRuntimeId);
      }
    }
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('portMapping.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildFrpcCard(theme),
            if (_tunnelEnabled) ...[
              const SizedBox(height: 16),
              _buildLogSection(theme),
            ],
            const SizedBox(height: 16),
            _buildUpnpCard(theme),
            const SizedBox(height: 16),
            _buildDdnsCard(theme),
          ],
        ),
      ),
    );
  }

  // —— UPnP 卡片 ——

  Widget _buildUpnpCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
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
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.tr('portMapping.upnpCardTitle'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            SwitchListTile(
              title: Text(context.tr('portMapping.enableUpnp')),
              subtitle: Text(context.tr('portMapping.enableUpnpSubtitle')),
              value: _upnpEnabled,
              onChanged: _setUpnp,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
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
                  child: FilledButton.tonalIcon(
                    onPressed: () async {
                      await _saveUpnpSettings();
                      if (!mounted) return;
                      final server = ServerScope.of(context);
                      if (server.isRunning) {
                        server.disableUpnpNow();
                        server.enableUpnpNow();
                      }
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.tr('portMapping.saved')),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.save, size: 18),
                    label: Text(context.tr('portMapping.saveConfig')),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // —— DDNS 卡片 ——

  Widget _buildDdnsCard(ThemeData theme) {
    final provider = _ddnsConfig.provider;
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.dns_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.tr('portMapping.ddnsCardTitle'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            SwitchListTile(
              title: Text(context.tr('portMapping.enableDdns')),
              subtitle: Text(context.tr('portMapping.enableDdnsSubtitle')),
              value: _ddnsConfig.enabled,
              onChanged: _setDdns,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
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
                  child: _field(
                    _ddnsToken,
                    switch (provider) {
                      DdnsProvider.cloudflare =>
                        context.tr('portMapping.ddnsApiToken'),
                      DdnsProvider.duckdns =>
                        context.tr('portMapping.ddnsToken'),
                      DdnsProvider.dnspod =>
                        context.tr('portMapping.ddnsToken'),
                      _ => context.tr('portMapping.ddnsAccessKeySecret'),
                    },
                    obscure: true,
                  ),
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
                      child: CheckboxListTile(
                        title: const Text('IPv4 (A)'),
                        value: _ddnsConfig.ipv4Enabled,
                        onChanged: (v) => setState(() {
                          _ddnsConfig =
                              _ddnsConfig.copyWith(ipv4Enabled: v ?? true);
                        }),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('IPv6 (AAAA)'),
                        value: _ddnsConfig.ipv6Enabled,
                        onChanged: (v) => setState(() {
                          _ddnsConfig =
                              _ddnsConfig.copyWith(ipv6Enabled: v ?? false);
                        }),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
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
                SwitchListTile(
                  title: Text(context.tr('portMapping.ddnsDeleteOnStop')),
                  subtitle:
                      Text(context.tr('portMapping.ddnsDeleteOnStopSubtitle')),
                  value: _ddnsConfig.deleteOnStop,
                  onChanged: (v) => setState(() {
                    _ddnsConfig = _ddnsConfig.copyWith(deleteOnStop: v);
                  }),
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              // 保存 + 立即更新。
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _saveDdnsSettings,
                        icon: const Icon(Icons.save, size: 18),
                        label: Text(context.tr('portMapping.saveDdnsConfig')),
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
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
                child: Card(
                  color: theme.colorScheme.surfaceContainerHighest,
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.tr('portMapping.ddnsUpnpHint'),
                            style: theme.textTheme.bodySmall,
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
      ),
    );
  }

  Widget _ddnsProviderDropdown() {
    return DropdownButtonFormField<DdnsProvider>(
      initialValue: _ddnsConfig.provider,
      decoration: InputDecoration(
        labelText: context.tr('portMapping.ddnsProvider'),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem(
          value: DdnsProvider.cloudflare,
          child: Text('Cloudflare'),
        ),
        const DropdownMenuItem(
          value: DdnsProvider.duckdns,
          child: Text('DuckDNS'),
        ),
        DropdownMenuItem(
          value: DdnsProvider.dnspod,
          child: Text(context.tr('portMapping.ddnsProviderDnspod')),
        ),
        DropdownMenuItem(
          value: DdnsProvider.aliyun,
          child: Text(context.tr('portMapping.ddnsProviderAliyun')),
        ),
        DropdownMenuItem(
          value: DdnsProvider.custom,
          child: Text(context.tr('portMapping.ddnsProviderCustom')),
        ),
      ],
      onChanged: (v) => setState(() {
        _ddnsConfig = _ddnsConfig.copyWith(provider: v ?? DdnsProvider.cloudflare);
      }),
    );
  }

  // —— FRP 卡片 ——

  Widget _buildFrpcCard(ThemeData theme) {
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
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
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('portMapping.frpCardTitle'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
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
            SwitchListTile(
              title: Text(context.tr('portMapping.enableFrp')),
              subtitle: Text(context.tr('portMapping.enableFrpSubtitle')),
              value: _tunnelEnabled,
              onChanged: _frpcRuntimes.isEmpty ? null : _setTunnel,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            if (_tunnelEnabled) ...[
              const Divider(indent: 16, endIndent: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Card(
                  color: theme.colorScheme.surfaceContainerHighest,
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.tr('portMapping.customConfigInfo'),
                            style: theme.textTheme.bodySmall,
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
                  child: FilledButton.tonalIcon(
                    onPressed: _editFrpcConfigFile,
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: Text(context.tr('portMapping.editConfigFile')),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFrpcRuntimeSelector(ThemeData theme) {
    if (_frpcRuntimes.isEmpty) {
      return Card(
        color: theme.colorScheme.errorContainer,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_outlined,
                size: 18,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('portMapping.frpcRequiredContent'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
              TextButton(
                onPressed: _showFrpcRequiredDialog,
                child: Text(context.tr('server.runtimeRequiredAction')),
              ),
            ],
          ),
        ),
      );
    }

    final runtimeNames = <String, String>{
      for (final r in _frpcRuntimes) r.id: '${r.name} (${r.displayVersion})',
    };

    return DropdownButtonFormField<String>(
      key: ValueKey(_selectedFrpcRuntimeId),
      isExpanded: true,
      initialValue: _selectedFrpcRuntimeId,
      decoration: InputDecoration(
        labelText: context.tr('portMapping.frpcRuntimeLabel'),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      items: _frpcRuntimes.map((r) {
        return DropdownMenuItem(
          value: r.id,
          child: Text(runtimeNames[r.id] ?? r.id),
        );
      }).toList(),
      selectedItemBuilder: (context) => _frpcRuntimes.map((r) {
        return DropdownMenuItem<String>(
          value: r.id,
          child: Text(
            runtimeNames[r.id] ?? r.id,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: (v) {
        if (v != null) {
          setState(() => _selectedFrpcRuntimeId = v);
          NetworkStore.saveFrpcRuntimeId(v);
        }
      },
    );
  }

  Widget _statusChip(ThemeData theme, String text) {
    final Color color;
    if (_tunnelExitCode != null) {
      // 已退出：退出码 0 灰色，非 0 红色。
      color = _tunnelExitCode == 0
          ? theme.colorScheme.outline
          : theme.colorScheme.error;
    } else if (_tunnelStatus == 'running') {
      color = theme.colorScheme.primary;
    } else {
      // 连接中 / 准备中。
      color = theme.colorScheme.tertiary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }

  // —— 工具 ——

  Widget _buildLogSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text(
                context.tr('portMapping.tunnelLog'),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                tooltip: context.tr('portMapping.clearLog'),
                onPressed: () {
                  _tunnel.clearLog();
                  setState(() => _logs.clear());
                },
              ),
            ],
          ),
        ),
        Container(
          height: 220,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(8),
          child: _logs.isEmpty
              ? Center(
                  child: Text(
                    context.tr('portMapping.noLogs'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
    return TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _upnpProtocolDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _upnpProtocol,
      decoration: InputDecoration(
        labelText: context.tr('portMapping.protocol'),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'tcp', child: Text('TCP')),
        DropdownMenuItem(value: 'udp', child: Text('UDP')),
      ],
      onChanged: (v) => setState(() => _upnpProtocol = v ?? 'tcp'),
    );
  }

}

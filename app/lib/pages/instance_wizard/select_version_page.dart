import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../server/server_service.dart';
import '../api_error.dart';
import 'download_flow_state.dart';

/// 下载流程版本页。
/// - hasLoader 类型(如 fabric):拉 Minecraft 版本列表 → 记录 mcVersion →
///   加载器版本页
/// - 简单类型:拉服务端版本列表 → 选版本 → 确认对话框 → 组装下载信息并
///   创建实例 → 下载进度页
/// bungeecord 无版本概念,不进本页(在服务端类型页直接开始下载)。
class SelectVersionPage extends ConsumerStatefulWidget {
  const SelectVersionPage({super.key});

  @override
  ConsumerState<SelectVersionPage> createState() => _SelectVersionPageState();
}

class _SelectVersionPageState extends ConsumerState<SelectVersionPage> {
  List<ServerVersion> _versions = [];
  bool _loading = true;
  String? _error;
  bool _submitting = false;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  DownloadFlowState? get _flow => ref.read(downloadFlowProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final flow = _flow;
    if (flow == null || flow.serverType == null) {
      // 不在向导流程中(异常直达):退回向导根页
      if (mounted) context.go('/servers/instances/create');
      return;
    }
    final client = _client;
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _versions = [];
    });
    try {
      final list = (await client
              .getCatalogApi()
              .listCatalogVersions(type: flow.serverType!))
          .data!;
      if (!mounted) return;
      setState(() {
        _versions = list.toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _onSelect(ServerVersion version) {
    final flow = _flow;
    if (flow == null) return;
    if (flow.hasLoader) {
      // 记录 MC 版本 → 下一步选加载器版本
      flow.mcVersion = version.version;
      context.push('/servers/instances/create/download/loader');
      return;
    }
    _confirmSimple(flow, version);
  }

  Future<void> _confirmSimple(DownloadFlowState flow, ServerVersion version) async {
    final meta = version.meta;
    final mcpe = _jsonString(meta?['mcpeVersion']);
    final serverName = serverTypeMeta(flow.serverType!)?.title ??
        flow.serverType!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认下载'),
        content: Text(
          mcpe != null
              ? '将下载 $serverName $version(对应客户端 $mcpe)'
              : '将下载 $serverName $version',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    flow.version = version.version;
    await _startDownload(flow);
  }

  /// 组装下载信息并创建实例(202),随后进入下载进度页。
  Future<void> _startDownload(DownloadFlowState flow) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await startInstanceDownload(ref, flow);
      if (!mounted) return;
      context.push('/servers/instances/create/download/progress');
    } catch (e) {
      if (!mounted) return;
      _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// meta 值是 JsonObject(字符串时带引号),统一剥离外层引号取原串。
  static String? _jsonString(Object? value) {
    if (value == null) return null;
    final s = value.toString();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final versions = _versions;
    final flow = _flow;
    final hasLoader = flow?.hasLoader ?? false;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(hasLoader ? '选择 Minecraft 版本' : '选择版本'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: _loading && versions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              : versions.isEmpty
                  ? _emptyView()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: versions.length,
                      itemBuilder: (context, index) {
                        final v = versions[index];
                        final mcpe = _jsonString(v.meta?['mcpeVersion']);
                        return ListTile(
                          title: Text(v.version),
                          subtitle: mcpe != null ? Text('对应客户端 $mcpe') : null,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _submitting ? null : () => _onSelect(v),
                        );
                      },
                    ),
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
        Center(child: TextButton(onPressed: _load, child: const Text('重试'))),
      ],
    );
  }

  Widget _emptyView() {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.inbox_outlined, size: 56, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Center(
          child: Text(
            '暂无可用版本',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
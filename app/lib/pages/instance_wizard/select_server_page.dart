import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../server/server_service.dart';
import '../api_error.dart';
import 'download_flow_state.dart';
import 'wizard_tile.dart';

/// 下载流程服务端类型页:展示 /catalog/server-types 中指定分类的类型列表。
/// [category] 由上一页经 URL 查询参数传入(vanilla / plugin / mod / proxy / bedrock)。
/// - bungeecord 无版本概念 → 直接组装下载信息并创建实例
/// - 其余类型 → 版本页(hasLoader 类型为 Minecraft 版本页)
class SelectServerPage extends ConsumerStatefulWidget {
  const SelectServerPage({super.key, required this.category});

  final String category;

  @override
  ConsumerState<SelectServerPage> createState() => _SelectServerPageState();
}

class _SelectServerPageState extends ConsumerState<SelectServerPage> {
  List<ServerTypeInfo>? _types;
  bool _loading = true;
  String? _error;
  bool _submitting = false;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = (await client.getCatalogApi().listServerTypes()).data!;
      final filtered = list
          .where((t) => t.category.name == widget.category)
          .toList();
      if (!mounted) return;
      setState(() {
        _types = filtered;
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

  void _select(BuildContext context, ServerTypeInfo info) {
    final flow = ref.read(downloadFlowProvider);
    if (flow == null) return;
    flow
      ..serverType = info.type
      ..category = widget.category
      ..hasLoader = info.hasLoader ?? false
      ..version = null
      ..mcVersion = null
      ..loaderVersion = null;
    if (info.type == 'bungeecord') {
      // 无版本概念:直接组装下载信息并创建实例
      _startBungee(flow);
      return;
    }
    context.push('/servers/instances/create/download/version');
  }

  Future<void> _startBungee(DownloadFlowState flow) async {
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

  @override
  Widget build(BuildContext context) {
    final types = _types;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('选择服务端类型'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: _loading && types == null
          ? const Center(child: CircularProgressIndicator())
          : types == null
              ? _errorView()
              : types.isEmpty
                  ? _emptyView()
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final t in types) ...[
                          WizardTile(
                            icon: serverTypeMeta(t.type)?.icon ??
                                Icons.dns_outlined,
                            title:
                                serverTypeMeta(t.type)?.title ?? t.type,
                            subtitle:
                                serverTypeMeta(t.type)?.subtitle ?? '未知类型',
                            onTap: () => _select(context, t),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
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
            '该分类下暂无可选服务端',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
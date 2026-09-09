import 'dart:async';

import 'package:edgecube_api_client/edgecube_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../server/server_service.dart';
import 'api_error.dart';
import 'labels.dart';

/// 运行时页:列出 daemon 已安装的 Java/PHP/FRPC 运行时,可卸载、可在线安装。
class RuntimePage extends ConsumerStatefulWidget {
  const RuntimePage({super.key});

  @override
  ConsumerState<RuntimePage> createState() => _RuntimePageState();
}

class _RuntimePageState extends ConsumerState<RuntimePage> {
  List<RuntimeInfo>? _runtimes;
  bool _loading = true;
  String? _error;
  String? _deletingId;

  EdgecubeApiClient? get _client => ref.read(edgecubeClientProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    setState(() => _loading = true);
    try {
      final list = (await client.getRuntimesApi().listRuntimes()).data!;
      if (!mounted) return;
      setState(() {
        _runtimes = list.toList();
        _error = null;
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

  Future<void> _delete(RuntimeInfo runtime) async {
    if (_deletingId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('卸载运行时'),
        content: Text(
          '确定卸载 ${runtimeTypeLabel(runtime.type)} ${runtime.version} 吗?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingId = runtime.id);
    try {
      await _client!.getRuntimesApi().deleteRuntime(runtimeId: runtime.id);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtimes = _runtimes;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('运行时'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/manage/runtimes/install');
          // 安装页返回后刷新已安装列表
          _load();
        },
        icon: const Icon(Icons.download_outlined),
        label: const Text('安装'),
      ),
      body: _loading && runtimes == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: runtimes == null
                  ? _errorView()
                  : _list(runtimes),
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

  Widget _list(List<RuntimeInfo> runtimes) {
    final cs = Theme.of(context).colorScheme;
    if (runtimes.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.memory, size: 56, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '尚未安装任何运行时',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              '点击右下角「安装」从官方源下载 Java/PHP/FRPC 运行时',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        for (final runtime in runtimes) ...[
          _RuntimeCard(
            runtime: runtime,
            deleting: _deletingId == runtime.id,
            onDelete: () => _delete(runtime),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _RuntimeCard extends StatelessWidget {
  const _RuntimeCard({
    required this.runtime,
    required this.deleting,
    required this.onDelete,
  });

  final RuntimeInfo runtime;
  final bool deleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = StringBuffer()
      ..write(runtimeTypeLabel(runtime.type))
      ..write(' ${runtime.version}');
    if (runtime.arch != null) subtitle.write(' · ${runtime.arch}');
    if (runtime.sizeBytes != null) {
      subtitle.write(' · ${_fmtBytes(runtime.sizeBytes)}');
    }
    if (runtime.default_ ?? false) subtitle.write(' · 默认');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.secondaryContainer.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Icon(
                switch (runtime.type) {
                  RuntimeType.java => Icons.coffee_outlined,
                  RuntimeType.php => Icons.integration_instructions_outlined,
                  RuntimeType.frpc => Icons.hub_outlined,
                  _ => Icons.memory_outlined,
                },
                size: 24,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${runtimeTypeLabel(runtime.type)} ${runtime.version}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle.toString(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            if (deleting)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                color: cs.onSurfaceVariant,
                tooltip: '卸载',
              ),
          ],
        ),
      ),
    );
  }

  static String _fmtBytes(int? v) {
    if (v == null) return '未知';
    if (v >= 1 << 30) return '${(v / (1 << 30)).toStringAsFixed(2)}GB';
    if (v >= 1 << 20) return '${(v / (1 << 20)).toStringAsFixed(1)}MB';
    if (v >= 1 << 10) return '${(v / (1 << 10)).toStringAsFixed(1)}KB';
    return '${v}B';
  }
}
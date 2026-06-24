import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../i18n/locale_scope.dart';
import '../server/runtime_service.dart';

/// 「运行环境」管理页：列出已安装运行时，导入/删除 .ecpkg。
class RuntimePage extends StatefulWidget {
  const RuntimePage({super.key});

  @override
  State<RuntimePage> createState() => _RuntimePageState();
}

class _RuntimePageState extends State<RuntimePage> {
  final _service = const RuntimeService();
  List<RuntimeInfo> _runtimes = [];
  bool _loading = true;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _service.installedRuntimes();
      if (!mounted) return;
      setState(() => _runtimes = list);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _import() async {
    if (!await StoragePermission.isGranted()) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('fileBrowser.permissionTitle')),
          content: Text(ctx.tr('fileBrowser.permissionContent')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ctx.tr('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(ctx.tr('fileBrowser.grantPermission')),
            ),
          ],
        ),
      );
      if (go != true) return;
      await StoragePermission.request();
      if (!mounted) return;
      return _import();
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final tr = LocaleScope.of(context).translations;
    final path = await pickFromSystem(context, mode: SystemPickMode.file);
    if (path == null || !path.toLowerCase().endsWith('.ecpkg')) {
      if (mounted && path != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(tr.get('runtime.notEcpkg'))),
        );
      }
      return;
    }

    await _doImport(path);
  }

  Future<void> _doImport(String path, {bool force = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    final tr = LocaleScope.of(context).translations;
    setState(() => _importing = true);
    try {
      await _service.importPackage(path, force: force);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(tr.get('runtime.importSuccess'))),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (e.code == 'IMPORT_FAILED' &&
          e.message?.contains('RUNTIME_EXISTS') == true &&
          !force) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr.get('runtime.importConfirmTitle')),
            content: Text(tr.get('runtime.importConfirmContent')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(tr.get('common.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(tr.get('common.replace')),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await _doImport(path, force: true);
        }
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(tr.get('runtime.importFailed', {'error': '${e.message}'})),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(tr.get('runtime.importFailed', {'error': '$e'}))),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _delete(RuntimeInfo info) async {
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final tr = LocaleScope.of(context).translations;
    final runtimeRunning = await _service.isRuntimeRunning(info.id);
    if (runtimeRunning) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(tr.get('runtime.cannotDeleteRunning'))),
      );
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.get('runtime.deleteConfirmTitle')),
        content: Text(
          tr.get('runtime.deleteConfirmContent', {'name': info.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr.get('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr.get('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.deleteRuntime(info.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(tr.get('runtime.deleteFailed', {'error': '$e'}))),
      );
    }
  }

  String _typeLabel(String type) {
    return switch (type) {
      'jre' => 'Java',
      'php' => 'PHP',
      'frpc' => 'FRP',
      _ => type,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('runtime.title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _runtimes.isEmpty
              ? _EmptyBody(onImport: _import)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _runtimes.length,
                  itemBuilder: (_, i) {
                    final rt = _runtimes[i];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          switch (rt.type) {
                            'jre' => Icons.coffee,
                            'php' => Icons.code,
                            'frpc' => Icons.network_check,
                            _ => Icons.memory,
                          },
                          size: 32,
                        ),
                        title: Text(rt.name),
                        subtitle: Text(
                          '${_typeLabel(rt.type)} · ${rt.version}',
                          style: theme.textTheme.bodySmall,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(rt),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: _importing
          ? const FloatingActionButton(
              onPressed: null,
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          : FloatingActionButton.extended(
              onPressed: _import,
              icon: const Icon(Icons.add),
              label: Text(context.tr('runtime.import')),
            ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.onImport});
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.memory, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              context.tr('runtime.emptyTitle'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('runtime.emptyDescription'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add),
              label: Text(context.tr('runtime.import')),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../i18n/locale_scope.dart';
import '../server/proot_service.dart';
import 'create_download_version_page.dart';
import 'download_session.dart';

/// 流程第 8 页：选择 proot 容器（Survivalcraft 类型独有）。
///
/// 实例文件将解压到所选容器 rootfs 的 `/opt/{实例id}` 下，绕过 Android 内部
/// 存储的 noexec 限制。选定后进入版本选择页。
class SelectProotContainerPage extends StatefulWidget {
  const SelectProotContainerPage({super.key, required this.session});

  final DownloadSession session;

  @override
  State<SelectProotContainerPage> createState() =>
      _SelectProotContainerPageState();
}

class _SelectProotContainerPageState extends State<SelectProotContainerPage> {
  List<ProotRootfsInfo> _rootfsList = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _rootfsList = [];
    });
    try {
      final available = await const ProotService().isAvailable();
      if (!available) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = context.tr('instance.prootNotAvailable');
        });
        return;
      }
      final list = await const ProotService().listRootfs();
      if (!mounted) return;
      setState(() {
        _rootfsList = list;
        _loading = false;
        if (list.isEmpty) _error = context.tr('instance.noProotRootfs');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _select(ProotRootfsInfo rootfs) {
    widget.session.selectedProotRootfsId = rootfs.id;
    widget.session.selectedProotRootfsDir = rootfs.dir;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelectVersionPage(
          session: widget.session,
          stage: VersionStage.forServerType('survivalcraft'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('instance.titleSelectProotContainer')),
      ),
      body: SafeArea(child: _buildBody(theme)),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              context.tr('instance.loadingProotContainers'),
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(context.tr('common.retry')),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.tr('instance.selectProotContainerHint'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final rootfs in _rootfsList) ...[
          Card(
            child: ListTile(
              leading: Icon(
                rootfs.isGeneric ? Icons.inventory_2_outlined : Icons.memory,
                size: 36,
              ),
              title: Text(
                rootfs.envName.isNotEmpty ? rootfs.envName : rootfs.id,
                style: const TextStyle(fontSize: 16),
              ),
              subtitle: Text(
                rootfs.isGeneric
                    ? context.tr('instance.prootContainerGeneric')
                    : '${rootfs.envType} · ${rootfs.envVersionName}',
              ),
              trailing: const Icon(Icons.chevron_right),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              onTap: () => _select(rootfs),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

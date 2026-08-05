import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../i18n/locale_scope.dart';
import '../server/proot_service.dart';
import '../widgets/ec_preference.dart';
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
    final theme = MiuixTheme.of(context);
    return MiuixScaffold(
      topBar: EcTopAppBar(
        title: context.tr('instance.titleSelectProotContainer'),
      ),
      content: (padding) => Padding(
        padding: padding,
        child: SafeArea(top: false, child: _buildBody(theme)),
      ),
    );
  }

  Widget _buildBody(MiuixThemeData theme) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiuixInfiniteProgressIndicator(),
            const SizedBox(height: 24),
            MiuixText(
              context.tr('instance.loadingProotContainers'),
              style: theme.textStyles.title4,
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return EcErrorRetry(
        message: _error!,
        retryLabel: context.tr('common.retry'),
        onRetry: _load,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        MiuixCard(
          child: Row(
            children: [
              MiuixIcon(icon: Icons.info_outline, tint: theme.colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: MiuixText(
                  context.tr('instance.selectProotContainerHint'),
                  style: theme.textStyles.footnote1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final rootfs in _rootfsList) ...[
          EcCardTile(
            leading: MiuixIcon(
              icon: rootfs.isGeneric
                  ? Icons.inventory_2_outlined
                  : Icons.memory,
              size: 36,
            ),
            title: rootfs.envName.isNotEmpty ? rootfs.envName : rootfs.id,
            summary: rootfs.isGeneric
                ? context.tr('instance.prootContainerGeneric')
                : '${rootfs.envType} · ${rootfs.envVersionName}',
            margin: const EdgeInsets.only(bottom: 12),
            onTap: () => _select(rootfs),
          ),
        ],
      ],
    );
  }
}

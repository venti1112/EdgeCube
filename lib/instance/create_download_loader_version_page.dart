import 'package:flutter/material.dart';

import '../config/java_env_pref_store.dart';
import '../i18n/locale_scope.dart';
import '../widgets/error_dialog.dart';
import '../server/java_env_resolver.dart';
import '../server/proot_service.dart';
import '../server/server_service.dart';
import 'create_download_install_loader_page.dart';
import 'create_download_progress_page.dart';
import 'download_session.dart';
import 'instance_controller.dart';
import 'version_fetch_service.dart';
import 'version_select_step.dart';

/// 加载器版本页的阶段描述。
class LoaderStage {
  const LoaderStage({
    required this.loader, // 'fabric' / 'forge' / 'neoforge'
    required this.mcVersion,
    this.versions,
  });

  final String loader;
  final String mcVersion;

  /// Forge/NeoForge 版本已随 MC 版本映射缓存，直接给出；Fabric 为 null（需拉取）。
  final List<String>? versions;
}

/// 流程第 5 页：选择模组加载器版本（模组端独有）。
///
/// - Fabric：拉取该 MC 版本的 Loader 列表，选定后确认 → 创建实例 → 下载页
/// - Forge/NeoForge：展示缓存的版本列表，选定后确认 → 创建实例 →
///   安装加载器页（页 7）
class SelectLoaderVersionPage extends StatefulWidget {
  const SelectLoaderVersionPage({
    super.key,
    required this.session,
    required this.stage,
  });

  final DownloadSession session;
  final LoaderStage stage;

  @override
  State<SelectLoaderVersionPage> createState() =>
      _SelectLoaderVersionPageState();
}

class _SelectLoaderVersionPageState extends State<SelectLoaderVersionPage> {
  DownloadSession get _session => widget.session;
  InstanceController get _controller => _session.controller;
  LoaderStage get _stage => widget.stage;

  List<String> _versions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Forge/NeoForge 版本已缓存，无需拉取。
    if (_stage.versions != null) {
      setState(() {
        _versions = _stage.versions!;
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _versions = [];
    });
    try {
      final versions =
          await VersionFetchService.fetchFabricLoaderVersions(_stage.mcVersion);
      if (!mounted) return;
      setState(() {
        _versions = versions;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.tr('instance.fetchFabricLoaderVersionsFailed',
            {'error': '$e'});
      });
    }
  }

  String get _title => switch (_stage.loader) {
        'forge' => context.tr('instance.titleSelectForgeVersion'),
        'neoforge' => context.tr('instance.titleSelectNeoforgeVersion'),
        _ => context.tr('instance.titleSelectFabricLoaderVersion'),
      };

  Future<bool> _checkJavaEnvAvailable() async {
    final results = await Future.wait([
      ServerService().availableJreIds(),
      const ProotService().listRootfs().catchError(
            (_) => <ProotRootfsInfo>[],
          ),
      JavaEnvPrefStore.loadPriority(),
    ]);
    final env = resolveJavaEnv(
      priority: results[2] as JavaEnvPriority,
      nativeJreIds: results[0] as List<String>,
      rootfsList: results[1] as List<ProotRootfsInfo>,
      preferredNativeJreId: null,
    );
    if (env != null) return true;
    if (!mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('instance.noJavaEnvTitle')),
        content: Text(ctx.tr('instance.noJavaEnvForInstall')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.tr('common.ok')),
          ),
        ],
      ),
    );
    return false;
  }

  Future<void> _onSelect(String loaderVersion) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('instance.confirmVersionTitle')),
        content: Text(
          switch (_stage.loader) {
            'forge' => ctx.tr('instance.confirmInstallForge',
                {'version': _stage.mcVersion, 'loader': loaderVersion}),
            'neoforge' => ctx.tr('instance.confirmInstallNeoforge',
                {'version': _stage.mcVersion, 'loader': loaderVersion}),
            _ => ctx.tr('instance.confirmDownloadFabric',
                {'version': _stage.mcVersion, 'loader': loaderVersion}),
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('common.ok')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Forge / NeoForge：需要 Java 环境来运行安装器，先检查是否有可用环境
    // （原生 JRE 或 proot Java 容器），没有则直接提示、不进入下载步骤。
    if (_stage.loader == 'forge' || _stage.loader == 'neoforge') {
      final ok = await _checkJavaEnvAvailable();
      if (!ok || !mounted) return;
    }

    try {
      final instance = await _controller.createInstance(_session.name);
      if (!mounted) return;

      if (_stage.loader == 'fabric') {
        _session.selectedLoaderVersion = loaderVersion;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DownloadProgressPage(
              session: _session,
              instanceId: instance.id,
            ),
          ),
        );
        return;
      }

      // Forge / NeoForge：进入安装加载器页；成功后（pop true）结束整个流程。
      _session.selectedForgeVersion =
          _stage.loader == 'forge' ? loaderVersion : _session.selectedForgeVersion;
      _session.selectedNeoforgeVersion = _stage.loader == 'neoforge'
          ? loaderVersion
          : _session.selectedNeoforgeVersion;
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => InstallLoaderPage(
            instanceController: _controller,
            instanceId: instance.id,
            mcVersion: _stage.mcVersion,
            loaderVersion: loaderVersion,
            installerType: _stage.loader,
          ),
        ),
      );
      if (result == true && mounted) {
        finishDownloadFlow(context);
      } else if (result != true) {
        // 用户取消/失败返回：清理已创建的空实例。
        await _controller.deleteInstance(instance.id);
      }
    } on DuplicateInstanceNameException {
      if (mounted) _showDuplicateDialog(_session.name);
    }
  }

  Future<void> _showDuplicateDialog(String name) =>
      showErrorDialog(context, context.tr('instance.duplicateName', {'name': name}));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(
        child: VersionSelectStep(
          versions: _versions,
          loading: _loading,
          error: _error,
          onRetry: _load,
          onSelect: _onSelect,
        ),
      ),
    );
  }
}

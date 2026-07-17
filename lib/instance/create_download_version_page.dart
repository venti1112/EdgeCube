import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../i18n/locale_scope.dart';
import '../instance/instance.dart';
import 'create_download_loader_version_page.dart';
import 'create_download_progress_page.dart';
import 'download_runner.dart';
import 'download_session.dart';
import 'instance_controller.dart';
import 'version_fetch_service.dart';
import 'version_select_step.dart';

/// 版本页要展示/处理哪一类版本。
enum VersionKind {
  /// 直接选版本即可下载（原版/插件/代理/基岩端）。
  simple,

  /// Fabric：选 Minecraft 版本，下一步选 Loader 版本。
  fabricMc,

  /// Forge：选 Minecraft 版本，下一步选 Forge 版本。
  forgeMc,

  /// NeoForge：选 Minecraft 版本，下一步选 NeoForge 版本。
  neoforgeMc,

  /// Survivalcraft：选版本后下载并解压到 proot 容器。
  survivalcraft,
}

/// 版本页的阶段描述：类型 + 分类。
class VersionStage {
  const VersionStage({required this.kind, required this.serverType});

  final VersionKind kind;
  final String serverType;

  /// 依据具体服务端类型推导阶段。
  factory VersionStage.forServerType(String type) {
    switch (type) {
      case 'fabric':
        return VersionStage(kind: VersionKind.fabricMc, serverType: type);
      case 'forge':
        return VersionStage(kind: VersionKind.forgeMc, serverType: type);
      case 'neoforge':
        return VersionStage(kind: VersionKind.neoforgeMc, serverType: type);
      case 'survivalcraft':
        return VersionStage(kind: VersionKind.survivalcraft, serverType: type);
      default:
        return VersionStage(kind: VersionKind.simple, serverType: type);
    }
  }
}

/// 流程第 4 页：选择版本。
///
/// 根据 [stage] 拉取对应版本列表并处理选择：
/// - simple：确认 → 创建实例 → 下载页
/// - fabricMc / forgeMc / neoforgeMc：记录 MC 版本 → 加载器版本页
/// - survivalcraft：确认 → 创建实例并迁移到 proot 容器 → 下载并解压页
class SelectVersionPage extends StatefulWidget {
  const SelectVersionPage({
    super.key,
    required this.session,
    required this.stage,
  });

  final DownloadSession session;
  final VersionStage stage;

  @override
  State<SelectVersionPage> createState() => _SelectVersionPageState();
}

class _SelectVersionPageState extends State<SelectVersionPage> {
  DownloadSession get _session => widget.session;
  InstanceController get _controller => _session.controller;
  String get _serverType => widget.stage.serverType;

  List<String> _versions = [];
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
      _versions = [];
    });
    try {
      final versions = await _fetch();
      if (!mounted) return;
      setState(() {
        _versions = versions;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.tr('instance.fetchVersionsFailed', {'error': '$e'});
      });
    }
  }

  Future<List<String>> _fetch() async {
    switch (widget.stage.kind) {
      case VersionKind.fabricMc:
        return VersionFetchService.fetchFabricMcVersions();
      case VersionKind.forgeMc:
        _session.forgeVersionMap =
            await VersionFetchService.fetchAllForgeVersions();
        return _session.forgeVersionMap.keys.toList();
      case VersionKind.neoforgeMc:
        _session.neoforgeVersionMap =
            await VersionFetchService.fetchAllNeoforgeVersions();
        return _session.neoforgeVersionMap.keys.toList();
      case VersionKind.survivalcraft:
        return VersionFetchService.fetchSurvivalcraftVersions();
      case VersionKind.simple:
        return _fetchSimple(_serverType);
    }
  }

  Future<List<String>> _fetchSimple(String type) async {
    switch (type) {
      case 'vanilla':
        final r = await DownloadRunner.fetchVanillaVersions();
        _session.vanillaVersionUrls = r.urls;
        return r.versions;
      case 'paper':
        return VersionFetchService.fetchPaperVersions();
      case 'spigot':
        return VersionFetchService.fetchSpigotVersions();
      case 'craftbukkit':
        return VersionFetchService.fetchCraftBukkitVersions();
      case 'purpur':
        return VersionFetchService.fetchPurpurVersions();
      case 'leaf':
        return VersionFetchService.fetchLeafVersions();
      case 'leaves':
        return VersionFetchService.fetchLeavesVersions();
      case 'powernukkitx':
        final r = await VersionFetchService.fetchPowernukkitxVersions();
        _session.powernukkitxMcVersions
          ..clear()
          ..addAll(r.mcVersions);
        return r.versions;
      case 'pocketmine':
        final r = await VersionFetchService.fetchPocketmineVersions();
        _session.pocketmineMcpeVersions
          ..clear()
          ..addAll(r.mcpeVersions);
        return r.versions;
      case 'allay':
        return VersionFetchService.fetchAllayVersions();
      default:
        return VersionFetchService.fetchVelocityVersions();
    }
  }

  // —— 选择处理 ——

  void _onSelect(String version) {
    switch (widget.stage.kind) {
      case VersionKind.fabricMc:
        _session.selectedMcVersion = version;
        _pushLoader(LoaderStage(
          loader: 'fabric',
          mcVersion: version,
        ));
      case VersionKind.forgeMc:
        _session.selectedForgeMcVersion = version;
        _pushLoader(LoaderStage(
          loader: 'forge',
          mcVersion: version,
          versions: _session.forgeVersionMap[version] ?? const [],
        ));
      case VersionKind.neoforgeMc:
        _session.selectedNeoforgeMcVersion = version;
        _pushLoader(LoaderStage(
          loader: 'neoforge',
          mcVersion: version,
          versions: _session.neoforgeVersionMap[version] ?? const [],
        ));
      case VersionKind.survivalcraft:
        _confirmSurvivalcraft(version);
      case VersionKind.simple:
        _confirmSimple(version);
    }
  }

  void _pushLoader(LoaderStage stage) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SelectLoaderVersionPage(session: _session, stage: stage),
      ),
    );
  }

  Future<void> _confirmSimple(String version) async {
    final isPocketmine = _serverType == 'pocketmine';
    final isPowernukkitx = _serverType == 'powernukkitx';
    final isAllay = _serverType == 'allay';
    final mcpeVersion = isPocketmine
        ? _session.pocketmineMcpeVersions[version]
        : (isPowernukkitx ? _session.powernukkitxMcVersions[version] : null);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('instance.confirmVersionTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isPocketmine
                  ? ctx.tr('instance.confirmDownloadPmmp', {'version': version})
                  : isPowernukkitx
                      ? ctx.tr('instance.confirmDownloadPowernukkitx',
                          {'version': version})
                      : isAllay
                          ? ctx.tr('instance.confirmDownloadAllay',
                              {'version': version})
                          : ctx.tr('instance.confirmDownload',
                              {'version': version}),
            ),
            if (mcpeVersion != null) ...[
              const SizedBox(height: 8),
              Text(
                ctx.tr('instance.mcpeVersionLabel', {'version': mcpeVersion}),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ],
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

    try {
      final instance = await _controller.createInstance(_session.name);
      if (!mounted) return;
      _session.selectedVersion = version;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DownloadProgressPage(
            session: _session,
            instanceId: instance.id,
          ),
        ),
      );
    } on DuplicateInstanceNameException {
      if (mounted) _showDuplicateDialog(_session.name);
    }
  }

  /// Survivalcraft：确认后创建实例并迁移到 proot 容器 rootfs 的 /opt/{id}，
  /// 设置 proot 运行环境与启动命令，随后进入下载并解压页。
  Future<void> _confirmSurvivalcraft(String version) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('instance.confirmVersionTitle')),
        content: Text(
          ctx.tr('instance.confirmDownloadSurvivalcraft', {'version': version}),
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

    try {
      final instance = await _controller.createInstance(_session.name);
      if (!mounted) return;
      _session.selectedVersion = version;

      // 将实例目录从默认 sdcard 路径迁移到 proot 容器 rootfs 的 /opt/{id}。
      // Android 内部存储（/sdcard）有 noexec 挂载标志，ELF/.so 无法执行；
      // proot rootfs 位于应用私有存储，无此限制。
      final rootfsDir = _session.selectedProotRootfsDir!;
      final containerPath = p.join(rootfsDir, 'opt', instance.id);
      try {
        await Directory(containerPath).create(recursive: true);
      } catch (e) {
        await _controller.deleteInstance(instance.id);
        if (!mounted) return;
        _showErrorDialog(
          context.tr('instance.createContainerDirFailed', {'error': '$e'}),
        );
        return;
      }
      // 删除默认路径下创建的空目录，更新实例路径到容器内。
      final defaultDir = await _controller.directoryForId(instance.id);
      if (await defaultDir.exists()) {
        try {
          await defaultDir.delete(recursive: true);
        } catch (_) {}
      }
      await _controller.updatePath(instance.id, containerPath);
      // 设置 proot 运行环境与启动命令。zip 解压不保留可执行位，启动前 chmod +x。
      final startupCommand =
          'cd /opt/${instance.id} && chmod +x ./Survivalcraft && ./Survivalcraft';
      await _controller.updateConfig(
        instance.id,
        runtime: kRuntimeProot,
        runtimeEnvId: _session.selectedProotRootfsId,
        prootStartupCommand: startupCommand,
        compatMode: true,
      );

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DownloadProgressPage(
            session: _session,
            instanceId: instance.id,
          ),
        ),
      );
    } on DuplicateInstanceNameException {
      if (mounted) _showDuplicateDialog(_session.name);
    }
  }

  Future<void> _showDuplicateDialog(String name) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('instance.noticeTitle')),
          content: Text(ctx.tr('instance.duplicateName', {'name': name})),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(ctx.tr('common.ok')),
            ),
          ],
        ),
      );

  Future<void> _showErrorDialog(String message) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('instance.noticeTitle')),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(ctx.tr('common.ok')),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    // pmmp/pnx 版本附带对应的 MCBE 客户端版本作为副标题。
    Map<String, String>? subtitles;
    if (_serverType == 'pocketmine') {
      subtitles = {
        for (final v in _versions)
          if (_session.pocketmineMcpeVersions.containsKey(v))
            v: context.tr('instance.pmmpVersionLabel',
                {'version': _session.pocketmineMcpeVersions[v]!}),
      };
    } else if (_serverType == 'powernukkitx') {
      subtitles = {
        for (final v in _versions)
          if (_session.powernukkitxMcVersions.containsKey(v))
            v: context.tr('instance.pnxVersionLabel',
                {'version': _session.powernukkitxMcVersions[v]!}),
      };
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('instance.titleSelectVersion'))),
      body: SafeArea(
        child: VersionSelectStep(
          versions: _versions,
          loading: _loading,
          error: _error,
          subtitles: subtitles,
          onRetry: _load,
          onSelect: _onSelect,
        ),
      ),
    );
  }
}

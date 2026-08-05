import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../files/archive_service.dart';
import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../i18n/locale_scope.dart';
import '../mods/modpack_service.dart';
import '../widgets/ec_preference.dart';
import '../widgets/miuix_dialog.dart';
import 'create_download_install_loader_page.dart';
import 'create_instance_page.dart';
import 'download_info.dart';
import 'download_runner.dart';
import 'instance_controller.dart';
import 'progress_steps.dart';

/// 「导入整合包」独立页：解析整合包并安装到已创建的空实例。
///
/// 实例由上一页（向导根页）创建并通过 [instanceId] 传入。参考 PCL-CE 的
/// ModModpack.ModpackInstall / InstallPackModrinth：
/// 1. 选择整合包文件 → 2. 检测格式 → 3.（Modrinth）解析清单 → 4. 确认 →
///    5. 下载服务端 mod → 6. 解压 overrides → 7. 下载服务端 jar。
/// 普通 zip：直接解压到实例目录后完成。
///
/// 成功后 `pop(CreateInstanceResult.done)`；用户取消则 `pop()` 返回根页。未完成即
/// 离开时，[dispose] 清理这个空实例。
class ModpackImportPage extends StatefulWidget {
  const ModpackImportPage({
    super.key,
    required this.controller,
    required this.instanceId,
  });

  final InstanceController controller;
  final String instanceId;

  @override
  State<ModpackImportPage> createState() => _ModpackImportPageState();
}

class _ModpackImportPageState extends State<ModpackImportPage> {
  bool _completed = false;

  /// 整合包导入状态。
  String _modpackPhase =
      ''; // parsing / downloading / extracting / preparing / idle
  int _modpackCurrent = 0;
  int _modpackTotal = 0;
  String _modpackCurrentFile = '';
  String? _modpackError;

  /// 整合包 Vanilla 服务端下载所需的版本详情 URL 映射。
  Map<String, String> _vanillaVersionUrls = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _doModpackImport());
  }

  @override
  void dispose() {
    // 未完成即离开：清理已创建的空实例。
    if (!_completed) {
      widget.controller.deleteInstance(widget.instanceId);
    }
    super.dispose();
  }

  Future<void> _doModpackImport() async {
    // 文件访问权限。
    if (!await StoragePermission.isGranted()) {
      if (!mounted) return;
      final go = await _showImportPermissionDialog();
      if (go != true) {
        _cancel();
        return;
      }
      await StoragePermission.request();
      if (!mounted) return;
      _doModpackImport();
      return;
    }

    // 选择整合包文件。
    if (!mounted) return;
    final sourcePath = await pickFromSystem(
      context,
      mode: SystemPickMode.file,
      allowedExtensions: const ['.mrpack', '.zip'],
    );
    if (sourcePath == null) {
      _cancel();
      return;
    }

    setState(() => _modpackPhase = 'parsing');
    try {
      final modpack = await ModpackService.detectAndParse(sourcePath);
      if (modpack == null) {
        // 无可识别清单：作为普通 zip 直接解压到实例目录后完成。
        await _extractPlainZip(sourcePath);
        return;
      }
      if (!mounted) return;

      // 确认对话框。
      final confirmed = await _showModpackConfirm(modpack);
      if (confirmed != true) {
        _cancel();
        return;
      }

      final dir = await widget.controller.directoryForId(widget.instanceId);

      // 下载服务端 mod 文件。
      setState(() {
        _modpackPhase = 'downloading';
        _modpackCurrent = 0;
        _modpackTotal = modpack.serverFiles.length;
        _modpackError = null;
      });
      await ModpackService.downloadServerFiles(
        modpack,
        dir,
        onProgress: (current, total, fileName) {
          if (!mounted) return;
          setState(() {
            _modpackCurrent = current;
            _modpackTotal = total;
            _modpackCurrentFile = fileName;
          });
        },
      );

      // 解压 overrides。
      if (!mounted) return;
      setState(() {
        _modpackPhase = 'extracting';
        _modpackError = null;
      });
      await ModpackService.extractOverrides(sourcePath, modpack, dir);

      // 下载服务端 jar。
      if (!mounted) return;
      setState(() => _modpackPhase = 'preparing');
      await _downloadServerJarFromModpack(modpack);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modpackError = context.tr('instance.modpackFailed', {'error': '$e'});
      });
    }
  }

  /// 普通 zip 整合包：解压到实例目录后完成（与导入压缩包行为一致）。
  Future<void> _extractPlainZip(String sourcePath) async {
    setState(() {
      _modpackPhase = 'extracting';
      _modpackError = null;
    });
    try {
      final dir = await widget.controller.directoryForId(widget.instanceId);
      await ArchiveService.extractWithProgress(sourcePath, dir.path);
      _finish();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modpackError = context.tr('instance.extractArchiveFailed', {
          'error': '$e',
        });
      });
    }
  }

  /// 根据整合包 dependencies 下载对应服务端 jar，复用共享下载逻辑。
  Future<void> _downloadServerJarFromModpack(ParsedModpack modpack) async {
    final deps = modpack.dependencies;
    final mcVersion = deps['minecraft'];
    if (mcVersion == null || mcVersion.isEmpty) {
      // 无 MC 版本信息，无法自动下载服务端，直接完成。
      _finish();
      return;
    }

    final fabricLoader = deps['fabric-loader'];
    final forge = deps['forge'];
    final neoforge = deps['neo-forge'] ?? deps['neoforge'];
    final quiltLoader = deps['quilt-loader'];

    if (fabricLoader != null) {
      await _modpackDownloadJar(
        serverType: 'fabric',
        info:
            await DownloadRunner.tryMirrorDownloadInfo('fabric', mcVersion) ??
            await DownloadRunner.fetchFabricDownloadInfo(
              mcVersion,
              fabricLoader,
            ),
        selectedMcVersion: mcVersion,
      );
    } else if (forge != null) {
      await _modpackInstallLoader(
        installerType: 'forge',
        mcVersion: mcVersion,
        loaderVersion: forge,
      );
    } else if (neoforge != null) {
      await _modpackInstallLoader(
        installerType: 'neoforge',
        mcVersion: _deriveNeoforgeMcKey(neoforge),
        loaderVersion: neoforge,
      );
    } else if (quiltLoader != null) {
      // Quilt 无独立服务端下载流程：Fabric 兼容，下载 Fabric 服务端。
      await _modpackDownloadJar(
        serverType: 'fabric',
        info:
            await DownloadRunner.tryMirrorDownloadInfo('fabric', mcVersion) ??
            await DownloadRunner.fetchFabricDownloadInfo(
              mcVersion,
              quiltLoader,
            ),
        selectedMcVersion: mcVersion,
      );
    } else {
      // Vanilla 服务端：先填充版本详情 URL 映射。
      try {
        final r = await DownloadRunner.fetchVanillaVersions();
        _vanillaVersionUrls = r.urls;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _modpackError = context.tr('instance.fetchVersionsFailed', {
            'error': '$e',
          });
        });
        return;
      }
      await _modpackDownloadJar(
        serverType: 'vanilla',
        info:
            await DownloadRunner.tryMirrorDownloadInfo('vanilla', mcVersion) ??
            await DownloadRunner.fetchVanillaDownloadInfo(
              mcVersion,
              _vanillaVersionUrls,
            ),
        selectedVersion: mcVersion,
      );
    }
  }

  /// 整合包场景下载服务端 jar（复用 DownloadRunner，保持在整合包进度页）。
  Future<void> _modpackDownloadJar({
    required String serverType,
    required DownloadInfo info,
    String? selectedVersion,
    String? selectedMcVersion,
  }) async {
    try {
      await DownloadRunner.downloadAndConfigure(
        controller: widget.controller,
        instanceId: widget.instanceId,
        info: info,
        serverType: serverType,
        selectedVersion: selectedVersion,
        selectedMcVersion: selectedMcVersion,
      );
      _finish();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modpackError = context.tr('instance.downloadFailed', {'error': '$e'});
      });
    }
  }

  /// 整合包场景安装 Forge/NeoForge 加载器（push 到安装页）。
  Future<void> _modpackInstallLoader({
    required String installerType,
    required String mcVersion,
    required String loaderVersion,
  }) async {
    if (!mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => InstallLoaderPage(
          instanceController: widget.controller,
          instanceId: widget.instanceId,
          mcVersion: mcVersion,
          loaderVersion: loaderVersion,
          installerType: installerType,
        ),
      ),
    );
    if (result == true && mounted) {
      _finish();
    }
  }

  /// 由 NeoForge 版本号推导 MC 版本键（与 fetchAllNeoforgeVersions 分组规则一致）。
  /// 三段式 "21.1.234" → "21.1"；四段式 "26.1.2.71" → "26.1.2"。
  String _deriveNeoforgeMcKey(String nfVersion) {
    final parts = nfVersion.split('-').first.split('.');
    if (parts.length >= 4) return '${parts[0]}.${parts[1]}.${parts[2]}';
    if (parts.length >= 2) return '${parts[0]}.${parts[1]}';
    return nfVersion;
  }

  Future<bool?> _showModpackConfirm(ParsedModpack modpack) {
    final mc = modpack.dependencies['minecraft'] ?? '-';
    final loader = _modpackLoaderLabel(modpack);
    final modCount = modpack.serverFiles.length;
    return showMiuixConfirm(
      context,
      title: context.tr('instance.modpackConfirmTitle'),
      message: context.tr('instance.modpackSummary', {
        'name': modpack.name ?? '-',
        'mc': mc,
        'loader': loader,
        'count': '$modCount',
      }),
      cancelLabel: context.tr('common.cancel'),
      confirmLabel: context.tr('common.ok'),
    );
  }

  String _modpackLoaderLabel(ParsedModpack modpack) {
    final deps = modpack.dependencies;
    if (deps['fabric-loader'] != null) return 'Fabric';
    if (deps['quilt-loader'] != null) return 'Quilt';
    if (deps['forge'] != null) return 'Forge';
    if (deps['neo-forge'] != null || deps['neoforge'] != null) {
      return 'NeoForge';
    }
    if (deps['minecraft'] != null) return context.tr('instance.modpackVanilla');
    return '-';
  }

  Future<bool?> _showImportPermissionDialog() {
    return showMiuixConfirm(
      context,
      title: context.tr('instance.storagePermissionTitle'),
      message: context.tr('instance.importStoragePermissionMessage'),
      cancelLabel: context.tr('common.cancel'),
      confirmLabel: context.tr('instance.goGrant'),
    );
  }

  void _finish() {
    _completed = true;
    if (mounted) Navigator.of(context).pop(CreateInstanceResult.done);
  }

  void _cancel() {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return MiuixScaffold(
      topBar: EcTopAppBar(title: context.tr('instance.titleModpackImport')),
      content: (padding) => Padding(
        padding: padding,
        // padding.top 已含顶栏（连同状态栏）高度，故这里的 SafeArea 只保留
        // 左右与底部，top 置 false，否则状态栏高度会被重复计入。
        child: SafeArea(
          top: false,
          child: ModpackImportStep(
            phase: _modpackPhase,
            current: _modpackCurrent,
            total: _modpackTotal,
            currentFile: _modpackCurrentFile,
            error: _modpackError,
            onCancel: _cancel,
          ),
        ),
      ),
    );
  }
}

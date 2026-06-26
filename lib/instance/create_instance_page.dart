import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../config/network_store.dart';
import '../files/archive_service.dart';
import '../files/file_service.dart';
import '../files/storage_permission.dart';
import '../files/system_picker.dart';
import '../i18n/locale_scope.dart';
import '../i18n/i18n_service.dart';
import '../instance/instance.dart';
import '../instance/instance_controller.dart';
import '../instance/instance_scope.dart';
import '../mods/modpack_service.dart';
import '../net/msl_mirror.dart';
import '../server/server_service.dart';

enum _WizardStep {
  nameEntry,
  serverType,
  versionSelect,
  fabricMcVersionSelect,
  fabricLoaderVersionSelect,
  forgeMcVersionSelect,
  forgeVersionSelect,
  neoforgeMcVersionSelect,
  neoforgeVersionSelect,
  downloading,
  forgeInstalling,
  importFile,
  importArchive,
  extractArchive,
  modpackImport,
}

/// 新建实例向导结果。
enum CreateInstanceResult { done, cancelled }

/// 新建实例向导页。
///
/// 流程：
/// 1. 输入名称 → 选择「下载服务端」或「导入服务端」
/// 2a. 下载服务端 → 选类型（官方/Paper/Fabric/Forge） → 选版本 → 创建实例并下载
///     - Forge 特殊流程：下载 Installer jar → 运行 java -jar --installServer → 配置
/// 2b. 导入服务端 → 创建实例 → 选文件导入
///
/// 如果用户中途退出（未完成），自动删除已创建的空实例。
class CreateInstancePage extends StatefulWidget {
  const CreateInstancePage({super.key});

  @override
  State<CreateInstancePage> createState() => _CreateInstancePageState();
}

class _CreateInstancePageState extends State<CreateInstancePage> {
  static const _fileService = FileService();

  _WizardStep _step = _WizardStep.nameEntry;
  final _nameController = TextEditingController();
  String? _instanceId;
  String? _serverType;
  List<String> _versions = [];
  bool _loadingVersions = false;
  String? _versionError;
  double? _downloadProgress;
  String? _downloadError;
  bool _completed = false;

  /// 缓存版本详情页 URL（Vanilla）。
  Map<String, String> _vanillaVersionUrls = {};

  /// 用户确认要下载的版本号（弹窗确认后记录，供下载和自动 Java 版本推断使用）。
  String? _selectedVersion;

  /// Fabric 流程中选择的 Minecraft 版本与 Loader 版本。
  List<String> _fabricMcVersions = [];
  String? _selectedMcVersion;
  String? _selectedLoaderVersion;

  /// Forge 流程：缓存全量版本映射 {mcVersion: [forgeVersion...]}。
  Map<String, List<String>> _forgeVersionMap = {};

  /// Forge 流程中选择的 Minecraft 版本与 Forge 版本。
  String? _selectedForgeMcVersion;
  String? _selectedForgeVersion;

  /// NeoForge 流程：缓存全量版本映射 {mcVersion: [neoforgeVersion...]}。
  Map<String, List<String>> _neoforgeVersionMap = {};

  /// NeoForge 流程中选择的 Minecraft 版本与 NeoForge 版本。
  String? _selectedNeoforgeMcVersion;
  String? _selectedNeoforgeVersion;

  /// Forge/NeoForge 安装日志输出。
  final List<String> _forgeInstallLogs = [];
  bool _forgeInstalling = false;
  String? _forgeInstallError;
  StreamSubscription<dynamic>? _forgeEventSub;

  bool _extracting = false;
  String? _extractError;
  double? _extractProgress;

  /// 整合包导入状态。
  ModpackFormat? _modpackFormat;
  String _modpackPhase = ''; // parsing / downloading / extracting / preparing / idle
  int _modpackCurrent = 0;
  int _modpackTotal = 0;
  String _modpackCurrentFile = '';
  String? _modpackError;

  /// 当前安装器类型（'forge' 或 'neoforge'），用于 UI 文案和日志文件名区分。
  String _installerType = 'forge';

  static const _forgeChannel = MethodChannel('com.venti1112.edgecube/forge');
  static const _forgeEventChannel = EventChannel(
    'com.venti1112.edgecube/forge_events',
  );

  late InstanceController _instanceController;

  @override
  void initState() {
    super.initState();
    _instanceController = InstanceScope.of(context);
    _nameController.text = context.tr('instance.defaultName');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _forgeEventSub?.cancel();
    _forgeEventSub = null;
    // 如果向导未完成且已创建了实例，清理空实例。
    if (!_completed && _instanceId != null) {
      _instanceController.deleteInstance(_instanceId!);
    }
    super.dispose();
  }

  // —— 步骤导航 ——

  /// 校验名称：非空且不重名。重复时弹出提示对话框。
  Future<bool> _validateName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return false;
    if (_instanceController.instances.any((i) => i.name == name)) {
      await _showDuplicateDialog(name);
      return false;
    }
    return _ensureInstanceStoragePermission();
  }

  Future<bool> _ensureInstanceStoragePermission() async {
    if (await StoragePermission.isGranted()) return true;
    if (!mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('instance.storagePermissionTitle')),
        content: Text(ctx.tr('instance.createStoragePermissionMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('instance.goGrant')),
          ),
        ],
      ),
    );
    if (go != true) return false;
    await StoragePermission.request();
    return false;
  }

  Future<void> _goToServerType() async {
    if (!await _validateName()) return;
    setState(() => _step = _WizardStep.serverType);
  }

  Future<void> _selectServerType(String type) async {
    _serverType = type;
    if (type == 'fabric') {
      setState(() {
        _step = _WizardStep.fabricMcVersionSelect;
        _loadingVersions = true;
        _versionError = null;
        _versions = [];
      });
      try {
        _fabricMcVersions = await _fetchFabricMcVersions();
        _versions = _fabricMcVersions;
        if (!mounted) return;
        setState(() => _loadingVersions = false);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loadingVersions = false;
          _versionError = context.tr('instance.fetchMcVersionsFailed', {
            'error': '$e',
          });
        });
      }
      return;
    }
    if (type == 'forge') {
      setState(() {
        _step = _WizardStep.forgeMcVersionSelect;
        _loadingVersions = true;
        _versionError = null;
        _versions = [];
      });
      try {
        _forgeVersionMap = await _fetchAllForgeVersions();
        _versions = _forgeVersionMap.keys.toList();
        if (!mounted) return;
        setState(() => _loadingVersions = false);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loadingVersions = false;
          _versionError = context.tr('instance.fetchForgeVersionsFailed', {
            'error': '$e',
          });
        });
      }
      return;
    }
    if (type == 'neoforge') {
      setState(() {
        _step = _WizardStep.neoforgeMcVersionSelect;
        _loadingVersions = true;
        _versionError = null;
        _versions = [];
      });
      try {
        _neoforgeVersionMap = await _fetchAllNeoforgeVersions();
        _versions = _neoforgeVersionMap.keys.toList();
        if (!mounted) return;
        setState(() => _loadingVersions = false);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loadingVersions = false;
          _versionError = context.tr('instance.fetchNeoforgeVersionsFailed', {
            'error': '$e',
          });
        });
      }
      return;
    }
    setState(() {
      _step = _WizardStep.versionSelect;
      _loadingVersions = true;
      _versionError = null;
      _versions = [];
    });
    try {
      _versions = await _fetchVersions(type);
      if (!mounted) return;
      setState(() => _loadingVersions = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingVersions = false;
        _versionError = context.tr('instance.fetchVersionsFailed', {
          'error': '$e',
        });
      });
    }
  }

  Future<void> _startImport() async {
    if (!await _validateName()) return;
    final name = _nameController.text.trim();
    try {
      final instance = await _instanceController.createInstance(name);
      if (!mounted) return;
      _instanceId = instance.id;
      setState(() => _step = _WizardStep.importFile);
      _doImport(instance.id);
    } on DuplicateInstanceNameException {
      if (!mounted) return;
      _showDuplicateDialog(name);
    }
  }

  Future<void> _startImportArchive() async {
    if (!await _validateName()) return;
    final name = _nameController.text.trim();
    try {
      final instance = await _instanceController.createInstance(name);
      if (!mounted) return;
      _instanceId = instance.id;
      setState(() => _step = _WizardStep.importArchive);
      _doImportArchive(instance.id);
    } on DuplicateInstanceNameException {
      if (!mounted) return;
      _showDuplicateDialog(name);
    }
  }

  Future<void> _doImportArchive(String instanceId) async {
    if (!await StoragePermission.isGranted()) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.tr('instance.storagePermissionTitle')),
          content: Text(context.tr('instance.importStoragePermissionMessage')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(context.tr('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(context.tr('instance.goGrant')),
            ),
          ],
        ),
      );
      if (go != true) {
        _closeWizard();
        return;
      }
      await StoragePermission.request();
      if (!mounted) return;
      _doImportArchive(instanceId);
      return;
    }

    if (!mounted) return;
    final sourcePath = await pickFromSystem(context, mode: SystemPickMode.file);
    if (sourcePath == null) {
      _closeWizard();
      return;
    }

    setState(() {
      _step = _WizardStep.extractArchive;
      _extracting = true;
      _extractError = null;
      _extractProgress = null;
    });

    try {
      final dir = await _instanceController.directoryForId(instanceId);

      await ArchiveService.extractWithProgress(
        sourcePath,
        dir.path,
        onProgress: (current, total) {
          if (!mounted) return;
          setState(() {
            if (total > 0) {
              _extractProgress = current / total;
            } else {
              _extractProgress = null;
            }
          });
        },
      );

      _completed = true;
      if (mounted) {
        setState(() {
          _extracting = false;
          _extractProgress = null;
        });
        _finishWizard();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _extractProgress = null;
        _extractError = context.tr('instance.extractArchiveFailed', {'error': '$e'});
      });
    }
  }

  /// 创建空实例：不下载/导入任何 jar，直接完成向导。
  Future<void> _createEmptyInstance() async {
    if (!await _validateName()) return;
    final name = _nameController.text.trim();
    try {
      final instance = await _instanceController.createInstance(name);
      _instanceId = instance.id;
      _completed = true;
      _finishWizard();
    } on DuplicateInstanceNameException {
      if (!mounted) return;
      _showDuplicateDialog(name);
    }
  }

  // —— 整合包导入流程 ——
  // 参考 PCL-CE 的 ModModpack.ModpackInstall / InstallPackModrinth：
  // 1. 选择整合包文件 → 2. 检测格式 → 3.（Modrinth）解析清单 →
  //    4. 确认 → 5. 下载服务端 mod → 6. 解压 overrides → 7. 下载服务端 jar。
  // 普通 zip：直接解压到实例目录后完成。

  Future<void> _startModpackImport() async {
    if (!await _validateName()) return;
    final name = _nameController.text.trim();
    try {
      final instance = await _instanceController.createInstance(name);
      if (!mounted) return;
      _instanceId = instance.id;
      setState(() {
        _step = _WizardStep.modpackImport;
        _modpackPhase = '';
        _modpackError = null;
        _modpackFormat = null;
      });
      await _doModpackImport(instance.id);
    } on DuplicateInstanceNameException {
      if (!mounted) return;
      _showDuplicateDialog(name);
    }
  }

  Future<void> _doModpackImport(String instanceId) async {
    // 文件访问权限。
    if (!await StoragePermission.isGranted()) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.tr('instance.storagePermissionTitle')),
          content: Text(context.tr('instance.importStoragePermissionMessage')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(context.tr('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(context.tr('instance.goGrant')),
            ),
          ],
        ),
      );
      if (go != true) {
        _deleteCreatedInstance();
        _closeWizard();
        return;
      }
      await StoragePermission.request();
      if (!mounted) return;
      _doModpackImport(instanceId);
      return;
    }

    // 选择整合包文件。
    if (!mounted) return;
    final sourcePath = await pickFromSystem(context, mode: SystemPickMode.file);
    if (sourcePath == null) {
      _deleteCreatedInstance();
      _closeWizard();
      return;
    }

    setState(() => _modpackPhase = 'parsing');
    try {
      final format = await ModpackService.detectFormat(sourcePath);
      _modpackFormat = format;
      if (format == ModpackFormat.plainZip) {
        // 普通 zip：直接解压到实例目录后完成。
        await _extractPlainZip(instanceId, sourcePath);
        return;
      }

      // Modrinth：解析清单。
      final modpack = await ModpackService.parseModrinth(sourcePath);
      if (!mounted) return;

      // 确认对话框。
      final confirmed = await _showModpackConfirm(modpack);
      if (confirmed != true) {
        _deleteCreatedInstance();
        _closeWizard();
        return;
      }

      final dir = await _instanceController.directoryForId(instanceId);

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
      await ModpackService.extractOverrides(sourcePath, dir);

      // 下载服务端 jar。
      if (!mounted) return;
      setState(() => _modpackPhase = 'preparing');
      await _downloadServerJarFromModpack(instanceId, modpack);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modpackError = context.tr('instance.modpackFailed', {'error': '$e'});
      });
    }
  }

  /// 普通 zip 整合包：解压到实例目录后完成（与导入压缩包行为一致）。
  Future<void> _extractPlainZip(String instanceId, String sourcePath) async {
    setState(() {
      _modpackPhase = 'extracting';
      _modpackError = null;
    });
    try {
      final dir = await _instanceController.directoryForId(instanceId);
      await ArchiveService.extractWithProgress(
        sourcePath,
        dir.path,
        onProgress: (current, total) {
          if (!mounted) return;
          setState(() {
            if (total > 0) {
              _extractProgress = current / total;
            } else {
              _extractProgress = null;
            }
          });
        },
      );
      _completed = true;
      if (mounted) {
        setState(() {
          _extracting = false;
          _extractProgress = null;
        });
        _finishWizard();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modpackError = context.tr('instance.extractArchiveFailed', {
          'error': '$e',
        });
      });
    }
  }

  /// 根据整合包 dependencies 下载对应服务端 jar，复用现有下载/安装流程。
  Future<void> _downloadServerJarFromModpack(
    String instanceId,
    ModrinthModpack modpack,
  ) async {
    final deps = modpack.dependencies;
    final mcVersion = deps['minecraft'];
    if (mcVersion == null || mcVersion.isEmpty) {
      // 无 MC 版本信息，无法自动下载服务端，直接完成。
      _completed = true;
      if (mounted) _finishWizard();
      return;
    }

    final fabricLoader = deps['fabric-loader'];
    final forge = deps['forge'];
    final neoforge = deps['neo-forge'] ?? deps['neoforge'];
    final quiltLoader = deps['quilt-loader'];

    if (fabricLoader != null) {
      _serverType = 'fabric';
      _selectedMcVersion = mcVersion;
      _selectedLoaderVersion = fabricLoader;
      if (mounted) setState(() => _step = _WizardStep.downloading);
      await _fetchAndDownloadFabric(instanceId);
    } else if (forge != null) {
      _serverType = 'forge';
      _selectedForgeMcVersion = mcVersion;
      _selectedForgeVersion = forge;
      if (mounted) setState(() => _step = _WizardStep.downloading);
      await _fetchAndDownloadForge(instanceId);
    } else if (neoforge != null) {
      _serverType = 'neoforge';
      _selectedNeoforgeVersion = neoforge;
      _selectedNeoforgeMcVersion = _deriveNeoforgeMcKey(neoforge);
      if (mounted) setState(() => _step = _WizardStep.downloading);
      await _fetchAndDownloadNeoforge(instanceId);
    } else if (quiltLoader != null) {
      // Quilt 无独立服务端下载流程：Fabric 兼容，下载 Fabric 服务端。
      _serverType = 'fabric';
      _selectedMcVersion = mcVersion;
      _selectedLoaderVersion = quiltLoader;
      if (mounted) setState(() => _step = _WizardStep.downloading);
      await _fetchAndDownloadFabric(instanceId);
    } else {
      // Vanilla 服务端。
      _serverType = 'vanilla';
      _selectedVersion = mcVersion;
      if (mounted) setState(() => _step = _WizardStep.downloading);
      // 需先填充版本详情 URL 映射。
      try {
        await _fetchVanillaVersions();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _downloadError = context.tr('instance.fetchVersionsFailed', {
            'error': '$e',
          });
        });
        return;
      }
      await _fetchAndDownload(instanceId, mcVersion);
    }
  }

  /// 由 NeoForge 版本号推导 MC 版本键（与 _fetchAllNeoforgeVersions 分组规则一致）。
  /// 三段式 "21.1.234" → "21.1"；四段式 "26.1.2.71" → "26.1.2"。
  String _deriveNeoforgeMcKey(String nfVersion) {
    final parts = nfVersion.split('-').first.split('.');
    if (parts.length >= 4) return '${parts[0]}.${parts[1]}.${parts[2]}';
    if (parts.length >= 2) return '${parts[0]}.${parts[1]}';
    return nfVersion;
  }

  Future<bool?> _showModpackConfirm(ModrinthModpack modpack) {
    final mc = modpack.dependencies['minecraft'] ?? '-';
    final loader = _modpackLoaderLabel(modpack);
    final modCount = modpack.serverFiles.length;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('instance.modpackConfirmTitle')),
        content: Text(
          ctx.tr('instance.modpackSummary', {
            'name': modpack.name ?? '-',
            'mc': mc,
            'loader': loader,
            'count': '$modCount',
          }),
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
  }

  String _modpackLoaderLabel(ModrinthModpack modpack) {
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

  Future<void> _doImport(String instanceId) async {
    // 确保有文件访问权限。
    if (!await StoragePermission.isGranted()) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.tr('instance.storagePermissionTitle')),
          content: Text(context.tr('instance.importStoragePermissionMessage')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(context.tr('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(context.tr('instance.goGrant')),
            ),
          ],
        ),
      );
      if (go != true) {
        _closeWizard();
        return;
      }
      await StoragePermission.request();
      // 授权后重新尝试导入。
      if (!mounted) return;
      _doImport(instanceId);
      return;
    }

    if (!mounted) return;
    final sourcePath = await pickFromSystem(context, mode: SystemPickMode.file);
    if (sourcePath == null) {
      // 用户取消选择，关闭向导（dispose 会自动清理空实例）。
      _closeWizard();
      return;
    }
    try {
      final dir = await _instanceController.directoryForId(instanceId);
      final savedPath = await _fileService.importFile(sourcePath, dir);
      final jarName = p.basename(savedPath);
      // 导入 .phar 时自动切到 PHP（PocketMine）运行环境，其余按 Java 处理。
      final isPhar = jarName.toLowerCase().endsWith('.phar');
      await _instanceController.updateConfig(
        instanceId,
        selectedJar: jarName,
        runtime: isPhar ? kRuntimePhp : kRuntimeJava,
      );
      _completed = true;
      _finishWizard();
    } catch (_) {
      _closeWizard();
    }
  }

  Future<void> _selectVersion(String version) async {
    // 步骤 1：确认弹窗
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('instance.confirmVersionTitle')),
        content: Text(
          context.tr('instance.confirmDownload', {'version': version}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('common.ok')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // 步骤 2：创建实例并导航到下载页
    final name = _nameController.text.trim();
    try {
      final instance = await _instanceController.createInstance(name);
      if (!mounted) return;
      _instanceId = instance.id;
      _selectedVersion = version;
      setState(() => _step = _WizardStep.downloading);
      // 步骤 3：在下载页内获取下载信息并下载
      await _fetchAndDownload(instance.id, version);
    } on DuplicateInstanceNameException {
      if (!mounted) return;
      _showDuplicateDialog(name);
    }
  }

  /// Fabric 流程：选择 Minecraft 版本后进入 Loader 版本选择。
  Future<void> _selectFabricMcVersion(String mcVersion) async {
    _selectedMcVersion = mcVersion;
    setState(() {
      _step = _WizardStep.fabricLoaderVersionSelect;
      _loadingVersions = true;
      _versionError = null;
      _versions = [];
    });
    try {
      _versions = await _fetchFabricLoaderVersions(mcVersion);
      if (!mounted) return;
      setState(() => _loadingVersions = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingVersions = false;
        _versionError = context.tr('instance.fetchFabricLoaderVersionsFailed', {
          'error': '$e',
        });
      });
    }
  }

  /// Fabric 流程：选择 Loader 版本后确认并下载。
  Future<void> _selectFabricLoaderVersion(String loaderVersion) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('instance.confirmVersionTitle')),
        content: Text(
          context.tr('instance.confirmDownloadFabric', {
            'version': '$_selectedMcVersion',
            'loader': loaderVersion,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('common.ok')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final name = _nameController.text.trim();
    try {
      final instance = await _instanceController.createInstance(name);
      if (!mounted) return;
      _instanceId = instance.id;
      _selectedLoaderVersion = loaderVersion;
      setState(() => _step = _WizardStep.downloading);
      await _fetchAndDownloadFabric(instance.id);
    } on DuplicateInstanceNameException {
      if (!mounted) return;
      _showDuplicateDialog(name);
    }
  }

  /// Forge 流程：选择 MC 版本后进入 Forge 版本选择。
  Future<void> _selectForgeMcVersion(String mcVersion) async {
    _selectedForgeMcVersion = mcVersion;
    final forgeVersions = _forgeVersionMap[mcVersion] ?? [];
    setState(() {
      _step = _WizardStep.forgeVersionSelect;
      _versions = forgeVersions;
      _loadingVersions = false;
      _versionError = null;
    });
  }

  /// Forge 流程：选择 Forge 版本后确认并下载。
  Future<void> _selectForgeVersion(String forgeVersion) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('instance.confirmVersionTitle')),
        content: Text(
          context.tr('instance.confirmInstallForge', {
            'version': '$_selectedForgeMcVersion',
            'loader': forgeVersion,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('common.ok')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final name = _nameController.text.trim();
    try {
      final instance = await _instanceController.createInstance(name);
      if (!mounted) return;
      _instanceId = instance.id;
      _selectedForgeVersion = forgeVersion;
      setState(() => _step = _WizardStep.downloading);
      await _fetchAndDownloadForge(instance.id);
    } on DuplicateInstanceNameException {
      if (!mounted) return;
      _showDuplicateDialog(name);
    }
  }

  /// Forge 下载流程：下载 Installer jar，然后进入安装步骤。
  Future<void> _fetchAndDownloadForge(String instanceId) async {
    setState(() {
      _downloadProgress = null;
      _downloadError = null;
    });

    final mcVersion = _selectedForgeMcVersion!;
    final forgeVersion = _selectedForgeVersion!;
    // 镜像开启时按所选 MC 版本走 MSL（installer），失败回退官方 Maven。
    final info =
        await _tryMirrorDownloadInfo('forge', mcVersion) ??
        _DownloadInfo(
          url:
              'https://maven.minecraftforge.net/net/minecraftforge/forge/$mcVersion-$forgeVersion/forge-$mcVersion-$forgeVersion-installer.jar',
        );

    await _downloadForgeJar(instanceId, info);
  }

  /// 下载 Forge Installer jar 到实例目录，完成后启动安装。
  Future<void> _downloadForgeJar(String instanceId, _DownloadInfo info) async {
    setState(() {
      _downloadProgress = null;
      _downloadError = null;
    });

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(info.url));
      final response = await request.close();

      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(
          () => _downloadError = context.tr('instance.downloadFailedHttp', {
            'status': '${response.statusCode}',
          }),
        );
        return;
      }

      final dir = await _instanceController.directoryForId(instanceId);
      final file = File(p.join(dir.path, 'forge-installer.jar'));

      final contentLength = response.contentLength;
      int received = 0;

      final sink = file.openWrite();
      final allBytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        received += chunk.length;
        allBytes.add(chunk);
        if (contentLength > 0 && mounted) {
          setState(() => _downloadProgress = received / contentLength);
        }
        sink.add(chunk);
      }
      await sink.close();

      // 下载完成，进入安装步骤。
      if (!mounted) return;
      await _runForgeInstaller(instanceId, file.path);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _downloadError = context.tr('instance.downloadFailed', {
          'error': '$e',
        }),
      );
    } finally {
      client.close();
    }
  }

  /// 调用原生平台运行 Forge Installer，安装完成后配置实例。
  Future<void> _runForgeInstaller(
    String instanceId,
    String installerPath,
  ) async {
    _installerType = 'forge';
    setState(() {
      _step = _WizardStep.forgeInstalling;
      _forgeInstalling = true;
      _forgeInstallError = null;
      _forgeInstallLogs.clear();
    });

    // 监听安装器日志。
    _forgeEventSub = _forgeEventChannel.receiveBroadcastStream().listen((
      event,
    ) {
      if (mounted && event is String) {
        setState(() {
          _forgeInstallLogs.add(event);
          // 保留最近 200 行。
          if (_forgeInstallLogs.length > 200) {
            _forgeInstallLogs.removeRange(0, _forgeInstallLogs.length - 200);
          }
        });
      }
    });

    try {
      final mcVersion = _selectedForgeMcVersion!;
      final javaVer = await _resolveJavaVersion(mcVersion);

      final exitCode = await _forgeChannel.invokeMethod<int>('runInstaller', {
        'installerJar': installerPath,
        'workingDir': (await _instanceController.directoryForId(
          instanceId,
        )).path,
        'javaVersion': javaVer,
      });

      await _forgeEventSub?.cancel();
      _forgeEventSub = null;

      if (exitCode != 0) {
        if (!mounted) return;
        setState(() {
          _forgeInstalling = false;
          _forgeInstallError = context.tr('instance.forgeInstallerExited', {
            'code': '$exitCode',
          });
        });
        return;
      }

      // 安装成功：扫描目录找到 forge 服务端 jar。
      final dir = await _instanceController.directoryForId(instanceId);
      final forgeJar = _findForgeServerJar(dir);
      if (forgeJar == null) {
        if (!mounted) return;
        setState(() {
          _forgeInstalling = false;
          _forgeInstallError = context.tr('instance.serverJarNotFound');
        });
        return;
      }

      await _instanceController.updateConfig(
        instanceId,
        selectedJar: forgeJar,
        javaVersion: javaVer,
      );

      // 清理 installer jar。
      try {
        await File(p.join(dir.path, 'forge-installer.jar')).delete();
      } catch (_) {}

      _completed = true;
      if (mounted) {
        setState(() => _forgeInstalling = false);
        _finishWizard();
      }
    } catch (e) {
      await _forgeEventSub?.cancel();
      _forgeEventSub = null;
      if (!mounted) return;
      setState(() {
        _forgeInstalling = false;
        _forgeInstallError = context.tr('instance.forgeInstallFailed', {
          'error': '$e',
        });
      });
    }
  }

  /// 在实例目录中查找 Forge/NeoForge 安装后生成的服务端 jar。
  String? _findForgeServerJar(Directory dir, {String prefix = 'forge-'}) {
    final files = dir.listSync();
    String? forgeJar;
    for (final f in files) {
      if (f is! File) continue;
      final name = p.basename(f.path);
      // 跳过 installer、不相关的 jar。
      if (name == 'forge-installer.jar') continue;
      if (name == 'server.jar') continue;
      if (name.startsWith(prefix) && name.endsWith('.jar')) {
        forgeJar = name;
      }
    }
    return forgeJar;
  }

  /// NeoForge 流程：选择 MC 版本后进入 NeoForge 版本选择。
  Future<void> _selectNeoforgeMcVersion(String mcVersion) async {
    _selectedNeoforgeMcVersion = mcVersion;
    final neoforgeVersions = _neoforgeVersionMap[mcVersion] ?? [];
    setState(() {
      _step = _WizardStep.neoforgeVersionSelect;
      _versions = neoforgeVersions;
      _loadingVersions = false;
      _versionError = null;
    });
  }

  /// NeoForge 流程：选择 NeoForge 版本后确认并下载。
  Future<void> _selectNeoforgeVersion(String neoforgeVersion) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('instance.confirmVersionTitle')),
        content: Text(
          context.tr('instance.confirmInstallNeoforge', {
            'version': '$_selectedNeoforgeMcVersion',
            'loader': neoforgeVersion,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('common.ok')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final name = _nameController.text.trim();
    try {
      final instance = await _instanceController.createInstance(name);
      if (!mounted) return;
      _instanceId = instance.id;
      _selectedNeoforgeVersion = neoforgeVersion;
      setState(() => _step = _WizardStep.downloading);
      await _fetchAndDownloadNeoforge(instance.id);
    } on DuplicateInstanceNameException {
      if (!mounted) return;
      _showDuplicateDialog(name);
    }
  }

  /// NeoForge 下载流程：下载 Installer jar，然后进入安装步骤。
  Future<void> _fetchAndDownloadNeoforge(String instanceId) async {
    setState(() {
      _downloadProgress = null;
      _downloadError = null;
    });

    final neoforgeVersion = _selectedNeoforgeVersion!;
    // 镜像开启时按所选 MC 版本走 MSL（installer），失败回退官方 Maven。
    final mslVersion = _neoforgeMcToMslVersion(_selectedNeoforgeMcVersion!);
    final info =
        await _tryMirrorDownloadInfo('neoforge', mslVersion) ??
        _DownloadInfo(
          url:
              'https://maven.neoforged.net/releases/net/neoforged/neoforge/$neoforgeVersion/neoforge-$neoforgeVersion-installer.jar',
        );

    await _downloadNeoforgeJar(instanceId, info);
  }

  /// 下载 NeoForge Installer jar 到实例目录，完成后启动安装。
  Future<void> _downloadNeoforgeJar(
    String instanceId,
    _DownloadInfo info,
  ) async {
    setState(() {
      _downloadProgress = null;
      _downloadError = null;
    });

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(info.url));
      final response = await request.close();

      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(
          () => _downloadError = context.tr('instance.downloadFailedHttp', {
            'status': '${response.statusCode}',
          }),
        );
        return;
      }

      final dir = await _instanceController.directoryForId(instanceId);
      final file = File(p.join(dir.path, 'neoforge-installer.jar'));

      final contentLength = response.contentLength;
      int received = 0;

      final sink = file.openWrite();
      final allBytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        received += chunk.length;
        allBytes.add(chunk);
        if (contentLength > 0 && mounted) {
          setState(() => _downloadProgress = received / contentLength);
        }
        sink.add(chunk);
      }
      await sink.close();

      // 下载完成，进入安装步骤。
      if (!mounted) return;
      await _runNeoforgeInstaller(instanceId, file.path);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _downloadError = context.tr('instance.downloadFailed', {
          'error': '$e',
        }),
      );
    } finally {
      client.close();
    }
  }

  /// 调用原生平台运行 NeoForge Installer，安装完成后配置实例。
  Future<void> _runNeoforgeInstaller(
    String instanceId,
    String installerPath,
  ) async {
    _installerType = 'neoforge';
    setState(() {
      _step = _WizardStep.forgeInstalling;
      _forgeInstalling = true;
      _forgeInstallError = null;
      _forgeInstallLogs.clear();
    });

    // 监听安装器日志。
    _forgeEventSub = _forgeEventChannel.receiveBroadcastStream().listen((
      event,
    ) {
      if (mounted && event is String) {
        setState(() {
          _forgeInstallLogs.add(event);
          // 保留最近 200 行。
          if (_forgeInstallLogs.length > 200) {
            _forgeInstallLogs.removeRange(0, _forgeInstallLogs.length - 200);
          }
        });
      }
    });

    try {
      final mcVersion = _selectedNeoforgeMcVersion!;
      // NeoForge MC 版本格式为 "major.minor.patch"（如 21.1.0），
      // 转换为 Minecraft 版本格式 "1.major.minor"（如 1.21.1）以供 Java 版本推断。
      // MC 26+（年份命名）直接使用 _javaVersionForMc 的原生逻辑。
      final nfParts = mcVersion.split('.');
      final nfMajor = int.tryParse(nfParts[0]) ?? 1;
      final String mcVerForJava;
      if (nfMajor >= 26) {
        mcVerForJava = mcVersion; // 26.1.2 → 直接传入，major≥26 走 jre25 分支
      } else {
        mcVerForJava = nfParts.length >= 2
            ? '1.${nfParts[0]}.${nfParts[1]}'
            : mcVersion;
      }
      final javaVer = await _resolveJavaVersion(mcVerForJava);

      final exitCode = await _forgeChannel.invokeMethod<int>('runInstaller', {
        'installerJar': installerPath,
        'workingDir': (await _instanceController.directoryForId(
          instanceId,
        )).path,
        'javaVersion': javaVer,
      });

      await _forgeEventSub?.cancel();
      _forgeEventSub = null;

      if (exitCode != 0) {
        if (!mounted) return;
        setState(() {
          _forgeInstalling = false;
          _forgeInstallError = context.tr('instance.neoforgeInstallerExited', {
            'code': '$exitCode',
          });
        });
        return;
      }

      // 安装成功：扫描目录找到 neoforge 服务端 jar。
      final dir = await _instanceController.directoryForId(instanceId);
      final neoforgeJar = _findForgeServerJar(dir, prefix: 'neoforge-');
      if (neoforgeJar == null) {
        if (!mounted) return;
        setState(() {
          _forgeInstalling = false;
          _forgeInstallError = context.tr('instance.serverJarNotFound');
        });
        return;
      }

      await _instanceController.updateConfig(
        instanceId,
        selectedJar: neoforgeJar,
        javaVersion: javaVer,
      );

      // 清理 installer jar。
      try {
        await File(p.join(dir.path, 'neoforge-installer.jar')).delete();
      } catch (_) {}

      _completed = true;
      if (mounted) {
        setState(() => _forgeInstalling = false);
        _finishWizard();
      }
    } catch (e) {
      await _forgeEventSub?.cancel();
      _forgeEventSub = null;
      if (!mounted) return;
      setState(() {
        _forgeInstalling = false;
        _forgeInstallError = context.tr('instance.neoforgeInstallFailed', {
          'error': '$e',
        });
      });
    }
  }

  /// 在下载页中先获取下载信息，再执行下载（Vanilla / Paper）。
  Future<void> _fetchAndDownload(String instanceId, String version) async {
    setState(() {
      _downloadProgress = null;
      _downloadError = null;
    });

    _DownloadInfo info;
    try {
      // 镜像开启时优先走 MSL，失败回退官方源。
      info =
          await _tryMirrorDownloadInfo(_serverType!, version) ??
          await _fetchDownloadInfo(version);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _downloadError = context.tr('instance.fetchDownloadInfoFailed', {
          'error': '$e',
        }),
      );
      return;
    }

    final jarName =
        _serverType == 'powernukkitx' ? 'powernukkitx.jar' : 'server.jar';
    await _downloadJar(instanceId, info, jarName: jarName);
  }

  /// Fabric 下载流程：获取最新 Installer 版本并构造下载 URL。
  Future<void> _fetchAndDownloadFabric(String instanceId) async {
    setState(() {
      _downloadProgress = null;
      _downloadError = null;
    });

    _DownloadInfo info;
    try {
      // 镜像开启时按所选 MC 版本走 MSL，失败回退官方源。
      info =
          await _tryMirrorDownloadInfo('fabric', _selectedMcVersion!) ??
          await _fetchFabricDownloadInfo();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _downloadError = context.tr('instance.fetchDownloadInfoFailed', {
          'error': '$e',
        }),
      );
      return;
    }

    await _downloadJar(instanceId, info);
  }

  Future<void> _downloadJar(
    String instanceId,
    _DownloadInfo info, {
    String jarName = 'server.jar',
  }) async {
    setState(() {
      _downloadProgress = null;
      _downloadError = null;
    });

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(info.url));
      final response = await request.close();

      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(
          () => _downloadError = context.tr('instance.downloadFailedHttp', {
            'status': '${response.statusCode}',
          }),
        );
        return;
      }

      final dir = await _instanceController.directoryForId(instanceId);
      final file = File(p.join(dir.path, jarName));

      final contentLength = response.contentLength;
      int received = 0;

      // 流式下载并记录所有字节用于哈希校验。
      final sink = file.openWrite();
      final allBytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        received += chunk.length;
        allBytes.add(chunk);
        if (contentLength > 0 && mounted) {
          setState(() => _downloadProgress = received / contentLength);
        }
        sink.add(chunk);
      }
      await sink.close();

      // 校验哈希。
      final hashOk = _verifyHash(allBytes.toBytes(), info);
      if (!hashOk) {
        await file.delete();
        if (!mounted) return;
        setState(
          () => _downloadError = context.tr('instance.hashVerifyFailed'),
        );
        return;
      }

      final String javaVer;
      if (_serverType == 'powernukkitx') {
        javaVer = await _resolveJavaVersion('1.20.5');
      } else {
        final mcVersion = _serverType == 'fabric'
            ? (_selectedMcVersion ?? '')
            : (_serverType == 'velocity' ? '1.21' : (_selectedVersion ?? ''));
        javaVer = await _resolveJavaVersion(mcVersion);
      }
      await _instanceController.updateConfig(
        instanceId,
        selectedJar: jarName,
        javaVersion: javaVer,
      );

      _completed = true;
      if (mounted) _finishWizard();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _downloadError = context.tr('instance.downloadFailed', {
          'error': '$e',
        }),
      );
    } finally {
      client.close();
    }
  }

  /// 根据 MC 版本号推断所需的 Java 版本（已移除 jre8）。
  ///
  /// MC 26+（年份命名）          → jre25
  /// MC 1.20.5 - 1.21.11（含边界） → jre21
  /// MC ≤1.20.4                  → jre17
  static String _javaVersionForMc(String mcVersion) {
    final parts = mcVersion.split('.');
    if (parts.isEmpty) return 'jre17';
    final major = int.tryParse(parts[0]) ?? 1;
    // Mojang 新版本采用年份开头（如 26 = 2026 年），统一使用 jre25。
    if (major >= 26) return 'jre25';
    if (major == 1) {
      final minor = parts.length >= 2 ? (int.tryParse(parts[1]) ?? 0) : 0;
      final patch = parts.length >= 3 ? (int.tryParse(parts[2]) ?? 0) : 0;
      // 1.20.5 ≤ version ≤ 1.21.11 → jre21
      if (minor > 21) return 'jre21';
      if (minor == 21 && patch <= 11) return 'jre21';
      if (minor == 20 && patch >= 5) return 'jre21';
      return 'jre17';
    }
    return 'jre17';
  }

  /// 根据 MC 版本推断首选 Java 版本；若该版本未安装，回退到首个已安装 JRE。
  static Future<String> _resolveJavaVersion(String mcVersion) async {
    final preferred = _javaVersionForMc(mcVersion);
    final available = await ServerService().availableJreIds();
    if (available.contains(preferred)) return preferred;
    if (available.isEmpty) return preferred;
    return available.first;
  }

  /// 根据下载信息校验文件哈希（Vanilla 用 SHA-1，Paper 用 SHA-256）。
  bool _verifyHash(Uint8List bytes, _DownloadInfo info) {
    if (info.sha1 != null) {
      final digest = sha1.convert(bytes).toString();
      return digest == info.sha1;
    } else if (info.sha256 != null) {
      final digest = sha256.convert(bytes).toString();
      return digest == info.sha256;
    }
    return true; // 无校验信息时视为通过。
  }

  void _onBack() {
    switch (_step) {
      case _WizardStep.nameEntry:
        _closeWizard();
      case _WizardStep.serverType:
        setState(() => _step = _WizardStep.nameEntry);
      case _WizardStep.versionSelect:
        setState(() => _step = _WizardStep.serverType);
      case _WizardStep.fabricMcVersionSelect:
        setState(() {
          _step = _WizardStep.serverType;
          _selectedMcVersion = null;
        });
      case _WizardStep.fabricLoaderVersionSelect:
        setState(() {
          _step = _WizardStep.fabricMcVersionSelect;
          _versions = _fabricMcVersions;
          _versionError = null;
          _loadingVersions = false;
          _selectedLoaderVersion = null;
        });
      case _WizardStep.forgeMcVersionSelect:
        setState(() {
          _step = _WizardStep.serverType;
          _selectedForgeMcVersion = null;
        });
      case _WizardStep.forgeVersionSelect:
        setState(() {
          _step = _WizardStep.forgeMcVersionSelect;
          _versions = _forgeVersionMap.keys.toList();
          _versionError = null;
          _loadingVersions = false;
          _selectedForgeVersion = null;
        });
      case _WizardStep.neoforgeMcVersionSelect:
        setState(() {
          _step = _WizardStep.serverType;
          _selectedNeoforgeMcVersion = null;
        });
      case _WizardStep.neoforgeVersionSelect:
        setState(() {
          _step = _WizardStep.neoforgeMcVersionSelect;
          _versions = _neoforgeVersionMap.keys.toList();
          _versionError = null;
          _loadingVersions = false;
          _selectedNeoforgeVersion = null;
        });
      case _WizardStep.importFile:
        _deleteCreatedInstance();
        _closeWizard();
      case _WizardStep.importArchive:
        _deleteCreatedInstance();
        _closeWizard();
      case _WizardStep.extractArchive:
        break;
      case _WizardStep.downloading:
        _deleteCreatedInstance();
        _closeWizard();
      case _WizardStep.forgeInstalling:
        // 安装进行中，不允许返回（已创建实例）。
        break;
      case _WizardStep.modpackImport:
        _deleteCreatedInstance();
        _closeWizard();
    }
  }

  void _closeWizard() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(CreateInstanceResult.cancelled);
    }
  }

  void _finishWizard() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(CreateInstanceResult.done);
    }
  }

  void _deleteCreatedInstance() {
    if (_instanceId != null) {
      _instanceController.deleteInstance(_instanceId!);
      _instanceId = null;
    }
  }

  Future<void> _showDuplicateDialog(String name) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('instance.noticeTitle')),
        content: Text(context.tr('instance.duplicateName', {'name': name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.tr('common.ok')),
          ),
        ],
      ),
    );
  }

  // —— UI 构建 ——

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _onBack,
          ),
          title: Text(_appBarTitle),
        ),
        body: SafeArea(child: _buildStepContent(theme)),
      ),
    );
  }

  String get _appBarTitle {
    return switch (_step) {
      _WizardStep.nameEntry => context.tr('instance.titleNameEntry'),
      _WizardStep.serverType => context.tr('instance.titleDownloadServer'),
      _WizardStep.versionSelect => context.tr('instance.titleSelectVersion'),
      _WizardStep.fabricMcVersionSelect => context.tr(
        'instance.titleSelectMcVersion',
      ),
      _WizardStep.fabricLoaderVersionSelect => context.tr(
        'instance.titleSelectFabricLoaderVersion',
      ),
      _WizardStep.forgeMcVersionSelect => context.tr(
        'instance.titleSelectMcVersion',
      ),
      _WizardStep.forgeVersionSelect => context.tr(
        'instance.titleSelectForgeVersion',
      ),
      _WizardStep.neoforgeMcVersionSelect => context.tr(
        'instance.titleSelectMcVersion',
      ),
      _WizardStep.neoforgeVersionSelect => context.tr(
        'instance.titleSelectNeoforgeVersion',
      ),
      _WizardStep.downloading => context.tr('instance.titleDownloading'),
      _WizardStep.forgeInstalling =>
        _installerType == 'neoforge'
            ? context.tr('instance.titleInstallNeoforge')
            : context.tr('instance.titleInstallForge'),
      _WizardStep.importFile => context.tr('instance.titleImportServer'),
      _WizardStep.importArchive => context.tr('instance.titleImportServer'),
      _WizardStep.extractArchive => context.tr('instance.titleImportArchive'),
      _WizardStep.modpackImport => context.tr('instance.titleModpackImport'),
    };
  }

  Widget _buildStepContent(ThemeData theme) {
    return switch (_step) {
      _WizardStep.nameEntry => _buildNameEntry(theme),
      _WizardStep.serverType => _buildServerTypeSelect(theme),
      _WizardStep.versionSelect => _buildVersionSelect(theme),
      _WizardStep.fabricMcVersionSelect => _buildVersionSelect(theme),
      _WizardStep.fabricLoaderVersionSelect => _buildVersionSelect(theme),
      _WizardStep.forgeMcVersionSelect => _buildVersionSelect(theme),
      _WizardStep.forgeVersionSelect => _buildVersionSelect(theme),
      _WizardStep.neoforgeMcVersionSelect => _buildVersionSelect(theme),
      _WizardStep.neoforgeVersionSelect => _buildVersionSelect(theme),
      _WizardStep.downloading => _buildDownloading(theme),
      _WizardStep.forgeInstalling => _buildForgeInstalling(theme),
      _WizardStep.importFile => _buildImporting(theme),
      _WizardStep.importArchive => _buildImporting(theme),
      _WizardStep.extractArchive => _buildExtractingArchive(theme),
      _WizardStep.modpackImport => _buildModpackImport(theme),
    };
  }

  /// 步骤 1：名称输入 + 两个大选项卡。
  Widget _buildNameEntry(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: context.tr('instance.nameLabel'),
              hintText: context.tr('instance.nameHint'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          _ServerTypeTile(
            icon: Icons.cloud_download_outlined,
            title: context.tr('instance.titleDownloadServer'),
            subtitle: context.tr('instance.downloadServerSubtitle'),
            onTap: _goToServerType,
          ),
          const SizedBox(height: 12),
          _ServerTypeTile(
            icon: Icons.file_upload_outlined,
            title: context.tr('instance.titleImportServer'),
            subtitle: context.tr('instance.importServerSubtitle'),
            onTap: _startImport,
          ),
          const SizedBox(height: 12),
          _ServerTypeTile(
            icon: Icons.archive_outlined,
            title: context.tr('instance.titleImportArchive'),
            subtitle: context.tr('instance.importArchiveSubtitle'),
            onTap: _startImportArchive,
          ),
          const SizedBox(height: 12),
          _ServerTypeTile(
            icon: Icons.inventory_2_outlined,
            title: context.tr('instance.titleModpackImport'),
            subtitle: context.tr('instance.modpackImportSubtitle'),
            onTap: _startModpackImport,
          ),
          const SizedBox(height: 12),
          _ServerTypeTile(
            icon: Icons.create_new_folder_outlined,
            title: context.tr('instance.createEmptyTitle'),
            subtitle: context.tr('instance.createEmptySubtitle'),
            onTap: _createEmptyInstance,
          ),
        ],
      ),
    );
  }

  /// 步骤 2a：服务端类型选择（官方端 / Paper 端 / Fabric 端）。
  Widget _buildServerTypeSelect(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        _ServerTypeTile(
          icon: Icons.storage_outlined,
          title: context.tr('instance.vanillaTitle'),
          subtitle: context.tr('instance.vanillaSubtitle'),
          onTap: () => _selectServerType('vanilla'),
        ),
        const SizedBox(height: 12),
        _ServerTypeTile(
          icon: Icons.article_outlined,
          title: context.tr('instance.paperTitle'),
          subtitle: context.tr('instance.paperSubtitle'),
          onTap: () => _selectServerType('paper'),
        ),
        const SizedBox(height: 12),
        _ServerTypeTile(
          icon: Icons.speed_outlined,
          title: context.tr('instance.velocityTitle'),
          subtitle: context.tr('instance.velocitySubtitle'),
          onTap: () => _selectServerType('velocity'),
        ),
        const SizedBox(height: 12),
        _ServerTypeTile(
          icon: Icons.layers_outlined,
          title: context.tr('instance.fabricTitle'),
          subtitle: context.tr('instance.fabricSubtitle'),
          onTap: () => _selectServerType('fabric'),
        ),
        const SizedBox(height: 12),
        _ServerTypeTile(
          icon: Icons.build_outlined,
          title: context.tr('instance.forgeTitle'),
          subtitle: context.tr('instance.forgeSubtitle'),
          onTap: () => _selectServerType('forge'),
        ),
        const SizedBox(height: 12),
        _ServerTypeTile(
          icon: Icons.extension_outlined,
          title: context.tr('instance.neoforgeTitle'),
          subtitle: context.tr('instance.neoforgeSubtitle'),
          onTap: () => _selectServerType('neoforge'),
        ),
        const SizedBox(height: 12),
        _ServerTypeTile(
          icon: Icons.phone_android_outlined,
          title: context.tr('instance.powernukkitxTitle'),
          subtitle: context.tr('instance.powernukkitxSubtitle'),
          onTap: () => _selectServerType('powernukkitx'),
        ),
      ],
    );
  }

  /// 步骤 3a/3b/4b：版本列表选择（Vanilla、Paper、Fabric MC、Fabric Loader）。
  Widget _buildVersionSelect(ThemeData theme) {
    if (_loadingVersions) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_versionError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _versionError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (_step == _WizardStep.fabricMcVersionSelect) {
                    _selectServerType('fabric');
                  } else if (_step == _WizardStep.fabricLoaderVersionSelect) {
                    if (_selectedMcVersion != null) {
                      _selectFabricMcVersion(_selectedMcVersion!);
                    }
                  } else if (_step == _WizardStep.forgeMcVersionSelect) {
                    _selectServerType('forge');
                  } else if (_step == _WizardStep.forgeVersionSelect) {
                    if (_selectedForgeMcVersion != null) {
                      _selectForgeMcVersion(_selectedForgeMcVersion!);
                    }
                  } else if (_step == _WizardStep.neoforgeMcVersionSelect) {
                    _selectServerType('neoforge');
                  } else if (_step == _WizardStep.neoforgeVersionSelect) {
                    if (_selectedNeoforgeMcVersion != null) {
                      _selectNeoforgeMcVersion(_selectedNeoforgeMcVersion!);
                    }
                  } else {
                    _selectServerType(_serverType!);
                  }
                },
                child: Text(context.tr('common.retry')),
              ),
            ],
          ),
        ),
      );
    }
    if (_versions.isEmpty) {
      return Center(child: Text(context.tr('instance.noVersionsAvailable')));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _versions.length,
      itemBuilder: (_, i) {
        final v = _versions[i];
        return ListTile(
          title: Text(v),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            switch (_step) {
              case _WizardStep.versionSelect:
                _selectVersion(v);
              case _WizardStep.fabricMcVersionSelect:
                _selectFabricMcVersion(v);
              case _WizardStep.fabricLoaderVersionSelect:
                _selectFabricLoaderVersion(v);
              case _WizardStep.forgeMcVersionSelect:
                _selectForgeMcVersion(v);
              case _WizardStep.forgeVersionSelect:
                _selectForgeVersion(v);
              case _WizardStep.neoforgeMcVersionSelect:
                _selectNeoforgeMcVersion(v);
              case _WizardStep.neoforgeVersionSelect:
                _selectNeoforgeVersion(v);
              default:
                break;
            }
          },
        );
      },
    );
  }

  /// 步骤 4a：下载进度页。
  Widget _buildDownloading(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(value: _downloadProgress),
                ),
                const SizedBox(height: 24),
                Text(
                  _downloadProgress != null
                      ? context.tr('instance.downloadingServer')
                      : context.tr('instance.preparingDownload'),
                  style: theme.textTheme.titleMedium,
                ),
                if (_downloadProgress != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${(_downloadProgress! * 100).toStringAsFixed(1)}%',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
                if (_downloadError != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _downloadError!,
                    style: TextStyle(color: theme.colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          _deleteCreatedInstance();
                          _closeWizard();
                        },
                        child: Text(context.tr('common.cancel')),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () {
                          _deleteCreatedInstance();
                          setState(() {
                            if (_serverType == 'fabric') {
                              _step = _selectedLoaderVersion != null
                                  ? _WizardStep.fabricLoaderVersionSelect
                                  : _WizardStep.fabricMcVersionSelect;
                            } else if (_serverType == 'forge') {
                              _step = _selectedForgeVersion != null
                                  ? _WizardStep.forgeVersionSelect
                                  : _WizardStep.forgeMcVersionSelect;
                            } else if (_serverType == 'neoforge') {
                              _step = _selectedNeoforgeVersion != null
                                  ? _WizardStep.neoforgeVersionSelect
                                  : _WizardStep.neoforgeMcVersionSelect;
                            } else {
                              _step = _WizardStep.versionSelect;
                            }
                          });
                        },
                        child: Text(context.tr('instance.reselect')),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () {
                      _deleteCreatedInstance();
                      _closeWizard();
                    },
                    child: Text(context.tr('common.cancel')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 步骤 2b：导入中提示。
  Widget _buildImporting(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            context.tr('instance.selectJarPrompt'),
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildExtractingArchive(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_extracting)
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(value: _extractProgress),
                  )
                else if (_extractError == null)
                  Icon(
                    Icons.check_circle_outline,
                    size: 48,
                    color: theme.colorScheme.primary,
                  )
                else
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                const SizedBox(height: 24),
                Text(
                  _extracting
                      ? context.tr('instance.extractingArchive')
                      : (_extractError != null
                            ? context.tr('instance.extractArchiveFailed', {'error': _extractError!})
                            : context.tr('instance.installComplete')),
                  style: theme.textTheme.titleMedium,
                ),
                if (_extracting && _extractProgress != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${(_extractProgress! * 100).toStringAsFixed(1)}%',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
                if (_extractError != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          _deleteCreatedInstance();
                          _closeWizard();
                        },
                        child: Text(context.tr('common.cancel')),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () {
                          _deleteCreatedInstance();
                          setState(() => _step = _WizardStep.nameEntry);
                        },
                        child: Text(context.tr('instance.reselect')),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 整合包导入进度页。
  Widget _buildModpackImport(ThemeData theme) {
    final hasError = _modpackError != null;
    final isDownloading = _modpackPhase == 'downloading';
    final isExtracting = _modpackPhase == 'extracting';
    final isPreparing = _modpackPhase == 'preparing';

    double? progress;
    String phaseText;
    if (isDownloading) {
      progress = _modpackTotal > 0 ? _modpackCurrent / _modpackTotal : null;
      phaseText = context.tr('instance.modpackDownloadingMods', {
        'current': '$_modpackCurrent',
        'total': '$_modpackTotal',
      });
    } else if (isExtracting && _modpackFormat == ModpackFormat.plainZip) {
      progress = _extractProgress;
      phaseText = context.tr('instance.extractingArchive');
    } else if (isExtracting) {
      phaseText = context.tr('instance.modpackExtracting');
    } else if (isPreparing) {
      phaseText = context.tr('instance.modpackPreparing');
    } else {
      phaseText = context.tr('instance.modpackParsing');
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasError)
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.error,
                  )
                else
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(value: progress),
                  ),
                const SizedBox(height: 24),
                Text(
                  hasError ? _modpackError! : phaseText,
                  style: hasError
                      ? TextStyle(color: theme.colorScheme.error)
                      : theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (!hasError && isDownloading) ...[
                  const SizedBox(height: 8),
                  if (_modpackTotal > 0)
                    Text(
                      '${(progress! * 100).toStringAsFixed(1)}%',
                      style: theme.textTheme.bodyLarge,
                    ),
                  if (_modpackCurrentFile.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _modpackCurrentFile,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
                if (!hasError && isExtracting &&
                    _modpackFormat == ModpackFormat.plainZip &&
                    _extractProgress != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${(_extractProgress! * 100).toStringAsFixed(1)}%',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
                const SizedBox(height: 16),
                if (hasError)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          _deleteCreatedInstance();
                          _closeWizard();
                        },
                        child: Text(context.tr('common.cancel')),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () {
                          _deleteCreatedInstance();
                          setState(() => _step = _WizardStep.nameEntry);
                        },
                        child: Text(context.tr('instance.reselect')),
                      ),
                    ],
                  )
                else
                  OutlinedButton(
                    onPressed: () {
                      _deleteCreatedInstance();
                      _closeWizard();
                    },
                    child: Text(context.tr('common.cancel')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Forge 安装进度页：显示安装器日志输出。
  Widget _buildForgeInstalling(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_forgeInstalling)
                    const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(),
                    )
                  else if (_forgeInstallError == null)
                    Icon(
                      Icons.check_circle_outline,
                      size: 36,
                      color: theme.colorScheme.primary,
                    )
                  else
                    Icon(
                      Icons.error_outline,
                      size: 36,
                      color: theme.colorScheme.error,
                    ),
                  const SizedBox(height: 12),
                  Text(
                    _forgeInstalling
                        ? (_installerType == 'neoforge'
                              ? context.tr('instance.installingNeoforge')
                              : context.tr('instance.installingForge'))
                        : (_forgeInstallError != null
                              ? context.tr('instance.installFailed')
                              : context.tr('instance.installComplete')),
                    style: theme.textTheme.titleMedium,
                  ),
                  if (_forgeInstallError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _forgeInstallError!,
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.save_outlined, size: 18),
                          onPressed: _exportForgeLogs,
                          label: Text(context.tr('instance.exportForgeLog')),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            _deleteCreatedInstance();
                            _closeWizard();
                          },
                          child: Text(context.tr('common.cancel')),
                        ),
                        FilledButton(
                          onPressed: () {
                            _deleteCreatedInstance();
                            setState(
                              () => _step = _installerType == 'neoforge'
                                  ? _WizardStep.neoforgeVersionSelect
                                  : _WizardStep.forgeVersionSelect,
                            );
                          },
                          child: Text(context.tr('instance.reselect')),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: _forgeInstallLogs.isEmpty
                    ? Center(
                        child: Text(
                          context.tr('instance.waitingInstallerOutput'),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _forgeInstallLogs.length,
                        itemBuilder: (_, i) => Text(
                          _forgeInstallLogs[i],
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 导出 Forge 安装日志到用户选择的外部目录。
  Future<void> _exportForgeLogs() async {
    if (_forgeInstallLogs.isEmpty) return;
    if (!await StoragePermission.isGranted()) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('instance.storagePermissionTitle')),
          content: Text(ctx.tr('instance.exportLogPermissionMessage')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ctx.tr('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(ctx.tr('instance.goGrant')),
            ),
          ],
        ),
      );
      if (go != true) return;
      await StoragePermission.request();
      // 授权后重新尝试导出。
      _exportForgeLogs();
      return;
    }

    if (!mounted) return;
    final destDir = await pickFromSystem(
      context,
      mode: SystemPickMode.directory,
    );
    if (destDir == null) return;

    try {
      final now = DateTime.now();
      final ts =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final fileName =
          '${_installerType == 'neoforge' ? 'neoforge' : 'forge'}_install_log_$ts.txt';
      final content = _forgeInstallLogs.join('\n');
      final file = File(p.join(destDir, fileName));
      await file.writeAsString(content, flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('instance.logExportedTo', {
              'path': '$destDir/$fileName',
            }),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('instance.logExportFailed', {'error': '$e'}),
          ),
        ),
      );
    }
  }

  // —— 网络请求 ——

  Future<List<String>> _fetchVersions(String type) async {
    if (type == 'vanilla') {
      return _fetchVanillaVersions();
    } else if (type == 'paper') {
      return _fetchPaperVersions();
    } else if (type == 'powernukkitx') {
      return _fetchPowernukkitxVersions();
    } else {
      return _fetchVelocityVersions();
    }
  }

  /// 获取 Fabric 支持的 Minecraft 版本列表（仅稳定版）。
  Future<List<String>> _fetchFabricMcVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('https://meta.fabricmc.net/v2/versions/game'),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as List<dynamic>;
      return json
          .where((v) => v['stable'] == true)
          .map<String>((v) => v['version'] as String)
          .toList();
    } finally {
      client.close();
    }
  }

  /// 获取指定 Minecraft 版本的 Fabric Loader 版本列表。
  Future<List<String>> _fetchFabricLoaderVersions(String mcVersion) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('https://meta.fabricmc.net/v2/versions/loader/$mcVersion'),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as List<dynamic>;
      return json
          .map<String>(
            (v) => (v['loader'] as Map<String, dynamic>)['version'] as String,
          )
          .toList();
    } finally {
      client.close();
    }
  }

  /// 解析 Forge Maven 元数据 XML，返回 {mcVersion: [forgeVersion...]}。
  /// 版本格式为 "{mcVersion}-{forgeVersion}"，按最后一个 "-" 分割。
  Future<Map<String, List<String>>> _fetchAllForgeVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml',
        ),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();

      // 解析 XML 中的 <version> 标签。
      final versionPattern = RegExp(r'<version>([^<]+)</version>');
      final matches = versionPattern.allMatches(body);

      // 按 MC 版本分组。
      final map = <String, List<String>>{};
      for (final m in matches) {
        final full = m.group(1)!;
        final lastDash = full.lastIndexOf('-');
        if (lastDash < 0) continue;
        final mcVersion = full.substring(0, lastDash);
        final forgeVersion = full.substring(lastDash + 1);
        map.putIfAbsent(mcVersion, () => []).add(forgeVersion);
      }

      // 按 MC 版本号降序排列（最新版本在前）。
      final sortedKeys = map.keys.toList()
        ..sort((a, b) {
          final pa = a.split('.').map(int.tryParse).toList();
          final pb = b.split('.').map(int.tryParse).toList();
          for (int i = 0; i < 3; i++) {
            final va = i < pa.length ? (pa[i] ?? 0) : 0;
            final vb = i < pb.length ? (pb[i] ?? 0) : 0;
            if (va != vb) return vb.compareTo(va);
          }
          return 0;
        });

      return {for (final k in sortedKeys) k: map[k]!};
    } finally {
      client.close();
    }
  }

  /// 解析 NeoForge Maven 元数据 XML，返回 {mcVersion: [neoforgeVersion...]}。
  /// NeoForge 版本格式为 "major.minor.patch.build[-beta]"，
  /// 其中 major.minor.patch 对应 MC 版本号（1.major.minor.patch 或 major.minor.patch）。
  Future<Map<String, List<String>>> _fetchAllNeoforgeVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml',
        ),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();

      // 解析 XML 中的 <version> 标签。
      final versionPattern = RegExp(r'<version>([^<]+)</version>');
      final matches = versionPattern.allMatches(body);

      // 按 MC 版本分组。
      // NeoForge 版本格式：
      //   三段式 major.minor.build[-beta]（如 21.1.234 → MC 1.21.1）
      //   四段式 major.minor.patch.build[-beta]（如 26.1.2.71 → MC 26.1.2）
      final map = <String, List<String>>{};
      for (final m in matches) {
        final full = m.group(1)!;
        // 过滤掉 beta 版本。
        if (full.contains('-beta')) continue;
        // 分割版本号段（去掉可能的 -beta 后缀）。
        final cleanFull = full.split('-').first;
        final parts = cleanFull.split('.');
        if (parts.length < 3) continue;
        final String mcVersion;
        if (parts.length >= 4) {
          // 四段式：MC 版本 = 前三段。
          mcVersion = '${parts[0]}.${parts[1]}.${parts[2]}';
        } else {
          // 三段式：MC 版本 = 前两段。
          mcVersion = '${parts[0]}.${parts[1]}';
        }
        map.putIfAbsent(mcVersion, () => []).add(full);
      }

      // 按 MC 版本号降序排列（最新版本在前）。
      final sortedKeys = map.keys.toList()
        ..sort((a, b) {
          final pa = a.split('.').map(int.tryParse).toList();
          final pb = b.split('.').map(int.tryParse).toList();
          for (int i = 0; i < 3; i++) {
            final va = i < pa.length ? (pa[i] ?? 0) : 0;
            final vb = i < pb.length ? (pb[i] ?? 0) : 0;
            if (va != vb) return vb.compareTo(va);
          }
          return 0;
        });

      return {for (final k in sortedKeys) k: map[k]!};
    } finally {
      client.close();
    }
  }

  /// 获取官方端版本列表，同时缓存每个版本的详情 URL。
  Future<List<String>> _fetchVanillaVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://launchermeta.mojang.com/mc/game/version_manifest.json',
        ),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final versions = json['versions'] as List<dynamic>;
      final releases = versions.where((v) => v['type'] == 'release').toList();

      _vanillaVersionUrls = {
        for (final v in releases) v['id'] as String: v['url'] as String,
      };

      return releases.map<String>((v) => v['id'] as String).toList();
    } finally {
      client.close();
    }
  }

  /// 获取 Paper 端版本列表，过滤掉含 rc/pre 的预发布版本。
  Future<List<String>> _fetchPaperVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('https://fill.papermc.io/v3/projects/paper'),
      );
      req.headers.set('User-Agent', 'EdgeCube/1.0');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final versions = json['versions'] as Map<String, dynamic>;
      final result = <String>[];
      for (final group in versions.keys) {
        final groupVersions = versions[group] as List<dynamic>;
        for (final v in groupVersions) {
          final lower = (v as String).toLowerCase();
          if (!lower.contains('rc') && !lower.contains('pre')) {
            result.add(v);
          }
        }
      }
      return result;
    } finally {
      client.close();
    }
  }

  /// 镜像开启且成功时返回 MSL 下载信息，否则返回 null（调用方回退官方源）。
  Future<_DownloadInfo?> _tryMirrorDownloadInfo(
    String serverType,
    String version,
  ) async {
    if (!await NetworkStore.loadUseMirror()) return null;
    final info = await MslMirror.fetchDownloadInfo(serverType, version);
    if (info == null) return null;
    return _DownloadInfo(url: info.url, sha256: info.sha256);
  }

  /// 将 NeoForge 流程中的 MC 版本键转换为 MSL 镜像所用的版本格式。
  /// 旧命名（如 `21.1`）加 `1.` 前缀得 `1.21.1`；年份命名（如 `26.1.2`）直接沿用。
  String _neoforgeMcToMslVersion(String key) {
    final major = int.tryParse(key.split('.').first) ?? 0;
    return major >= 26 ? key : '1.$key';
  }

  /// 根据服务端类型获取指定版本的下载信息。
  Future<_DownloadInfo> _fetchDownloadInfo(String version) async {
    if (_serverType == 'vanilla') {
      return _fetchVanillaDownloadInfo(version);
    } else if (_serverType == 'velocity') {
      return _fetchVelocityDownloadInfo(version);
    } else if (_serverType == 'powernukkitx') {
      return _fetchPowernukkitxDownloadInfo(version);
    } else {
      return _fetchPaperDownloadInfo(version);
    }
  }

  /// Fabric 下载信息：查询最新 Installer 版本并组装直接下载 URL。
  Future<_DownloadInfo> _fetchFabricDownloadInfo() async {
    final mcVersion = _selectedMcVersion!;
    final loaderVersion = _selectedLoaderVersion!;

    final client = HttpClient();
    try {
      // 获取最新 Installer 版本。
      final req = await client.getUrl(
        Uri.parse('https://meta.fabricmc.net/v2/versions/installer'),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as List<dynamic>;
      final latestInstaller = json.first['version'] as String;

      return _DownloadInfo(
        url:
            'https://meta.fabricmc.net/v2/versions/loader/$mcVersion/$loaderVersion/$latestInstaller/server/jar',
      );
    } finally {
      client.close();
    }
  }

  /// 从版本详情 JSON 获取官方端服务端的真实下载 URL 和 SHA-1。
  Future<_DownloadInfo> _fetchVanillaDownloadInfo(String version) async {
    final detailUrl = _vanillaVersionUrls[version];
    if (detailUrl == null) {
      throw Exception(
        tr('instance.versionDetailNotFound', {'version': version}),
      );
    }
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(detailUrl));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final server = json['downloads']?['server'];
      if (server == null) {
        throw Exception(tr('instance.noServerJar'));
      }
      return _DownloadInfo(
        url: server['url'] as String,
        sha1: server['sha1'] as String?,
      );
    } finally {
      client.close();
    }
  }

  /// 获取 Velocity 端版本列表，显示快照版本（过滤 rc/pre）。
  Future<List<String>> _fetchVelocityVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('https://fill.papermc.io/v3/projects/velocity'),
      );
      req.headers.set('User-Agent', 'EdgeCube/1.0');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final versions = json['versions'] as Map<String, dynamic>;
      final result = <String>[];
      for (final group in versions.keys) {
        final groupVersions = versions[group] as List<dynamic>;
        for (final v in groupVersions) {
          final lower = (v as String).toLowerCase();
          if (!lower.contains('rc') && !lower.contains('pre')) {
            result.add(v);
          }
        }
      }
      return result;
    } finally {
      client.close();
    }
  }

  /// 通过 PaperMC Fill v3 API 获取 Velocity 最新构建的下载 URL 和 SHA-256。
  Future<_DownloadInfo> _fetchVelocityDownloadInfo(String version) async {
    final client = HttpClient();
    try {
      final buildReq = await client.getUrl(
        Uri.parse(
          'https://fill.papermc.io/v3/projects/velocity/versions/$version/builds/latest',
        ),
      );
      buildReq.headers.set('User-Agent', 'EdgeCube/1.0');
      final buildRes = await buildReq.close();
      final buildBody = await buildRes.transform(utf8.decoder).join();
      final buildJson = jsonDecode(buildBody) as Map<String, dynamic>;
      final serverDefault =
          (buildJson['downloads'] as Map<String, dynamic>)['server:default']
              as Map<String, dynamic>;
      final sha256 =
          (serverDefault['checksums'] as Map<String, dynamic>)['sha256']
              as String;
      final downloadUrl = serverDefault['url'] as String;
      return _DownloadInfo(url: downloadUrl, sha256: sha256);
    } finally {
      client.close();
    }
  }

  /// 通过 PaperMC Fill v3 API 获取 Paper 最新构建的下载 URL 和 SHA-256。
  Future<_DownloadInfo> _fetchPaperDownloadInfo(String version) async {
    final client = HttpClient();
    try {
      final buildReq = await client.getUrl(
        Uri.parse(
          'https://fill.papermc.io/v3/projects/paper/versions/$version/builds/latest',
        ),
      );
      buildReq.headers.set('User-Agent', 'EdgeCube/1.0');
      final buildRes = await buildReq.close();
      final buildBody = await buildRes.transform(utf8.decoder).join();
      final buildJson = jsonDecode(buildBody) as Map<String, dynamic>;
      final serverDefault =
          (buildJson['downloads'] as Map<String, dynamic>)['server:default']
              as Map<String, dynamic>;
      final sha256 =
          (serverDefault['checksums'] as Map<String, dynamic>)['sha256']
              as String;
      final downloadUrl = serverDefault['url'] as String;
      return _DownloadInfo(url: downloadUrl, sha256: sha256);
    } finally {
      client.close();
    }
  }

  /// 从 GitHub Releases 获取 PowerNukkitX 版本列表（tag_name）。
  Future<List<String>> _fetchPowernukkitxVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://api.github.com/repos/PowerNukkitX/PowerNukkitX/releases',
        ),
      );
      req.headers.set('User-Agent', 'EdgeCube/1.0');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as List<dynamic>;
      return json
          .map<String>((r) => (r as Map<String, dynamic>)['tag_name'] as String)
          .toList();
    } finally {
      client.close();
    }
  }

  /// 从 GitHub Release Assets 获取 PowerNukkitX 指定版本的 jar 下载 URL。
  Future<_DownloadInfo> _fetchPowernukkitxDownloadInfo(
    String version,
  ) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://api.github.com/repos/PowerNukkitX/PowerNukkitX/releases/tags/$version',
        ),
      );
      req.headers.set('User-Agent', 'EdgeCube/1.0');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final assets = json['assets'] as List<dynamic>;
      // 优先匹配 shaded jar，否则取第一个 jar。
      String? downloadUrl;
      for (final asset in assets) {
        final name = (asset as Map<String, dynamic>)['name'] as String;
        if (name.endsWith('.jar')) {
          downloadUrl = asset['browser_download_url'] as String;
          if (name.toLowerCase().contains('shaded')) break;
        }
      }
      if (downloadUrl == null) {
        throw Exception('No JAR found in release $version');
      }
      return _DownloadInfo(url: downloadUrl);
    } finally {
      client.close();
    }
  }
}

/// 服务端 JAR 的下载信息。
class _DownloadInfo {
  const _DownloadInfo({required this.url, this.sha1, this.sha256});

  final String url;
  final String? sha1;
  final String? sha256;
}

/// 服务端类型选择项。
class _ServerTypeTile extends StatelessWidget {
  const _ServerTypeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 36),
        title: Text(title, style: const TextStyle(fontSize: 16)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: onTap,
      ),
    );
  }
}

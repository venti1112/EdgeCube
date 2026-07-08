import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:flutter/material.dart';
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
import 'download_info.dart';
import 'download_info_service.dart';
import 'name_entry_step.dart';
import 'progress_steps.dart';
import 'server_select_step.dart';
import 'version_fetch_service.dart';
import 'version_select_step.dart';
import 'forge_installer_page.dart';

enum _WizardStep {
  nameEntry,
  editionSelect,
  javaServerCategory,
  serverType,
  bedrockServerType,
  versionSelect,
  fabricMcVersionSelect,
  fabricLoaderVersionSelect,
  forgeMcVersionSelect,
  forgeVersionSelect,
  neoforgeMcVersionSelect,
  neoforgeVersionSelect,
  downloading,
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
/// 2a. 下载服务端 → 选版本（Java 版 / 基岩版） → 选类型分类（原版/插件/模组/代理）
///     → 选类型 → 选版本 → 创建实例并下载
///     - 原版：Vanilla
///     - 插件服：Paper/Spigot/CraftBukkit/Purpur/Leaf/Leaves
///     - 模组服：Fabric/Forge/NeoForge
///     - 代理端：Velocity/BungeeCord
///     - 基岩版类型：PowerNukkitX
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
  String? _javaServerCategory;
  List<String> _versions = [];
  bool _loadingVersions = false;
  String? _versionError;
  double? _downloadProgress;
  String? _downloadError;
  bool _completed = false;

  /// 缓存版本详情页 URL（Vanilla）。
  Map<String, String> _vanillaVersionUrls = {};

  /// 缓存 PocketMine-MP 版本对应的 MCBE 客户端版本（version → mcpe_version）。
  final Map<String, String> _pocketmineMcpeVersions = {};

  /// 缓存 PowerNukkitX 版本对应的 MCBE 客户端版本（version → mc_version）。
  final Map<String, String> _powernukkitxMcVersions = {};

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

  bool _extracting = false;
  String? _extractError;
  double? _extractProgress;

  /// 整合包导入状态。
  String _modpackPhase =
      ''; // parsing / downloading / extracting / preparing / idle
  int _modpackCurrent = 0;
  int _modpackTotal = 0;
  String _modpackCurrentFile = '';
  String? _modpackError;

  static const Map<String, List<String>> _javaServerCategories = {
    'vanilla': ['vanilla'],
    'plugin': ['paper', 'spigot', 'craftbukkit', 'purpur', 'leaf', 'leaves'],
    'mod': ['fabric', 'forge', 'neoforge'],
    'proxy': ['velocity', 'bungeecord'],
  };

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
    setState(() => _step = _WizardStep.editionSelect);
  }

  /// 选择版本：Java 版 → 进入 Java 服务端分类选择页。
  void _selectJavaEdition() {
    setState(() => _step = _WizardStep.javaServerCategory);
  }

  /// 选择 Java 服务端分类并跳转到该分类下的具体服务端类型列表。
  void _selectJavaServerCategory(String category) {
    setState(() {
      _javaServerCategory = category;
      _step = _WizardStep.serverType;
    });
  }

  /// 选择版本：基岩版 → 进入基岩服务端类型选择页。
  void _selectBedrockEdition() {
    setState(() => _step = _WizardStep.bedrockServerType);
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
        _fabricMcVersions = await VersionFetchService.fetchFabricMcVersions();
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
        _forgeVersionMap = await VersionFetchService.fetchAllForgeVersions();
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
        _neoforgeVersionMap = await VersionFetchService.fetchAllNeoforgeVersions();
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
    if (type == 'dragonfly') {
      setState(() {
        _step = _WizardStep.nameEntry;
        _loadingVersions = false;
        _versionError = null;
        _versions = [];
      });
      return;
    }
    if (type == 'bungeecord') {
      setState(() {
        _step = _WizardStep.nameEntry;
        _loadingVersions = false;
        _versionError = null;
        _versions = [];
      });
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
    final sourcePath = await pickFromSystem(
      context,
      mode: SystemPickMode.file,
      // 与原生 ArchiveExtractor 支持的格式保持一致。
      allowedExtensions: const [
        '.zip',
        '.tar',
        '.tar.gz',
        '.tgz',
        '.tar.xz',
        '.txz',
        '.tar.bz2',
        '.tbz2',
        '.tar.zst',
        '.tzst',
        '.tar.lz4',
        '.7z',
      ],
    );
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
        _extractError = context.tr('instance.extractArchiveFailed', {
          'error': '$e',
        });
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

  Future<void> _createDragonflyInstance() async {
    if (!await _validateName()) return;
    final name = _nameController.text.trim();
    try {
      final instance = await _instanceController.createInstance(name);
      await _instanceController.updateConfig(
        instance.id,
        runtime: kRuntimeDragonfly,
      );
      final dir = await _instanceController.directoryForId(instance.id);
      final configYml = [
        'network:',
        '  address: ":19132"',
        'server:',
        '  name: "$name"',
        '  authenabled: true',
        'world:',
        '  folder: "world"',
        'players:',
        '  folder: "players"',
        '',
      ].join('\n');
      await File(p.join(dir.path, 'config.yml')).writeAsString(configYml);
      _instanceId = instance.id;
      _completed = true;
      _finishWizard();
    } on DuplicateInstanceNameException {
      if (!mounted) return;
      _showDuplicateDialog(name);
    }
  }

  Future<void> _createAndDownloadBungeeCord() async {
    if (!await _validateName()) return;
    final name = _nameController.text.trim();
    try {
      final instance = await _instanceController.createInstance(name);
      if (!mounted) return;
      _instanceId = instance.id;
      setState(() => _step = _WizardStep.downloading);
      await _fetchAndDownloadBungeeCord(instance.id);
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
    final sourcePath = await pickFromSystem(
      context,
      mode: SystemPickMode.file,
      allowedExtensions: const ['.mrpack', '.zip'],
    );
    if (sourcePath == null) {
      _deleteCreatedInstance();
      _closeWizard();
      return;
    }

    setState(() => _modpackPhase = 'parsing');
    try {
      final format = await ModpackService.detectFormat(sourcePath);
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
      if (mounted) {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => ForgeInstallerPage(
              instanceController: _instanceController,
              instanceId: instanceId,
              mcVersion: mcVersion,
              forgeVersion: forge,
              installerType: 'forge',
            ),
          ),
        );
        if (result == true && mounted) {
          _completed = true;
          _finishWizard();
        }
      }
      return;
    } else if (neoforge != null) {
      _serverType = 'neoforge';
      final neoforgeMcKey = _deriveNeoforgeMcKey(neoforge);
      if (mounted) {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => ForgeInstallerPage(
              instanceController: _instanceController,
              instanceId: instanceId,
              mcVersion: neoforgeMcKey,
              forgeVersion: neoforge,
              installerType: 'neoforge',
            ),
          ),
        );
        if (result == true && mounted) {
          _completed = true;
          _finishWizard();
        }
      }
      return;
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
    final sourcePath = await pickFromSystem(
      context,
      mode: SystemPickMode.file,
      allowedExtensions: const ['.jar', '.phar'],
    );
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
    // PocketMine-MP / PowerNukkitX 额外显示对应的 MCBE 客户端版本。
    final isPocketmine = _serverType == 'pocketmine';
    final isPowernukkitx = _serverType == 'powernukkitx';
    final isAllay = _serverType == 'allay';
    final mcpeVersion = isPocketmine
        ? _pocketmineMcpeVersions[version]
        : (isPowernukkitx ? _powernukkitxMcVersions[version] : null);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('instance.confirmVersionTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isPocketmine
                  ? context.tr('instance.confirmDownloadPmmp', {
                      'version': version,
                    })
                  : isPowernukkitx
                      ? context.tr('instance.confirmDownloadPowernukkitx', {
                          'version': version,
                        })
                      : isAllay
                          ? context.tr('instance.confirmDownloadAllay', {
                              'version': version,
                            })
                          : context.tr('instance.confirmDownload', {
                              'version': version,
                            }),
            ),
            if (mcpeVersion != null) ...[
              const SizedBox(height: 8),
              Text(
                context.tr('instance.mcpeVersionLabel', {
                  'version': mcpeVersion,
                }),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ],
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
      _versions = await VersionFetchService.fetchFabricLoaderVersions(mcVersion);
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
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ForgeInstallerPage(
            instanceController: _instanceController,
            instanceId: instance.id,
            mcVersion: _selectedForgeMcVersion!,
            forgeVersion: forgeVersion,
            installerType: 'forge',
          ),
        ),
      );
      if (result == true && mounted) {
        _completed = true;
        _finishWizard();
      }
    } on DuplicateInstanceNameException {
      if (!mounted) return;
      _showDuplicateDialog(name);
    }
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
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ForgeInstallerPage(
            instanceController: _instanceController,
            instanceId: instance.id,
            mcVersion: _selectedNeoforgeMcVersion!,
            forgeVersion: neoforgeVersion,
            installerType: 'neoforge',
          ),
        ),
      );
      if (result == true && mounted) {
        _completed = true;
        _finishWizard();
      }
    } on DuplicateInstanceNameException {
      if (!mounted) return;
      _showDuplicateDialog(name);
    }
  }

  /// 在下载页中先获取下载信息，再执行下载（Vanilla / Paper / PocketMine-MP）。
  Future<void> _fetchAndDownload(String instanceId, String version) async {
    setState(() {
      _downloadProgress = null;
      _downloadError = null;
    });

    DownloadInfo info;
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

    final String jarName;
    if (_serverType == 'powernukkitx') {
      jarName = 'powernukkitx.jar';
    } else if (_serverType == 'pocketmine') {
      jarName = 'PocketMine-MP.phar';
    } else if (_serverType == 'allay') {
      jarName = 'allay-server.jar';
    } else {
      jarName = 'server.jar';
    }
    await _downloadJar(instanceId, info, jarName: jarName);
  }

  /// Fabric 下载流程：获取最新 Installer 版本并构造下载 URL。
  Future<void> _fetchAndDownloadFabric(String instanceId) async {
    setState(() {
      _downloadProgress = null;
      _downloadError = null;
    });

    DownloadInfo info;
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

  Future<void> _fetchAndDownloadBungeeCord(String instanceId) async {
    setState(() {
      _downloadProgress = null;
      _downloadError = null;
    });

    DownloadInfo info;
    try {
      info =
          await _tryMirrorDownloadInfo('bungeecord', 'latest') ??
          await DownloadInfoService.fetchBungeeCordDownloadInfo();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _downloadError = context.tr('instance.fetchDownloadInfoFailed', {
          'error': '$e',
        }),
      );
      return;
    }

    await _downloadJar(instanceId, info, jarName: 'bungeecord.jar');
  }

  Future<void> _downloadJar(
    String instanceId,
    DownloadInfo info, {
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
      if (_serverType == 'pocketmine') {
        // PocketMine-MP 使用 PHP 运行环境，无需 Java 版本。
        await _instanceController.updateConfig(
          instanceId,
          selectedJar: jarName,
          runtime: kRuntimePhp,
        );
        _completed = true;
        if (mounted) _finishWizard();
        return;
      } else if (_serverType == 'powernukkitx') {
        javaVer = await _resolveJavaVersion('1.20.5');
      } else if (_serverType == 'allay') {
        // Allay 需要 Java 21 及以上。
        javaVer = await _resolveJavaVersion('1.21');
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
  bool _verifyHash(Uint8List bytes, DownloadInfo info) {
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
      case _WizardStep.editionSelect:
        setState(() => _step = _WizardStep.nameEntry);
      case _WizardStep.javaServerCategory:
        setState(() => _step = _WizardStep.editionSelect);
      case _WizardStep.serverType:
        setState(() => _step = _WizardStep.javaServerCategory);
      case _WizardStep.bedrockServerType:
        setState(() => _step = _WizardStep.editionSelect);
      case _WizardStep.versionSelect:
        setState(() => _step = (_serverType == 'powernukkitx' ||
                _serverType == 'pocketmine' ||
                _serverType == 'allay')
            ? _WizardStep.bedrockServerType
            : _WizardStep.javaServerCategory);
      case _WizardStep.fabricMcVersionSelect:
        setState(() {
          _step = _WizardStep.javaServerCategory;
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
          _step = _WizardStep.javaServerCategory;
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
          _step = _WizardStep.javaServerCategory;
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
      _WizardStep.editionSelect => context.tr('instance.titleSelectEdition'),
      _WizardStep.javaServerCategory => context.tr('instance.titleJavaServerCategory'),
      _WizardStep.serverType => context.tr('instance.titleJavaServerType'),
      _WizardStep.bedrockServerType => context.tr('instance.titleBedrockServerType'),
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
      _WizardStep.importFile => context.tr('instance.titleImportServer'),
      _WizardStep.importArchive => context.tr('instance.titleImportServer'),
      _WizardStep.extractArchive => context.tr('instance.titleImportArchive'),
      _WizardStep.modpackImport => context.tr('instance.titleModpackImport'),
    };
  }

  Widget _buildStepContent(ThemeData theme) {
    return switch (_step) {
      _WizardStep.nameEntry => _buildNameEntry(theme),
      _WizardStep.editionSelect => _buildEditionSelect(theme),
      _WizardStep.javaServerCategory => _buildJavaServerCategorySelect(theme),
      _WizardStep.serverType => _buildServerTypeSelect(theme),
      _WizardStep.bedrockServerType => _buildBedrockServerTypeSelect(theme),
      _WizardStep.versionSelect => _buildVersionSelect(theme),
      _WizardStep.fabricMcVersionSelect => _buildVersionSelect(theme),
      _WizardStep.fabricLoaderVersionSelect => _buildVersionSelect(theme),
      _WizardStep.forgeMcVersionSelect => _buildVersionSelect(theme),
      _WizardStep.forgeVersionSelect => _buildVersionSelect(theme),
      _WizardStep.neoforgeMcVersionSelect => _buildVersionSelect(theme),
      _WizardStep.neoforgeVersionSelect => _buildVersionSelect(theme),
      _WizardStep.downloading => _buildDownloading(theme),
      _WizardStep.importFile => _buildImporting(theme),
      _WizardStep.importArchive => _buildImporting(theme),
      _WizardStep.extractArchive => _buildExtractingArchive(theme),
      _WizardStep.modpackImport => _buildModpackImport(theme),
    };
  }

  Widget _buildNameEntry(ThemeData theme) {
    return NameEntryStep(
      controller: _nameController,
      showDragonflyTile: _serverType == 'dragonfly',
      showBungeeCordTile: _serverType == 'bungeecord',
      onGoToServerType: _goToServerType,
      onStartImport: _startImport,
      onStartArchive: _startImportArchive,
      onStartModpack: _startModpackImport,
      onCreateDragonfly: _createDragonflyInstance,
      onCreateBungeeCord: _createAndDownloadBungeeCord,
      onCreateEmpty: _createEmptyInstance,
    );
  }

  Widget _buildEditionSelect(ThemeData theme) {
    return EditionSelectStep(
      onSelectJavaEdition: _selectJavaEdition,
      onSelectBedrockEdition: _selectBedrockEdition,
    );
  }

  Widget _buildJavaServerCategorySelect(ThemeData theme) {
    return JavaServerCategoryStep(
      onSelectCategory: _selectJavaServerCategory,
    );
  }

  Widget _buildServerTypeSelect(ThemeData theme) {
    final types = _javaServerCategories[_javaServerCategory] ?? <String>[];
    return ServerTypeTileList(
      types: types,
      onSelect: _selectServerType,
    );
  }

  Widget _buildBedrockServerTypeSelect(ThemeData theme) {
    return ServerTypeTileList(
      types: const ['pocketmine', 'powernukkitx', 'allay', 'dragonfly'],
      onSelect: _selectServerType,
    );
  }

  /// 步骤 3a/3b/4b：版本列表选择（Vanilla、Paper、Fabric MC、Fabric Loader）。
  Widget _buildVersionSelect(ThemeData theme) {
    final isVersionSelect = _step == _WizardStep.versionSelect;
    final isPocketmineList = _serverType == 'pocketmine' && isVersionSelect;
    final isPowernukkitxList =
        _serverType == 'powernukkitx' && isVersionSelect;
    final Map<String, String>? subtitles;
    if (isPocketmineList) {
      subtitles = {
        for (final v in _versions)
          if (_pocketmineMcpeVersions.containsKey(v))
            v: context.tr('instance.pmmpVersionLabel', {
              'version': v,
            }),
      };
    } else if (isPowernukkitxList) {
      subtitles = {
        for (final v in _versions)
          if (_powernukkitxMcVersions.containsKey(v))
            v: context.tr('instance.pnxVersionLabel', {
              'version': v,
            }),
      };
    } else {
      subtitles = null;
    }
    final List<String> displayVersions;
    if (isPocketmineList) {
      displayVersions = _versions.map((v) => _pocketmineMcpeVersions[v] ?? v).toList();
    } else if (isPowernukkitxList) {
      displayVersions = _versions.map((v) => _powernukkitxMcVersions[v] ?? v).toList();
    } else {
      displayVersions = _versions;
    }
    return VersionSelectStep(
      versions: displayVersions,
      loading: _loadingVersions,
      error: _versionError,
      subtitles: subtitles,
      onRetry: () {
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
      onSelect: (v) {
        final originalVersion = isPocketmineList || isPowernukkitxList
            ? _versions[displayVersions.indexOf(v)]
            : v;
        switch (_step) {
          case _WizardStep.versionSelect:
            _selectVersion(originalVersion);
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
  }

  /// 步骤 4a：下载进度页。
  Widget _buildDownloading(ThemeData theme) {
    return DownloadingStep(
      progress: _downloadProgress,
      error: _downloadError,
      onRetry: () {
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
      onCancel: _deleteCreatedInstance,
    );
  }

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
    return ExtractingArchiveStep(
      extracting: _extracting,
      progress: _extractProgress,
      error: _extractError,
      onCancel: _deleteCreatedInstance,
      onReselect: () {
        _deleteCreatedInstance();
        setState(() => _step = _WizardStep.nameEntry);
      },
    );
  }

  /// 整合包导入进度页。
  Widget _buildModpackImport(ThemeData theme) {
    return ModpackImportStep(
      phase: _modpackPhase,
      current: _modpackCurrent,
      total: _modpackTotal,
      currentFile: _modpackCurrentFile,
      error: _modpackError,
      onCancel: _deleteCreatedInstance,
    );
  }

  // —— 网络请求 ——

  Future<List<String>> _fetchVersions(String type) async {
    if (type == 'vanilla') {
      return _fetchVanillaVersions();
    } else if (type == 'paper') {
      return VersionFetchService.fetchPaperVersions();
    } else if (type == 'spigot') {
      return VersionFetchService.fetchSpigotVersions();
    } else if (type == 'craftbukkit') {
      return VersionFetchService.fetchCraftBukkitVersions();
    } else if (type == 'purpur') {
      return VersionFetchService.fetchPurpurVersions();
    } else if (type == 'leaf') {
      return VersionFetchService.fetchLeafVersions();
    } else if (type == 'leaves') {
      return VersionFetchService.fetchLeavesVersions();
    } else if (type == 'powernukkitx') {
      return _fetchPowernukkitxVersions();
    } else if (type == 'pocketmine') {
      return _fetchPocketmineVersions();
    } else if (type == 'allay') {
      return VersionFetchService.fetchAllayVersions();
    } else {
      return VersionFetchService.fetchVelocityVersions();
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

  /// 镜像开启且成功时返回 MSL 下载信息，否则返回 null（调用方回退官方源）。
  Future<DownloadInfo?> _tryMirrorDownloadInfo(
    String serverType,
    String version,
  ) async {
    if (!await NetworkStore.loadUseMirror()) return null;
    final info = await MslMirror.fetchDownloadInfo(serverType, version);
    if (info == null) return null;
    return DownloadInfo(url: info.url, sha256: info.sha256);
  }

  /// 根据服务端类型获取指定版本的下载信息。
  Future<DownloadInfo> _fetchDownloadInfo(String version) async {
    if (_serverType == 'vanilla') {
      return _fetchVanillaDownloadInfo(version);
    } else if (_serverType == 'velocity') {
      return DownloadInfoService.fetchVelocityDownloadInfo(version);
    } else if (_serverType == 'spigot') {
      return DownloadInfoService.fetchSpigotDownloadInfo(version);
    } else if (_serverType == 'craftbukkit') {
      return DownloadInfoService.fetchCraftBukkitDownloadInfo(version);
    } else if (_serverType == 'purpur') {
      return DownloadInfoService.fetchPurpurDownloadInfo(version);
    } else if (_serverType == 'leaf') {
      return DownloadInfoService.fetchLeafDownloadInfo(version);
    } else if (_serverType == 'leaves') {
      return DownloadInfoService.fetchLeavesDownloadInfo(version);
    } else if (_serverType == 'powernukkitx') {
      return DownloadInfoService.fetchPowernukkitxDownloadInfo(version);
    } else if (_serverType == 'pocketmine') {
      return DownloadInfoService.fetchPocketmineDownloadInfo(version);
    } else if (_serverType == 'allay') {
      return DownloadInfoService.fetchAllayDownloadInfo(version);
    } else {
      return DownloadInfoService.fetchPaperDownloadInfo(version);
    }
  }

  /// Fabric 下载信息：查询最新 Installer 版本并组装直接下载 URL。
  Future<DownloadInfo> _fetchFabricDownloadInfo() async {
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

      return DownloadInfo(
        url:
            'https://meta.fabricmc.net/v2/versions/loader/$mcVersion/$loaderVersion/$latestInstaller/server/jar',
      );
    } finally {
      client.close();
    }
  }

  /// 从版本详情 JSON 获取官方端服务端的真实下载 URL 和 SHA-1。
  Future<DownloadInfo> _fetchVanillaDownloadInfo(String version) async {
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
      return DownloadInfo(
        url: server['url'] as String,
        sha1: server['sha1'] as String?,
      );
    } finally {
      client.close();
    }
  }
  /// 从 GitHub Releases 获取 PowerNukkitX 版本列表（tag_name），
  /// 同时从 release body 中提取 MCBE 版本号缓存在 [_powernukkitxMcVersions]。
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
      final mcVersionRegex = RegExp(
        r'\|\s*\*\*Supported Minecraft Version\*\*\s*\|\s*([\d.]+)\s*\|',
      );
      final versions = <String>[];
      _powernukkitxMcVersions.clear();
      for (final r in json) {
        final release = r as Map<String, dynamic>;
        final tagName = release['tag_name'] as String;
        versions.add(tagName);
        final bodyText = release['body'] as String?;
        if (bodyText != null) {
          final match = mcVersionRegex.firstMatch(bodyText);
          if (match != null) {
            _powernukkitxMcVersions[tagName] = match.group(1)!;
          }
        }
      }
      return versions;
    } finally {
      client.close();
    }
  }
  /// 获取 PocketMine-MP 版本列表。
  ///
  /// 数据源：https://github.com/pmmp/update.pmmp.io/tree/master/channels
  /// 列出 channels 目录下所有 JSON 文件，筛选出 5.x 稳定版本（PHP 运行环境
  /// 仅支持 PocketMine-MP 5.0 及以上），按版本号降序返回。
  ///
  /// 同时并发获取每个版本的 mcpe_version，缓存在 [_pocketmineMcpeVersions]
  /// 供版本列表副标题展示。
  Future<List<String>> _fetchPocketmineVersions() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://api.github.com/repos/pmmp/update.pmmp.io/contents/channels',
        ),
      );
      req.headers.set('User-Agent', 'EdgeCube/1.0');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as List<dynamic>;

      // 仅匹配 5.x 稳定版本文件名（如 5、5.44、5.25.0），排除 alpha/beta 等。
      final versionPattern = RegExp(r'^5(\.\d+)*$');
      final versions = <String>[];
      for (final item in json) {
        final name = (item as Map<String, dynamic>)['name'] as String;
        if (!name.endsWith('.json')) continue;
        final base = name.substring(0, name.length - 5); // 去掉 .json
        if (!versionPattern.hasMatch(base)) continue;
        versions.add(base);
      }

      // 按版本号降序排列（最新版本在前）。
      versions.sort((a, b) {
        final pa = a.split('.').map(int.tryParse).toList();
        final pb = b.split('.').map(int.tryParse).toList();
        final len = pa.length > pb.length ? pa.length : pb.length;
        for (int i = 0; i < len; i++) {
          final va = i < pa.length ? (pa[i] ?? 0) : 0;
          final vb = i < pb.length ? (pb[i] ?? 0) : 0;
          if (va != vb) return vb.compareTo(va);
        }
        return 0;
      });

      // 并发获取每个版本的 mcpe_version，缓存到 _pocketmineMcpeVersions。
      _pocketmineMcpeVersions.clear();
      await Future.wait(
        versions.map((v) => _fetchPocketmineMcpeVersion(client, v)),
      );

      return versions;
    } finally {
      client.close();
    }
  }

  /// 获取单个 PocketMine-MP 版本对应的 MCBE 客户端版本。
  ///
  /// 从 `channels/<version>.json` 中读取 `mcpe_version` 字段，
  /// 成功时写入 [_pocketmineMcpeVersions]；失败时静默跳过（不影响版本列表）。
  Future<void> _fetchPocketmineMcpeVersion(
    HttpClient client,
    String version,
  ) async {
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://raw.githubusercontent.com/pmmp/update.pmmp.io/master/channels/$version.json',
        ),
      );
      req.headers.set('User-Agent', 'EdgeCube/1.0');
      final res = await req.close();
      if (res.statusCode != 200) return;
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final mcpe = json['mcpe_version'] as String?;
      if (mcpe != null && mcpe.isNotEmpty) {
        _pocketmineMcpeVersions[version] = mcpe;
      }
    } catch (_) {
      // 单个版本获取失败不影响整体列表。
    }
  }
}


